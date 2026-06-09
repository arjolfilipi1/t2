## GameDirector.gd
## The central coordinator. Owns all domain systems and is the single
## entry point for player input. Nothing outside this node mutates
## game state directly — everything goes through submit_action().
##
## Responsibilities:
##   1. Boot and wire all domain systems (ZoneManager, EffectStack,
##      TurnManager, RuleEngine)
##   2. Receive GameAction objects and validate → execute them
##   3. Drive the battle sub-phase loop (BATTLE_STEP → DAMAGE_STEP)
##   4. Expose query helpers for UI (legal actions, context)
##   5. Emit high-level signals the UI subscribes to
##
## Usage:
##   var gd := GameDirector.new()
##   add_child(gd)
##   gd.setup(players, deck_data)
##   gd.start_game()
##   # Then route all player input through:
##   gd.submit_action(GameAction.NormalSummonAction.make(p1, card))
class_name GameDirector
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## An action was validated and executed successfully.
signal action_executed(action: GameAction)

## An action was rejected — carries the reason.
signal action_rejected(action: GameAction, result: RuleResult)

## A card was summoned (after the summon trigger window resolves).
signal card_summoned(card: CardInstance, was_normal: bool)

## Battle damage was dealt.
signal damage_dealt(amount: int, to_player: Player, from_battle: bool)

## The game has ended.
signal game_over(winner: Player, loser: Player)

## The active player changed (for UI turn indicators).
signal active_player_changed(player: Player)

## Phase changed — UI updates HUD.
signal phase_changed(phase_name: String, turn: int, active_player: Player)

## Waiting for the local player to make a decision (targeting, discard, etc.)
signal awaiting_input(input_request: InputRequest)

## All pending input has been resolved; normal play resumes.
signal input_resolved()

# ─── Owned Systems ────────────────────────────────────────────────────────────

var zm:    ZoneManager  = null
var stack: EffectStack  = null
var tm:    TurnManager  = null

# ─── Players ──────────────────────────────────────────────────────────────────

var players: Array[Player] = []

## The local human player (index 0 by default).
var local_player: Player = null

# ─── Action History ───────────────────────────────────────────────────────────

## Every executed action in order. Used for replay and debug.
var action_log: Array[GameAction] = []
var _next_action_id: int = 0
var player_used_effects:Dictionary = {}# player -> {card_id - effect_index - turn}
# ─── Pending Input ────────────────────────────────────────────────────────────

## Set when GameDirector is waiting for the player to make a UI decision.
var _pending_input: InputRequest = null

# ─── Setup ────────────────────────────────────────────────────────────────────

## Call once after add_child(). Players must already have decks loaded via
## CardFactory / ZoneManager before calling start_game().
func setup(player_list: Array[Player]) -> void:
	players      = player_list
	local_player = players[0]

	# Build systems
	zm    = ZoneManager.new()
	stack = EffectStack.new()
	tm    = TurnManager.new()

	add_child(zm)
	add_child(stack)
	add_child(tm)

	zm.setup(players)
	stack.setup(players, zm)
	tm.setup(players, zm, stack)
	tm.turn_started.connect(_on_turn_started)

	# Register service locator for EffectResolutionStep
	EffectResolutionStep.zone_manager = zm
	EffectResolutionStep.effect_stack = stack
	EffectResolutionStep.players      = players

	# Wire internal signals
	tm.phase_changed.connect(_on_phase_changed)
	tm.active_player_changed.connect(_on_active_player_changed)
	tm.game_over.connect(_on_game_over)
	tm.card_drawn.connect(_on_card_drawn)
	stack.stack_idle.connect(_on_stack_idle)
	stack.triggers_pending.connect(_on_triggers_pending)

func _on_turn_started(turn:int,_player:Player)->void:
	stack.set_meta("current_turn",turn)

## Begin the game. Call after all decks are loaded.
func start_game() -> void:
	action_log.clear()
	_next_action_id = 0
	tm.start_game()

# ─── Action Submission ────────────────────────────────────────────────────────

## The primary entry point for all player input.
## Validates the action, executes it if legal, and emits signals.
## Returns true if the action was executed.
func submit_action(action: GameAction) -> bool:
	# Stamp the action
	action.action_id = _next_action_id
	_next_action_id  += 1
	action.timestamp = Time.get_ticks_msec() / 1000.0

	# Validate
	var result := action.validate(zm, tm, stack)
	if not result.valid:
		action_rejected.emit(action, result)
		push_warning("GameDirector: rejected '%s' — %s" % [action.describe(), result.message])
		return false

	# Inject stack ref for actions that need it (NormalSummonAction triggers)
	if action is GameAction.NormalSummonAction:
		action._stack_ref = stack

	# Execute
	action.execute(zm, tm, stack)
	action_log.append(action)
	action_executed.emit(action)

	# Post-execution hooks
	_post_action(action)

	return true

## Convenience: submit and return the RuleResult without executing.
## Useful for UI tooltip queries.
func check_action(action: GameAction) -> RuleResult:
	return action.validate(zm, tm, stack)

# ─── Convenience Action Builders ──────────────────────────────────────────────
## These let callers avoid importing GameAction themselves.

func normal_summon(player: Player, card: CardInstance,
		tributes: Array[CardInstance] = [], slot: int = -1) -> bool:
	return submit_action(GameAction.NormalSummonAction.make(player, card, tributes, slot))

func set_card(player: Player, card: CardInstance, slot: int = -1) -> bool:
	return submit_action(GameAction.SetAction.make(player, card, slot))

func activate_effect(player: Player, card: CardInstance, effect_index: int,
		targets: Array[CardInstance] = []) -> bool:
	return submit_action(GameAction.ActivateEffectAction.make(player, card, effect_index, targets))

func declare_attack(player: Player, attacker: CardInstance,
		target: CardInstance = null) -> bool:
	print("attack declared by "+attacker.definition.card_name )
	return submit_action(GameAction.DeclareAttackAction.make(player, attacker, target))

func change_position(player: Player, card: CardInstance,
		new_pos: CardDefinition.Position) -> bool:
	return submit_action(GameAction.ChangeBattlePositionAction.make(player, card, new_pos))

func pass_priority(player: Player) -> bool:
	print("pass_priority: ", player.display_name, " stack: ", get_stack())
	return submit_action(GameAction.PassPriorityAction.make(player))

func advance_phase(player: Player) -> bool:
	return submit_action(GameAction.AdvancePhaseAction.make(player))

# ─── Query Helpers (read-only, for UI) ────────────────────────────────────────

## Current turn context snapshot.
func context() -> TurnContext:
	return tm.context

## All legal actions the player can take right now.
func legal_actions_for(player: Player) -> LegalActions:
	return RuleEngine.get_all_legal_actions(player, zm, tm.context, stack)

## Which tooltip buttons to show for a specific card.
func tooltip_actions_for(card: CardInstance, player: Player) -> Array[CardTooltip.Action]:
	var la      := legal_actions_for(player)
	var actions: Array[CardTooltip.Action] = []

	if card in la.can_normal_summon: actions.append(CardTooltip.Action.SUMMON)
	if card in la.can_set:           actions.append(CardTooltip.Action.SET)
	if la.can_card_activate(card):   actions.append(CardTooltip.Action.ACTIVATE)
	if la.can_card_attack(card):     actions.append(CardTooltip.Action.ATTACK)
	actions.append(CardTooltip.Action.INSPECT)

	return actions

## Opponent of the given player.
func opponent_of(player: Player) -> Player:
	for p in players:
		if p != player:
			return p
	return null

## Apply LP damage (called from EffectResolutionStep helpers).
func apply_damage(player: Player, amount: int, from_battle: bool) -> void:
	player.take_damage(amount)
	damage_dealt.emit(amount, player, from_battle)

## Restore LP (called from EffectResolutionStep helpers).
func gain_life_points(player: Player, amount: int) -> void:
	player.gain_lp(amount)

# ─── Battle Sub-Phase Loop ────────────────────────────────────────────────────

## Called by stack_idle signal when we're in BATTLE_STEP and a chain just resolved.
## GameDirector checks whether to proceed to damage or wait for more actions.
func _try_advance_to_damage_step() -> void:
	if tm.context.phase != TurnContext.Phase.BATTLE_STEP:
		return
	if not stack.is_idle():
		return
	if tm.current_attacker() == null:
		return
	# Both players passed in BATTLE_STEP with an attacker declared → damage step
	tm.begin_damage_step()
	var resolve_action := GameAction.ResolveBattleDamageAction.make(
		tm.active_player(),
		tm.current_attacker(),
		tm.current_defender()
	)
	submit_action(resolve_action)

# ─── Input Request System ─────────────────────────────────────────────────────

## Pause normal flow and ask the local player for a decision.
## The UI listens to awaiting_input, presents the choice, then calls
## resolve_input() with the result.
func request_input(request: InputRequest) -> void:
	_pending_input = request
	awaiting_input.emit(request)

## Called by the UI (or AI) with the player's decision.
## Resumes whatever was waiting for input.
func resolve_input(result: Variant) -> void:
	if _pending_input == null:
		push_warning("GameDirector.resolve_input: no pending request")
		return
	var req           := _pending_input
	_pending_input    = null
	req.resolve(result)
	input_resolved.emit()

func is_awaiting_input() -> bool:
	return _pending_input != null

# ─── Post-Action Hooks ────────────────────────────────────────────────────────

func _post_action(action: GameAction) -> void:
	# Emit semantic signals for actions that have board meaning
	if action is GameAction.NormalSummonAction:
		card_summoned.emit(action.card, true)
	elif action is GameAction.DeclareAttackAction:
		_try_advance_to_damage_step()
		# stack is now open (priority window for attack response)
		pass

# ─── Signal Handlers ──────────────────────────────────────────────────────────

func _on_phase_changed(_old: TurnContext.Phase, _new: TurnContext.Phase, ctx: TurnContext) -> void:
	phase_changed.emit(ctx.phase_name(), tm.current_turn(), tm.active_player())

func _on_active_player_changed(player: Player) -> void:
	active_player_changed.emit(player)

func _on_game_over(winner: Player, loser: Player) -> void:
	game_over.emit(winner, loser)

func _on_card_drawn(player: Player, _card: CardInstance) -> void:
	## Re-evaluate legal actions after draw (UI may need to highlight new options)
	if player == local_player:
		pass  ## BoardView refreshes via ZoneManager.card_moved signal

func _on_stack_idle() -> void:
	## Chain fully resolved — check if we should auto-advance to damage step
	_try_advance_to_damage_step()

func _on_triggers_pending(triggers: Array) -> void:
	## Ask the local player about optional triggers via InputRequest
	var local_triggers := triggers.filter(func(t: PendingTrigger) -> bool:
		return t.controller == local_player and not t.is_mandatory
	)
	if local_triggers.is_empty():
		## No optional triggers for local player — auto-decline all
		var choices := {}
		for t in triggers:
			choices[t] = false
		stack.confirm_optional_triggers(choices)
		return

	## Create an input request for trigger selection
	var req := InputRequest.trigger_selection(local_triggers, func(choices: Dictionary):
		stack.confirm_optional_triggers(choices)
	)
	request_input(req)
func mark_player_effect_used(player:Player, card_id:StringName,effect_index:int,turn:int) ->void:
	if not player_used_effects.has(player):
		player_used_effects[player] = {}
	if not player_used_effects[player].has(card_id):
		player_used_effects[player][card_id]= {}
	player_used_effects[player][card_id][effect_index]= turn

func was_player_effect_used_this_turn(player:Player, card_id:StringName,effect_index:int,turn:int) ->bool:
	return player_used_effects.get(player,{}).get(card_id,{}).get(effect_index,-1) == turn
# ─── Debug ────────────────────────────────────────────────────────────────────

func debug_state() -> void:
	print("=== GameDirector State ===")
	print("  Phase:   %s (Turn %d)" % [tm.current_phase_name(), tm.current_turn()])
	print("  Active:  %s" % tm.active_player().display_name)
	print("  Stack:   %s" % EffectStack.StackState.keys()[stack.state])
	print("  Actions: %d executed" % action_log.size())
	for p in players:
		print("  %s: LP=%d  Hand=%d  Field=%d" % [
			p.display_name,
			p.life_points,
			zm.hand_of(p).count(),
			zm.monster_count(p),
		])
