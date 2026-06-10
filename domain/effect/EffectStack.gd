## EffectStack.gd
## The central chain/stack engine for the effect system.
##
## Implements the full Yu-Gi-Oh chain mechanic:
##   - LIFO resolution (last activated = first resolved)
##   - Priority passing between players after each push
##   - SEGOC (Simultaneous Effects Go On Chain) for trigger windows
##   - Mandatory effect enforcement
##   - Negate-on-chain support (Solemn Judgment, etc.)
##   - Spell Speed validation (can't chain Spell Speed 1 to Spell Speed 2+)
##
## ─── State Machine ────────────────────────────────────────────────────────────
##
##   IDLE ──push()──▶ OPEN_WINDOW ──pass()──▶ OPEN_WINDOW
##                         │                       │
##                    both pass                 push()
##                         │                       │
##                         ▼                       ▼
##                     RESOLVING ◀─────────────────┘
##                         │
##                   all links done
##                         │
##                         ▼
##                    IDLE (or new OPEN_WINDOW if triggers fired)
##
class_name EffectStack
extends Node
var player_used_effects:Dictionary = {}# player -> {card_id - effect_index - turn}
# ─── Signals ──────────────────────────────────────────────────────────────────

## A new ChainLink was added (UI: add entry to chain display).
signal chain_link_pushed(link: ChainLink)

## A ChainLink was popped and resolved (UI: remove top entry, show resolution).
signal chain_link_resolved(link: ChainLink, was_negated: bool)

## The entire chain finished resolving (all links popped).
signal chain_resolved(links_in_order: Array)  ## Array[ChainLink], first-pushed first

## Priority was passed to a player — they may add to the chain or pass.
## UI: highlight whose turn it is to respond.
signal priority_passed(to_player: Player)

## The chain is open and waiting for a player to act or pass.
## UI: show "activate?" prompt.
signal window_opened(pending_player: Player, can_pass: bool)

## Trigger effects were detected and need player decisions (SEGOC).
## UI: show trigger selection popup.
signal triggers_pending(pending: Array)  ## Array[PendingTrigger]

## An effect was negated mid-chain.
signal effect_negated(link: ChainLink, by_card: CardInstance)

## Emitted when the stack returns to idle with no pending business.
signal stack_idle()

# ─── State ────────────────────────────────────────────────────────────────────

enum StackState {
	IDLE,          ## Nothing happening; normal game actions allowed
	OPEN_WINDOW,   ## Chain is open; current priority holder may respond
	RESOLVING,     ## Chain is actively resolving (no new activations)
	AWAITING_COST, ## Waiting for a player to pay a cost before link is confirmed
	AWAITING_TARGETS, ## Waiting for a player to select targets
	AWAITING_SEGOC,   ## Waiting for players to arrange trigger order
}

# ─── Core Data ────────────────────────────────────────────────────────────────

## The live chain. Index 0 = first pushed (resolves last). Last = top (resolves next).
var links: Array[ChainLink] = []
var _human_players:Array[Player]
## Current machine state.
var state: StackState = StackState.IDLE

## Who currently holds priority.
var priority_holder: Player = null

## The player whose turn it currently is (set by TurnManager each turn).
var turn_player: Player = null

## Both players. Populated in setup().
var players: Array[Player] = []

## Passes received consecutively. When both players pass consecutively → resolve.
var _consecutive_passes: int = 0

## Triggers detected during the current event that haven't been added to the chain yet.
var _pending_triggers: Array[PendingTrigger] = []

## Links completed this chain (for post-chain callbacks and replay).
var _completed_links: Array[ChainLink] = []

## Reference to ZoneManager — used to connect zone-move signals.
var _zone_manager: ZoneManager = null

# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(player_list: Array[Player], zone_manager: ZoneManager) -> void:
	players       = player_list
	_zone_manager = zone_manager
	turn_player   = players[0]
	priority_holder = players[0]
	_human_players  = [players[0]]   # ← add this line
	# Hook into ZoneManager to detect triggers on card movement
	_zone_manager.card_moved.connect(_on_card_moved)

# ─── Public API ───────────────────────────────────────────────────────────────

## Attempt to push a new activation onto the chain.
## Called by GameDirector when a player activates an effect.
## Returns false if the activation is illegal (spell speed, timing, etc.)
func push(
	effect: EffectDefinition,
	card: CardInstance,
	effect_index:int,
	activating_player: Player,
	targets: Array[CardInstance] = [],
	trigger_event: GameEvent = null
) -> bool:

	# ── Validation ────────────────────────────────────────────────────────────

	if not _can_push(effect, activating_player):
		push_warning("EffectStack.push: illegal activation of '%s'" % effect.effect_name)
		return false

	# ── Build link ────────────────────────────────────────────────────────────

	var index   := links.size() + 1
	var link    := ChainLink.create(index, effect, card, activating_player, targets, trigger_event)

	links.append(link)
	_consecutive_passes = 0
	state = StackState.OPEN_WINDOW

	chain_link_pushed.emit(link)

	# ── Mark once-per-turn usage ───────────────────────────────────────────────

	if effect.once_per_turn:
		print("effect registered for turn ",_current_turn())
		card.mark_effect_used(card.definition.effects.find(effect), _current_turn())
	if effect.once_per_duel:
		card.mark_effect_used_duel(card.definition.effects.find(effect))
	if effect.once_per_turn_per_player:
		if was_player_effect_used_this_turn(activating_player,card.definition.card_id,effect_index,_current_turn()):
			push_warning("Player has already used effect of card % this turn" % card.definition.card_name)
		mark_player_effect_used(activating_player,card.definition.card_id,effect_index,_current_turn())
	# ── Pass priority to the opponent ─────────────────────────────────────────

	var opponent := _opponent_of(activating_player)
	_pass_priority_to(opponent)

	return true

## The current priority holder passes without activating anything.
## When both players pass consecutively, resolution begins.
func pass_priority(player: Player) -> void:
	print("pass_priority: ", player.display_name, " pasees: ", _consecutive_passes)
	assert(state == StackState.OPEN_WINDOW, "Cannot pass priority in state: %s" % StackState.keys()[state])
	assert(player == priority_holder, "Player %d does not hold priority" % player.player_id)

	_consecutive_passes += 1

	if _consecutive_passes >= 2:
		# Both players passed — chain is closed, begin resolution
		_begin_resolution()
	else:
		# Pass to the other player
		var other := _opponent_of(player)
		_pass_priority_to(other)

## Open a new priority window with no chain yet (e.g. after a summon).
## Used to give both players a chance to respond before game state advances.
func open_window(for_player: Player) -> void:
	if state != StackState.IDLE:
		push_warning("EffectStack.open_window: stack not idle (state=%s)" % StackState.keys()[state])
		return
	state = StackState.OPEN_WINDOW
	_consecutive_passes = 0
	_pass_priority_to(for_player)

## Negate the top link on the chain (e.g. Solemn Judgment).
## Usually called from within another effect's resolve().
func negate_top_link(by_card: CardInstance) -> void:
	assert(not links.is_empty(), "Cannot negate: chain is empty")
	var top := links.back()
	top.negate()
	effect_negated.emit(top, by_card)

## Negate a specific link by chain index.
func negate_link(chain_index: int, by_card: CardInstance) -> void:
	var link := get_link(chain_index)
	assert(link != null, "No link at chain index %d" % chain_index)
	link.negate()
	effect_negated.emit(link, by_card)

## Returns the ChainLink at the given 1-based chain index, or null.
func get_link(chain_index: int) -> ChainLink:
	for link in links:
		if link.chain_index == chain_index:
			return link
	return null

## The topmost (most recently pushed) link.
func top_link() -> ChainLink:
	return links.back() if not links.is_empty() else null

## Current chain depth.
func depth() -> int:
	return links.size()

func is_idle() -> bool:
	return state == StackState.IDLE

func is_resolving() -> bool:
	return state == StackState.RESOLVING

func chain_is_empty() -> bool:
	return links.is_empty()

## Minimum spell speed required to add to the current chain.
func minimum_spell_speed() -> int:
	if links.is_empty():
		return 1
	return top_link().effect.spell_speed

# ─── Trigger Evaluation ───────────────────────────────────────────────────────
func mark_player_effect_used(player:Player, card_id:StringName,effect_index:int,turn:int) ->void:
	if not player_used_effects.has(player):
		player_used_effects[player] = {}
	if not player_used_effects[player].has(card_id):
		player_used_effects[player][card_id]= {}
	player_used_effects[player][card_id][effect_index]= turn

func was_player_effect_used_this_turn(player:Player, card_id:StringName,effect_index:int,turn:int) ->bool:
	return player_used_effects.get(player,{}).get(card_id,{}).get(effect_index,-1) == turn
## Called by GameDirector after any game event that might trigger effects.
## Collects all matching trigger effects from all cards currently on the field,
## respects SEGOC ordering, and either auto-places mandatory ones or
## asks players about optional ones.
func evaluate_triggers(event: GameEvent, zone_manager: ZoneManager) -> void:
	var new_triggers: Array[PendingTrigger] = []
	if state == StackState.RESOLVING:
		return
	# Scan all on-field cards for matching trigger effects
	for player in players:
		for card in zone_manager.all_cards_on_field(player):
			_collect_triggers_from_card(card, event, new_triggers, zone_manager)

	# Also scan hand for hand traps (Quick effects with QUICK_EFFECT timing)
	for player in players:
		for card in zone_manager.hand_of(player).get_cards():
			_collect_hand_traps_from_card(card, event, new_triggers)

	if new_triggers.is_empty():
		return

	_pending_triggers.append_array(new_triggers)

	# Sort by SEGOC rules before presenting to players
	_sort_triggers_segoc(new_triggers)

	# Auto-place mandatory triggers and ask about optional ones
	_process_pending_triggers(new_triggers, zone_manager)

# ─── Resolution Engine ────────────────────────────────────────────────────────

func _begin_resolution() -> void:
	assert(state == StackState.OPEN_WINDOW)
	state = StackState.RESOLVING

	# Resolve LIFO — pop from the back
	while not links.is_empty():
		var link: ChainLink = links.pop_back()
		link.resolve()
		_completed_links.append(link)
		chain_link_resolved.emit(link, link.was_negated())
		_send_to_gy_after_resolution(link)
	# Collect all completed links in first-pushed order for the signal
	var ordered := _completed_links.duplicate()
	_completed_links.clear()
	links.clear()

	chain_resolved.emit(ordered)

	# Check for triggers that fired during resolution
	state = StackState.IDLE
	#if _pending_triggers.is_empty():
	stack_idle.emit()
	# If _pending_triggers is not empty, the next evaluate_triggers call
	# will handle them (GameDirector drives this loop)
func _send_to_gy_after_resolution(link:ChainLink) -> void:
	var card = link.source_card
	var def = card.definition
	
	if def.is_monster():
		return
	elif def.is_trap():
		if def.trap_type == CardDefinition.TrapType.CONTINUOUS:
			return
	elif def.is_spell():
		match def.spell_type:
			CardDefinition.SpellType.CONTINUOUS,CardDefinition.SpellType.EQUIP,CardDefinition.SpellType.FIELD:
				return
	if card.is_in_graveyard() or card.is_banished():
		return
	_zone_manager.move(card,_zone_manager.graveyard_of(card.controller),ZoneManager.MoveReason.RESOLVE)
# ─── Spell Speed Validation ───────────────────────────────────────────────────

func _can_push(effect: EffectDefinition, player: Player) -> bool:
	# Must hold priority
	if player != priority_holder:
		push_warning("Player %d does not hold priority" % player.player_id)
		return false

	# Must be in a state that allows activation
	if state == StackState.RESOLVING:
		push_warning("Cannot activate during resolution")
		return false

	# Spell Speed check: new activation must be >= top link's spell speed
	if not links.is_empty():
		var top_speed := top_link().effect.spell_speed
		if effect.spell_speed < top_speed:
			push_warning(
				"Spell Speed %d cannot be chained to Spell Speed %d" % [
					effect.spell_speed, top_speed
				]
			)
			return false

	# Continuous effects don't go on the chain
	if effect.is_continuous:
		push_warning("Continuous effects do not go on the chain")
		return false

	# Once-per-turn is validated by the caller (RuleEngine / TestBoard) before
	# calling push(). The source card and effect index are on the ChainLink,
	# not on the EffectDefinition resource, so we can't check it here without
	# also receiving the source card. Callers are responsible for this check.

	return true

# ─── Priority Passing ─────────────────────────────────────────────────────────

func _pass_priority_to(player: Player) -> void:
	print("passed prio to ",player.display_name)
	priority_holder = player
	priority_passed.emit(player)
	window_opened.emit(player, true)

	# Only auto-pass if this player STILL holds priority after the signal.
	# The signal handler may have activated an effect which transferred
	# priority to the opponent inside push().
	#if player not in _human_players and priority_holder == player:
		#pass_priority(player)
# ─── Trigger Collection ───────────────────────────────────────────────────────

func _collect_triggers_from_card(
	card: CardInstance,
	event: GameEvent,
	out_triggers: Array[PendingTrigger],
	zone_manager: ZoneManager
) -> void:
	for i in card.definition.effects.size():
		var eff: EffectDefinition = card.definition.effects[i]

		# Only trigger effects
		if eff.category != EffectDefinition.EffectCategory.TRIGGER:
			continue

		# Does this event match the effect's trigger?
		if not GameEvent.triggers_match(eff.trigger, event):
			continue

		# Is the effect's source the card involved in the event?
		# (e.g. "when THIS card is destroyed" — only fires for this specific card)
		if not _trigger_source_matches(eff, card, event):
			continue

		# Once-per-turn check
		if eff.once_per_turn and card.was_effect_used_this_turn(i, _current_turn()):
			continue

		# Once-per-duel check
		if eff.once_per_duel and card.was_effect_used_this_duel(i):
			continue

		# Evaluate activation conditions
		if not eff.conditions.is_empty():
			var all_pass := true
			for cond in eff.conditions:
				if not cond.evaluate(card, zone_manager, card.controller):
					all_pass = false
					break
			if not all_pass:
				continue

		var pt := PendingTrigger.create(
			card, eff, i, card.controller, event,
			eff.timing == EffectDefinition.EffectTiming.MANDATORY
		)
		out_triggers.append(pt)

func _collect_hand_traps_from_card(
	card: CardInstance,
	event: GameEvent,
	out_triggers: Array[PendingTrigger]
) -> void:
	for i in card.definition.effects.size():
		var eff: EffectDefinition = card.definition.effects[i]
		if eff.timing != EffectDefinition.EffectTiming.QUICK_EFFECT:
			continue
		if eff.category != EffectDefinition.EffectCategory.QUICK:
			continue
		if not GameEvent.triggers_match(eff.trigger, event):
			continue
		if eff.once_per_turn and card.was_effect_used_this_turn(i, _current_turn()):
			continue

		var pt := PendingTrigger.create(card, eff, i, card.controller, event, false)
		out_triggers.append(pt)

func _trigger_source_matches(eff: EffectDefinition, card: CardInstance, event: GameEvent) -> bool:
	## For most trigger effects, the card must BE the primary_card in the event
	## (e.g. "when this card is destroyed"). Some effects watch for other cards
	## (e.g. "when a DARK monster is sent to GY") — those use conditions instead.
	match eff.trigger:
		[EffectDefinition.EffectTrigger.ON_DESTROY,
		EffectDefinition.EffectTrigger.ON_SEND_TO_GY,
		EffectDefinition.EffectTrigger.ON_BANISH,
		EffectDefinition.EffectTrigger.ON_SUMMON,
		EffectDefinition.EffectTrigger.ON_FLIP]:
			# Self-referential triggers: only fire if this card is the event's subject
			return event.primary_card == card
		_:
			# Phase/turn/board-watching triggers: fire for any card that matches conditions
			return true

# ─── SEGOC Ordering ───────────────────────────────────────────────────────────

## Sort pending triggers per SEGOC rules:
##   1. Turn player's MANDATORY effects
##   2. Non-turn player's MANDATORY effects
##   3. Turn player's OPTIONAL effects
##   4. Non-turn player's OPTIONAL effects
func _sort_triggers_segoc(triggers: Array[PendingTrigger]) -> void:
	triggers.sort_custom(func(a: PendingTrigger, b: PendingTrigger) -> bool:
		var a_turn := a.controller == turn_player
		var b_turn := b.controller == turn_player

		# Mandatory before optional
		if a.is_mandatory != b.is_mandatory:
			return a.is_mandatory  # mandatory first

		# Turn player's effects before non-turn player's
		if a_turn != b_turn:
			return a_turn  # turn player first

		return false  # preserve original relative order
	)

## Place mandatory triggers and signal optional ones to the player.
func _process_pending_triggers(
	triggers: Array[PendingTrigger],
	zone_manager: ZoneManager
) -> void:
	var optional_triggers: Array[PendingTrigger] = []

	for pt in triggers:
		if pt.is_mandatory:
			# Auto-push mandatory effects — no player choice
			push(pt.effect, pt.source_card,pt.effect_index, pt.controller, pt.targets, pt.trigger_event)
			pt.is_handled = true
		else:
			optional_triggers.append(pt)

	if not optional_triggers.is_empty():
		# Signal UI to present the optional trigger window
		triggers_pending.emit(optional_triggers)
		# GameDirector/UI will call confirm_optional_triggers() with player choices

## Called by GameDirector after the player decides which optional triggers to use.
## player_choices: Dictionary[PendingTrigger → bool] (true = place on chain)
func confirm_optional_triggers(player_choices: Dictionary) -> void:
	for pt in player_choices.keys():
		var activate: bool = player_choices[pt]
		if activate and not pt.is_handled:
			push(pt.effect, pt.source_card, pt.controller, pt.targets, pt.trigger_event)
		pt.is_handled = true
	_pending_triggers = _pending_triggers.filter(func(pt): return not pt.is_handled)

# ─── ZoneManager Hook ─────────────────────────────────────────────────────────

## Connected to ZoneManager.card_moved in setup().
## Converts zone moves into GameEvents and evaluates triggers.
func _on_card_moved(
	card: CardInstance,
	from_zone: Zone,
	to_zone: Zone,
	reason: ZoneManager.MoveReason
) -> void:
	var events: Array[GameEvent] = _events_from_move(card, from_zone, to_zone, reason)
	for event in events:
		evaluate_triggers(event, _zone_manager)

func _events_from_move(
	card: CardInstance,
	from_zone: Zone,
	to_zone: Zone,
	reason: ZoneManager.MoveReason
) -> Array[GameEvent]:
	var events: Array[GameEvent] = []

	match reason:
		ZoneManager.MoveReason.NORMAL_SUMMON:
			events.append(GameEvent.card_summoned(card, true))

		ZoneManager.MoveReason.SPECIAL_SUMMON:
			events.append(GameEvent.card_summoned(card, false))

		ZoneManager.MoveReason.FLIP_SUMMON:
			var e := GameEvent.new()
			e.event_type   = GameEvent.EventType.CARD_SUMMONED_FLIP
			e.primary_card = card
			e.cause_player = card.controller
			events.append(e)

		ZoneManager.MoveReason.BATTLE_DESTROY, ZoneManager.MoveReason.EFFECT_DESTROY:
			events.append(GameEvent.card_destroyed(card, card.controller, reason))
			if to_zone != null and to_zone.zone_type == Zone.ZoneType.GRAVEYARD:
				events.append(GameEvent.card_sent_to_gy(card, card.controller, reason))

		ZoneManager.MoveReason.EFFECT_SEND, ZoneManager.MoveReason.TRIBUTE, ZoneManager.MoveReason.MATERIAL:
			if to_zone != null and to_zone.zone_type == Zone.ZoneType.GRAVEYARD:
				events.append(GameEvent.card_sent_to_gy(card, card.controller, reason))

		ZoneManager.MoveReason.EFFECT_BANISH:
			events.append(GameEvent.card_banished(card, card.controller))

		ZoneManager.MoveReason.DRAW:
			events.append(GameEvent.card_drawn(card, card.controller))

	return events

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _opponent_of(player: Player) -> Player:
	for p in players:
		if p != player:
			return p
	push_error("EffectStack: cannot find opponent of player %d" % player.player_id)
	return null

func _current_turn() -> int:
	## GameDirector sets this; fallback for standalone testing.
	if has_meta(&"current_turn"):
		return get_meta(&"current_turn")
	return 0

# ─── Debug ────────────────────────────────────────────────────────────────────

func debug_print_chain() -> void:
	print("=== Effect Chain (depth=%d, state=%s) ===" % [depth(), StackState.keys()[state]])
	for i in links.size():
		var link := links[i]
		print("  CL%d: %s by %s [%s]" % [
			link.chain_index,
			link.effect.effect_name,
			link.source_card.definition.card_name,
			ChainLink.LinkState.keys()[link.state]
		])
	if _pending_triggers.size() > 0:
		print("  Pending triggers: %d" % _pending_triggers.size())
