## EffectResolutionStep.gd
## Base class for atomic resolution steps.
## Each subclass performs exactly one game action.
##
## Service access pattern:
##   Steps need ZoneManager and sometimes a player list. Rather than using
##   Engine.get_singleton() (which requires actual Godot Autoloads), steps
##   call EffectResolutionStep.zm() and EffectResolutionStep.all_players()
##   which read from static vars set by GameDirector (or TestBoard) at boot:
##
##     EffectResolutionStep.zone_manager = zm
##     EffectResolutionStep.players      = [p1, p2]
class_name EffectResolutionStep
extends Resource

# ─── Service Locator ──────────────────────────────────────────────────────────
## Set once at game boot by GameDirector or TestBoard.
static var zone_manager: ZoneManager = null
static var players: Array = []         ## Array[Player]

## Convenience accessor with null-check.
static func zm() -> ZoneManager:
	assert(zone_manager != null,
		"EffectResolutionStep.zone_manager is null — call EffectResolutionStep.zone_manager = zm at boot")
	return zone_manager

## Returns all players except the given one.
static func opponents_of(player: Player) -> Array:
	var result := []
	for p in players:
		if p != player:
			result.append(p)
	return result

# ─── Interface ────────────────────────────────────────────────────────────────

## Override in subclasses. context is the ChainLink's EffectContext.
func execute(_context: EffectContext) -> void:
	push_error("EffectResolutionStep.execute() not overridden in %s" % get_class())


# ══════════════════════════════════════════════════════════════════════════════
# DESTRUCTION
# ══════════════════════════════════════════════════════════════════════════════

class DestroyTargetsStep extends EffectResolutionStep:
	## Destroys all valid targets (sends to GY as destroyed).
	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		var to_destroy := context.valid_targets()
		if to_destroy.is_empty():
			return
		# Group by controller so each card goes to the right GY
		var by_ctrl: Dictionary = {}
		for card in to_destroy:
			if not by_ctrl.has(card.controller):
				by_ctrl[card.controller] = []
			by_ctrl[card.controller].append(card)
		for player in by_ctrl.keys():
			z.move_batch(by_ctrl[player], z.graveyard_of(player), ZoneManager.MoveReason.EFFECT_DESTROY)
		context.set_data(&"destroyed_cards", to_destroy)


class DestroyAllMonstersStep extends EffectResolutionStep:
	## Destroys all monsters on the field (Dark Hole-style).
	@export var include_controller: bool = true
	@export var include_opponent:   bool = true

	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		var by_ctrl: Dictionary = {}
		var all_players: Array = [context.controller]
		all_players.append_array(EffectResolutionStep.opponents_of(context.controller))
		for player in all_players:
			var include :bool= (player == context.controller and include_controller) \
						or (player != context.controller and include_opponent)
			if not include:
				continue
			var monsters := z.monsters_on_field(player)
			if not monsters.is_empty():
				by_ctrl[player] = monsters
		for player in by_ctrl.keys():
			z.move_batch(by_ctrl[player], z.graveyard_of(player), ZoneManager.MoveReason.EFFECT_DESTROY)


# ══════════════════════════════════════════════════════════════════════════════
# DRAW
# ══════════════════════════════════════════════════════════════════════════════

class DrawCardsStep extends EffectResolutionStep:
	## The controller (or opponent if target_opponent=true) draws `count` cards.
	@export var count:           int  = 1
	@export var target_opponent: bool = false

	func execute(context: EffectContext) -> void:
		var z      := EffectResolutionStep.zm()
		var opps   := EffectResolutionStep.opponents_of(context.controller)
		var player: Player = opps[0] if target_opponent and opps.size() > 0 else context.controller
		var deck   := z.deck_of(player)
		var hand   := z.hand_of(player)
		for _i in count:
			if deck.is_empty():
				push_warning("DrawCardsStep: %s has no cards left" % player.display_name)
				break
			z.move(deck.peek_top(), hand, ZoneManager.MoveReason.DRAW)


# ══════════════════════════════════════════════════════════════════════════════
# SEND TO GRAVEYARD
# ══════════════════════════════════════════════════════════════════════════════

class SendToGraveyardStep extends EffectResolutionStep:
	## Sends all valid targets to GY (not destroying them — no destroyed trigger).
	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		for card in context.valid_targets():
			z.move(card, z.graveyard_of(card.controller), ZoneManager.MoveReason.EFFECT_SEND)


# ══════════════════════════════════════════════════════════════════════════════
# BANISH
# ══════════════════════════════════════════════════════════════════════════════

class BanishTargetsStep extends EffectResolutionStep:
	@export var face_down: bool = false

	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		for card in context.valid_targets():
			z.move(card, z.banished_of(card.controller), ZoneManager.MoveReason.EFFECT_BANISH)
			if face_down:
				card.face_state = CardInstance.FaceState.FACE_DOWN


# ══════════════════════════════════════════════════════════════════════════════
# RETURN TO HAND
# ══════════════════════════════════════════════════════════════════════════════

class ReturnToHandStep extends EffectResolutionStep:
	## Returns targets to the hand of their current controller.
	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		for card in context.valid_targets():
			z.move(card, z.hand_of(card.controller), ZoneManager.MoveReason.EFFECT_RETURN)


# ══════════════════════════════════════════════════════════════════════════════
# SPECIAL SUMMON
# ══════════════════════════════════════════════════════════════════════════════

class SpecialSummonTargetStep extends EffectResolutionStep:
	## Special summons targets from GY / banished / hand to the field.
	@export var method: StringName = &"effect"

	func execute(context: EffectContext) -> void:
		var z    := EffectResolutionStep.zm()
		var turn := 0
		if Engine.has_singleton(&"TurnManager"):
			turn = Engine.get_singleton(&"TurnManager").current_turn
		for card in context.targets:
			if card.is_on_field():
				continue
			if not z.has_open_monster_zone(card.controller):
				push_warning("SpecialSummonTargetStep: no open zone for %s" % card)
				continue
			z.move_to_first_slot(
				card, z.monster_zone_of(card.controller),
				ZoneManager.MoveReason.SPECIAL_SUMMON
			)
			card.record_special_summon(turn, method)


# ══════════════════════════════════════════════════════════════════════════════
# STAT MODIFICATION
# ══════════════════════════════════════════════════════════════════════════════

class ModifyStatStep extends EffectResolutionStep:
	@export var stat:              StringName = &"atk"
	@export var amount:            int        = 0
	@export var use_set:           bool       = false
	@export var expires_end_of_turn: bool     = true

	func execute(context: EffectContext) -> void:
		var turn_end := -1
		if expires_end_of_turn and Engine.has_singleton(&"TurnManager"):
			turn_end = Engine.get_singleton(&"TurnManager").current_turn
		for card in context.valid_targets():
			var mod: StatModifier
			if use_set:
				mod = StatModifier.set_value(stat, amount,
					context.source_card.instance_id, context.effect_index, turn_end)
			else:
				mod = StatModifier.additive(stat, amount,
					context.source_card.instance_id, context.effect_index, turn_end)
			card.add_modifier(mod)


# ══════════════════════════════════════════════════════════════════════════════
# LIFE POINTS
# ══════════════════════════════════════════════════════════════════════════════

class DealDamageStep extends EffectResolutionStep:
	@export var amount:           int  = 0
	@export var use_atk_snapshot: bool = false
	@export var damage_controller: bool = false  ## false = damage opponent

	func execute(context: EffectContext) -> void:
		var damage := context.source_atk_snapshot if use_atk_snapshot else amount
		var opps := EffectResolutionStep.opponents_of(context.controller)
		var target_player: Player = context.controller if damage_controller \
			else (opps[0] if opps.size() > 0 else context.controller)
		target_player.take_damage(damage)


class GainLifePointsStep extends EffectResolutionStep:
	@export var amount:           int  = 0
	@export var use_atk_snapshot: bool = false

	func execute(context: EffectContext) -> void:
		var gain := context.source_atk_snapshot if use_atk_snapshot else amount
		context.controller.gain_lp(gain)


# ══════════════════════════════════════════════════════════════════════════════
# SEARCH (ADD TO HAND FROM DECK)
# ══════════════════════════════════════════════════════════════════════════════

class SearchDeckStep extends EffectResolutionStep:
	## In a full game, GameDirector pauses resolution, shows search UI,
	## sets chosen_card, then resumes. In tests the first deck card is used.
	var chosen_card: CardInstance = null

	func execute(context: EffectContext) -> void:
		var z    := EffectResolutionStep.zm()
		var deck := z.deck_of(context.controller)
		var card := chosen_card if chosen_card != null else deck.peek_top()
		if card == null:
			push_warning("SearchDeckStep: deck is empty")
			return
		z.move(card, z.hand_of(context.controller), ZoneManager.MoveReason.EFFECT_RETURN)
		z.shuffle_deck(context.controller)
		chosen_card = null


# ══════════════════════════════════════════════════════════════════════════════
# COUNTERS
# ══════════════════════════════════════════════════════════════════════════════

class AddCounterStep extends EffectResolutionStep:
	@export var counter_name: StringName = &"spell_counter"
	@export var amount:       int        = 1
	@export var on_source:    bool       = true

	func execute(context: EffectContext) -> void:
		if on_source:
			context.source_card.add_counter(counter_name, amount)
		else:
			for card in context.valid_targets():
				card.add_counter(counter_name, amount)


class RemoveCounterStep extends EffectResolutionStep:
	@export var counter_name: StringName = &"spell_counter"
	@export var amount:       int        = 1
	@export var on_source:    bool       = true

	func execute(context: EffectContext) -> void:
		if on_source:
			context.source_card.remove_counter(counter_name, amount)
		else:
			for card in context.valid_targets():
				card.remove_counter(counter_name, amount)


# ══════════════════════════════════════════════════════════════════════════════
# NEGATE
# ══════════════════════════════════════════════════════════════════════════════

class NegateTopChainLinkStep extends EffectResolutionStep:
	## Used by counter traps (Solemn Judgment, etc.).
	## Negates the link directly below this one on the chain.
	func execute(context: EffectContext) -> void:
		if not Engine.has_singleton(&"EffectStack"):
			push_warning("NegateTopChainLinkStep: EffectStack singleton not registered")
			return
		var stack: EffectStack = Engine.get_singleton(&"EffectStack")
		var target_index := context.chain_index - 1
		if target_index >= 1:
			stack.negate_link(target_index, context.source_card)


class NegateSummonStep extends EffectResolutionStep:
	## Negates the summon referenced by the trigger event.
	func execute(context: EffectContext) -> void:
		if context.trigger_event == null:
			return
		var summoned := context.trigger_event.primary_card
		if summoned == null or not summoned.is_on_field():
			return
		var z := EffectResolutionStep.zm()
		z.move(summoned, z.graveyard_of(summoned.controller), ZoneManager.MoveReason.EFFECT_DESTROY)


# ══════════════════════════════════════════════════════════════════════════════
# SET FLAG
# ══════════════════════════════════════════════════════════════════════════════

class SetFlagStep extends EffectResolutionStep:
	@export var flag_name:  StringName = &""
	@export var flag_value: bool       = true   ## Variant not exportable; use bool
	@export var on_targets: bool       = false

	func execute(context: EffectContext) -> void:
		if on_targets:
			for card in context.valid_targets():
				card.set_flag(flag_name, flag_value)
		else:
			context.source_card.set_flag(flag_name, flag_value)
