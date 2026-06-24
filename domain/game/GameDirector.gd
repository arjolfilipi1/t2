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

## An attack was just declared and validated — fires BEFORE damage is
## calculated, so the UI can play the attack lunge animation first and only
## apply destruction/LP feedback once that animation completes.
signal attack_declared(attacker: CardInstance, target: CardInstance)
## Battle damage has been calculated and applied — carries the full
## BattleResult so the UI can animate destruction/survival correctly.
signal battle_resolved(result: RuleEngine.BattleResult)

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

## Snapshot-based undo/redo. Captures board state before every action;
## restoring snaps directly to a prior state rather than computing inverse
## mutations. See UndoManager.gd for the full design rationale.
var undo_manager: UndoManager = null
# ─── Players ──────────────────────────────────────────────────────────────────

var players: Array[Player] = []

## The local human player (index 0 by default).
var local_player: Player = null

# ─── Action History ───────────────────────────────────────────────────────────

## Every executed action in order. Used for replay and debug.
var action_log: Array[GameAction] = []
var _next_action_id: int = 0
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
	
	undo_manager = UndoManager.new()
	undo_manager.setup(zm, tm, stack, players)
	
	# Register service locator for EffectResolutionStep
	EffectResolutionStep.zone_manager = zm
	EffectResolutionStep.effect_stack = stack
	EffectResolutionStep.players      = players

	# Wire internal signals
	tm.phase_changed.connect(_on_phase_changed)
	tm.active_player_changed.connect(_on_active_player_changed)
	tm.game_over.connect(_on_game_over)
	tm.card_drawn.connect(_on_card_drawn)
	tm.hand_limit_exceeded.connect(_on_hand_limit_exceeded)
	stack.stack_idle.connect(_on_stack_idle)
	stack.triggers_pending.connect(_on_triggers_pending)

func _on_turn_started(turn:int,_player:Player)->void:
	stack.set_meta("current_turn",turn)

## Begin the game. Call after all decks are loaded.
func start_game() -> void:
	action_log.clear()
	_next_action_id = 0
	undo_manager.clear()
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
	# Capture undo point — BEFORE execute() mutates anything. Only captured
	# when the chain is idle (UndoManager itself also enforces this; the
	# check here just avoids the warning print on the common path).
	if stack.is_idle():
			undo_manager.capture_before_action(action.describe())
	# Execute
	action.execute(zm, tm, stack)
	action_log.append(action)
	action_executed.emit(action)

	# Post-execution hooks
	_post_action(action)
	_try_auto_advance()
	
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

	return submit_action(GameAction.PassPriorityAction.make(player))

func advance_phase(player: Player) -> bool:
	return submit_action(GameAction.AdvancePhaseAction.make(player))
# ─── Undo / Redo ──────────────────────────────────────────────────────────────
## Thin wrappers around UndoManager — kept here so callers only ever talk
## to GameDirector and never need a direct reference to UndoManager itself.
## Reverts the board to the state immediately before the last executed
## action. Returns false if there is nothing to undo (or a chain is open).
func undo() -> bool:
		return undo_manager.undo()
## Re-applies the most recently undone action. Returns false if there is
## nothing to redo (or a chain is open).
func redo() -> bool:
		return undo_manager.redo()
func can_undo() -> bool:
		return undo_manager.can_undo()
func can_redo() -> bool:
		return undo_manager.can_redo()
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
	print("action finished:",action.describe())
	# Emit semantic signals for actions that have board meaning
	if action is GameAction.NormalSummonAction:
		card_summoned.emit(action.card, true)
	elif action is GameAction.DeclareAttackAction:
		_try_advance_to_damage_step()
		attack_declared.emit(action.attacker, action.target)
	elif action is GameAction.ResolveBattleDamageAction:
		var result := RuleEngine.resolve_battle(action.attacker, action.target)
		battle_resolved.emit(result)
		
# ─── Auto-Advance ──────────────────────────────────────────────────────────────
##
## Automatically advances the phase when the active player has no possible
## legal action left to take. This only applies to phases where waiting for
## input is pointless — DRAW, STANDBY, BATTLE_START (instant), and BATTLE_STEP
## once no attacker has a legal target remaining.
##
## Main Phase 1 and Main Phase 2 are EXCLUDED for the human player by design:
## even if RuleEngine reports zero legal actions, the human should still see
## the phase and press End Phase themselves. Auto-advancing Main Phase would
## be confusing — "did my turn just skip past me?"
##
## For the AI, Main Phase is driven entirely by AIController's own planner,
## which explicitly calls advance_phase() once it has finished acting — so
## this method does not need to (and should not) auto-advance Main Phase for
## the AI either; doing so would race against the AI's action queue.
## Phases that are always safe to auto-advance for ANY player, since they
## never require a human decision.
const _ALWAYS_AUTO_ADVANCE := [
		TurnContext.Phase.STANDBY,
		TurnContext.Phase.BATTLE_START,
		TurnContext.Phase.BATTLE_END,
]
## Phases that are auto-advanced only when the active player has no legal
## action remaining. Main Phases are deliberately NOT in this list.
const _CONDITIONAL_AUTO_ADVANCE := [
		TurnContext.Phase.BATTLE_STEP,
]
func _try_auto_advance() -> void:
	if tm == null or tm.context == null:
		return
	if not stack.is_idle():
		return   ## Never advance while a chain is open or resolving

	var phase  := tm.context.phase
	var player := tm.active_player()

	# Draw phase has no human decision point at all — TurnManager already
	# executes the draw synchronously, so by the time phase_changed fires
	# there is nothing left to wait for.
	if phase == TurnContext.Phase.DRAW:
		_queue_auto_advance(player)
		return

	if phase in _ALWAYS_AUTO_ADVANCE:
		_queue_auto_advance(player)
		return

	if phase in _CONDITIONAL_AUTO_ADVANCE:
		if not _has_any_legal_action(player, phase):
			_queue_auto_advance(player)
		return

	# MAIN_1 / MAIN_2 / END: never auto-advance here.
	# END already passes the turn on its own via TurnManager._pass_turn().

## Defers the actual advance_phase() call by one frame.
## This avoids advancing mid-signal-emission, which would re-enter
## TurnManager while it is still finishing the current phase transition.
func _queue_auto_advance(player: Player) -> void:
	call_deferred("_do_auto_advance", player)

func _do_auto_advance(player: Player) -> void:
	if tm == null or tm.context == null:
		return
	if not stack.is_idle():
		return   ## State may have changed since this was queued — re-check
	advance_phase(player)

## True if `player` has at least one legal action available in `phase`.
## Used only for the conditional auto-advance phases (currently BATTLE_STEP).
func _has_any_legal_action(player: Player, phase: TurnContext.Phase) -> bool:
	match phase:
		TurnContext.Phase.BATTLE_STEP:
			var la := RuleEngine.get_all_legal_actions(player, zm, tm.context, stack)
			return not la.can_attack.is_empty()
		_:
			return true   ## Unknown phase — be conservative, don't auto-advance

# ─── Signal Handlers ──────────────────────────────────────────────────────────

func _on_phase_changed(_old: TurnContext.Phase, _new: TurnContext.Phase, ctx: TurnContext) -> void:
	phase_changed.emit(ctx.phase_name(), tm.current_turn(), tm.active_player())
	#_try_auto_advance()
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
	#_try_advance_to_damage_step()
	_try_auto_advance()
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
func _on_hand_limit_exceeded(player: Player, excess_count: int, hand_cards: Array) -> void:
		## Always routed through InputRequest — for the human this surfaces a
		## UI prompt; for the AI, AIController._on_awaiting_input picks it up
		## via the same awaiting_input signal and resolves it with its own
		## lowest-value heuristic (_resolve_discard_selection). Either way,
		## confirm_hand_discard() is what actually performs the moves and lets
		## TurnManager resume passing the turn.
		var typed_hand: Array[CardInstance] = []
		for c in hand_cards:
				typed_hand.append(c)
		var req := InputRequest.discard_selection(player, typed_hand, excess_count,
				func(chosen: Array):
						var typed_chosen: Array[CardInstance] = []
						for c in chosen:
								typed_chosen.append(c)
						tm.confirm_hand_discard(player, typed_chosen)
		)
		request_input(req)

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
