## TurnManager.gd
## Drives the phase state machine and all per-phase housekeeping.
##
## Owns the authoritative TurnContext and rebuilds it on every phase
## transition. All other systems read TurnContext; only TurnManager writes it.
##
## Phase order:
##   DRAW → STANDBY → MAIN_1 → BATTLE_START → BATTLE_STEP → DAMAGE_STEP
##   → BATTLE_END → MAIN_2 → END → (next player's DRAW)
##
## Battle sub-phases are driven explicitly:
##   begin_battle_step(attacker, target) → BATTLE_STEP
##   begin_damage_step()                → DAMAGE_STEP
##   end_damage_step()                  → BATTLE_STEP (for next attacker)
##   end_battle_phase()                 → MAIN_2
##
## TurnManager does NOT execute game actions — that is GameDirector's job.
## TurnManager just says what phase it is and fires the right housekeeping.
class_name TurnManager
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Fired when the phase changes. Carry both old and new for UI transitions.
signal phase_changed(old_phase: TurnContext.Phase, new_phase: TurnContext.Phase, ctx: TurnContext)

## Fired at the very start of a new turn (after the previous player's END phase).
signal turn_started(turn_number: int, active_player: Player)

## Fired when the turn player changes (same as turn_started but more explicit).
signal active_player_changed(player: Player)

## Fired during DRAW phase after the draw has been executed.
signal card_drawn(player: Player, card: CardInstance)

## Fired during STANDBY if any mandatory standby effects are pending.
signal standby_effects_pending(player: Player)

## Fired when the END phase cleanup is complete and the turn is about to pass.
signal turn_ending(player: Player)

## Fired when a player's LP reach 0.
signal player_defeated(player: Player)

## Fired when the game ends (one player wins).
signal game_over(winner: Player, loser: Player)

# ─── Dependencies (set in setup()) ───────────────────────────────────────────

var _players:   Array[Player]  = []
var _zm:        ZoneManager    = null
var _stack:     EffectStack    = null

# ─── Turn State ───────────────────────────────────────────────────────────────

## The live context. Rebuilt on every phase transition.
var context: TurnContext = null

## Index into _players[] for the current turn player.
var _active_index: int = 0

## Increments every time _active_index flips (i.e. every full round).
var _turn_number: int = 1

## True once game_over has fired — blocks further phase advances.
var _game_over: bool = false

## Battle phase bookkeeping.
var _current_attacker: CardInstance = null
var _current_defender: CardInstance = null   ## null = direct attack

## Tracks cards that attacked this battle phase (for has_attacked flag).
var _attacked_this_turn: Array[CardInstance] = []

# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(
	players:      Array[Player],
	zone_manager: ZoneManager,
	effect_stack: EffectStack
) -> void:
	_players = players
	_zm      = zone_manager
	_stack   = effect_stack

	# Listen to EffectStack so we know when chains resolve
	_stack.stack_idle.connect(_on_stack_idle)

	# Listen to LP changes for win condition
	for p in _players:
		p.life_points_changed.connect(_on_lp_changed)

	# Build initial context (before first turn starts)
	_rebuild_context(TurnContext.Phase.MAIN_1)

## Call this to begin the very first turn of the game.
func start_game() -> void:
	assert(not _players.is_empty(), "TurnManager.start_game: no players set up")
	_active_index = 0
	_turn_number  = 1
	_game_over    = false
	turn_started.emit(_turn_number, _active_player())
	active_player_changed.emit(_active_player())
	_enter_phase(TurnContext.Phase.DRAW)

# ─── Phase Advance (public API) ───────────────────────────────────────────────

## Advance to the next phase in sequence.
## Returns false and does nothing if the stack is still open or the game is over.
func advance_phase() -> bool:
	if _game_over:
		return false
	if not _stack.is_idle():
		push_warning("TurnManager.advance_phase: EffectStack is not idle — wait for chain to resolve.")
		return false

	var next := _next_phase(context.phase)
	_enter_phase(next)
	return true

## Skip directly to a specific phase (used by some card effects, e.g. "skip to End Phase").
func skip_to_phase(target: TurnContext.Phase) -> void:
	if _game_over:
		return
	_enter_phase(target)

# ─── Battle Phase API (explicit sub-phase control) ────────────────────────────

## Declare an attack. Moves from BATTLE_START or between attacks into BATTLE_STEP.
## GameDirector calls this after RuleEngine.can_attack() passes.
func begin_battle_step(attacker: CardInstance, defender: CardInstance) -> void:
	assert(context.is_battle_phase(),
		"begin_battle_step called outside battle phase")
	_current_attacker = attacker
	_current_defender = defender
	_enter_phase(TurnContext.Phase.BATTLE_STEP)

	# Open a priority window: both players may respond before damage
	#_stack.open_window(_opponent_of(_active_player()))

## Move into the damage step. Called by GameDirector when both players pass
## priority after attack declaration.
func begin_damage_step() -> void:
	assert(context.phase == TurnContext.Phase.BATTLE_STEP,
		"begin_damage_step called outside BATTLE_STEP")
	_enter_phase(TurnContext.Phase.DAMAGE_STEP)

## Resolve damage and return to BATTLE_STEP for the next attack declaration.
## GameDirector calls this after executing the BattleResult.
func end_damage_step() -> void:
	assert(context.phase == TurnContext.Phase.DAMAGE_STEP,
		"end_damage_step called outside DAMAGE_STEP")
	# Mark attacker as having attacked
	if _current_attacker != null:
		_current_attacker.has_attacked = true
		if not _attacked_this_turn.has(_current_attacker):
			_attacked_this_turn.append(_current_attacker)
	_current_attacker = null
	_current_defender = null
	# Return to BATTLE_STEP for another potential attack
	_enter_phase(TurnContext.Phase.BATTLE_STEP)

## End the battle phase entirely. Moves to MAIN_2.
func end_battle_phase() -> void:
	_enter_phase(TurnContext.Phase.BATTLE_END)
	# BATTLE_END is instant — immediately move to MAIN_2
	_enter_phase(TurnContext.Phase.MAIN_2)

## Current attacker / defender during BATTLE_STEP or DAMAGE_STEP.
func current_attacker() -> CardInstance:
	return _current_attacker

func current_defender() -> CardInstance:
	return _current_defender

# ─── Turn Context Access ──────────────────────────────────────────────────────

func current_phase() -> TurnContext.Phase:
	return context.phase

func current_phase_name() -> String:
	return context.phase_name()

func current_turn() -> int:
	return _turn_number

func active_player() -> Player:
	return _active_player()

func non_active_player() -> Player:
	return _opponent_of(_active_player())

func is_turn_player(player: Player) -> bool:
	return player == _active_player()

# ─── Phase Entry ──────────────────────────────────────────────────────────────

func _enter_phase(phase: TurnContext.Phase) -> void:
	if _stack.state == EffectStack.StackState.OPEN_WINDOW and _stack.chain_is_empty():
		_stack.state = EffectStack.StackState.IDLE
		_stack.stack_idle.emit()
	var old_phase := context.phase if context != null else phase
	_rebuild_context(phase)
	phase_changed.emit(old_phase, phase, context)
	_run_phase_start(phase)

func _run_phase_start(phase: TurnContext.Phase) -> void:
	match phase:
		TurnContext.Phase.DRAW:      _on_draw_phase_start()
		TurnContext.Phase.STANDBY:   _on_standby_phase_start()
		TurnContext.Phase.MAIN_1:    _on_main_phase_start()
		TurnContext.Phase.BATTLE_START: _on_battle_phase_start()
		TurnContext.Phase.END:       _on_end_phase_start()

# ─── Per-Phase Housekeeping ───────────────────────────────────────────────────

func _on_draw_phase_start() -> void:
	var player := _active_player()

	# First turn of the game: first player does not draw (standard rule).
	# Remove this check if your game has different rules.
	if _turn_number == 1 and _active_index == 0:
		_stack.evaluate_triggers(
			GameEvent.phase_started(GameEvent.EventType.DRAW_PHASE_START, player),
			_zm
		)
		return

	# Deck-out check before drawing
	if _zm.deck_of(player).is_empty():
		_trigger_loss(player, "deck out")
		return

	# Draw one card
	var top := _zm.deck_of(player).peek_top()
	_zm.move(top, _zm.hand_of(player), ZoneManager.MoveReason.DRAW)
	card_drawn.emit(player, top)

	# Evaluate draw triggers
	_stack.evaluate_triggers(
		GameEvent.card_drawn(top, player),
		_zm
	)
	_stack.evaluate_triggers(
		GameEvent.phase_started(GameEvent.EventType.DRAW_PHASE_START, player),
		_zm
	)

func _on_standby_phase_start() -> void:
	var player := _active_player()
	_stack.evaluate_triggers(
		GameEvent.phase_started(GameEvent.EventType.STANDBY_PHASE_START, player),
		_zm
	)
	standby_effects_pending.emit(player)

func _on_main_phase_start() -> void:
	var player := _active_player()
	_stack.evaluate_triggers(
		GameEvent.phase_started(GameEvent.EventType.MAIN_PHASE_1_START, player),
		_zm
	)

func _on_battle_phase_start() -> void:
	var player := _active_player()
	_attacked_this_turn.clear()
	_stack.evaluate_triggers(
		GameEvent.phase_started(GameEvent.EventType.BATTLE_PHASE_START, player),
		_zm
	)

func _on_end_phase_start() -> void:
	var player := _active_player()

	_stack.evaluate_triggers(
		GameEvent.phase_started(GameEvent.EventType.END_PHASE_START, player),
		_zm
	)

	# Hand size limit (default 6 — override for your game)
	_enforce_hand_limit(player)

	# Reset per-turn state on all cards the player controls
	_reset_field_cards(player)

	# Reset player per-turn state
	player.reset_for_new_turn()

	# Remove modifiers that expire at end of turn
	_expire_end_of_turn_modifiers(player)

	turn_ending.emit(player)
	# Pass turn after a short yield to let end-phase triggers fire
	# In a real game GameDirector awaits stack_idle before calling _pass_turn()
	# Here we call it directly since we have no active triggers yet
	if _stack.is_idle():
		_pass_turn()
	else:
		_stack.stack_idle.connect(_pass_turn,CONNECT_ONE_SHOT)

# ─── Turn Passing ─────────────────────────────────────────────────────────────

func _pass_turn() -> void:
	# Flip active player
	_active_index = (_active_index + 1) % _players.size()

	# Increment turn number every full round (when index wraps to 0)
	if _active_index == 0:
		_turn_number += 1

	turn_started.emit(_turn_number, _active_player())
	active_player_changed.emit(_active_player())
	_enter_phase(TurnContext.Phase.DRAW)

# ─── End-Phase Housekeeping ───────────────────────────────────────────────────

## Enforce hand size limit. Player discards down to the limit.
## Emits a signal for GameDirector / UI to handle the discard selection.
func _enforce_hand_limit(player: Player) -> void:
	var limit := _hand_size_limit()
	var hand  := _zm.hand_of(player)
	while hand.count() > limit:
		## In a full game, pause here and ask the player which card to discard.
		## For now, discard the last card (index -1).
		var to_discard := hand.get_cards().back()
		_zm.move(to_discard, _zm.graveyard_of(player), ZoneManager.MoveReason.EFFECT_SEND)

## Override this in your game for a different hand limit.
func _hand_size_limit() -> int:
	return 6

func _reset_field_cards(player: Player) -> void:
	for card in _zm.all_cards_on_field(player):
		card.reset_turn_state()
		# Remove the position-changed-this-turn flag
		card.clear_flag(&"position_changed_this_turn")

func _expire_end_of_turn_modifiers(player: Player) -> void:
	## Remove any StatModifier whose expires_on_turn == current turn
	for card in _zm.all_cards_on_field(player):
		var to_remove: Array[StatModifier] = []
		for mod in card._atk_modifiers:
			if mod.expires_on_turn == _turn_number:
				to_remove.append(mod)
		for mod in card._def_modifiers:
			if mod.expires_on_turn == _turn_number:
				to_remove.append(mod)
		for mod in card._level_modifiers:
			if mod.expires_on_turn == _turn_number:
				to_remove.append(mod)
		for mod in to_remove:
			card.remove_modifier(mod)

# ─── Win / Loss Conditions ────────────────────────────────────────────────────

func _on_lp_changed(player: Player, _old: int, new_lp: int) -> void:
	if new_lp <= 0 and not _game_over:
		_trigger_loss(player, "life points reached 0")

func _trigger_loss(loser: Player, reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	var winner := _opponent_of(loser)
	push_warning("TurnManager: %s loses — %s" % [loser.display_name, reason])
	player_defeated.emit(loser)
	game_over.emit(winner, loser)

# ─── Phase Sequence ───────────────────────────────────────────────────────────

## Returns the next phase in the standard sequence.
func _next_phase(current: TurnContext.Phase) -> TurnContext.Phase:
	match current:
		TurnContext.Phase.DRAW:          return TurnContext.Phase.STANDBY
		TurnContext.Phase.STANDBY:       return TurnContext.Phase.MAIN_1
		TurnContext.Phase.MAIN_1:        return TurnContext.Phase.BATTLE_START
		TurnContext.Phase.BATTLE_START:  return TurnContext.Phase.BATTLE_STEP
		TurnContext.Phase.BATTLE_STEP:   return TurnContext.Phase.BATTLE_END
		TurnContext.Phase.DAMAGE_STEP:   return TurnContext.Phase.BATTLE_STEP
		TurnContext.Phase.BATTLE_END:    return TurnContext.Phase.MAIN_2
		TurnContext.Phase.MAIN_2:        return TurnContext.Phase.END
		TurnContext.Phase.END:           return TurnContext.Phase.DRAW  ## Handled by _pass_turn
	return TurnContext.Phase.DRAW

# ─── Context Rebuild ──────────────────────────────────────────────────────────

func _rebuild_context(phase: TurnContext.Phase) -> void:
	context = TurnContext.make(
		phase,
		_turn_number,
		_active_player(),
		_opponent_of(_active_player()),
		_stack.priority_holder if _stack.priority_holder != null else _active_player(),
		not _stack.is_idle()
	)

# ─── EffectStack Listener ─────────────────────────────────────────────────────

## When the chain resolves, rebuild context to reflect stack_idle = true
func _on_stack_idle() -> void:
	_rebuild_context(context.phase)

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _active_player() -> Player:
	return _players[_active_index]

func _opponent_of(player: Player) -> Player:
	for p in _players:
		if p != player:
			return p
	return null

func _to_string() -> String:
	if context == null:
		return "TurnManager(not started)"
	return "TurnManager(turn=%d phase=%s active=%s)" % [
		_turn_number,
		context.phase_name(),
		_active_player().display_name
	]
