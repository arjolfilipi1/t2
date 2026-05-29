## GameEvent.gd
## Describes a discrete game event that may trigger automatic effects.
## Created by GameDirector/ZoneManager when something noteworthy happens,
## then passed to EffectStack.evaluate_triggers() for window processing.
##
## Events are immutable value objects — create-once, read-many.
class_name GameEvent
extends RefCounted

# ─── Event Types ──────────────────────────────────────────────────────────────

enum EventType {
	## Card movement events
	CARD_SUMMONED_NORMAL,
	CARD_SUMMONED_SPECIAL,
	CARD_SUMMONED_FLIP,
	CARD_DESTROYED,       ## Any destruction (battle or effect)
	CARD_SENT_TO_GY,
	CARD_BANISHED,
	CARD_RETURNED_TO_HAND,
	CARD_RETURNED_TO_DECK,
	CARD_SET,

	## Battle events
	ATTACK_DECLARED,      ## Attacker declared, before damage step
	BATTLE_DAMAGE_DEALT,  ## LP damage from battle resolved
	EFFECT_DAMAGE_DEALT,  ## LP damage from an effect resolved
	DIRECT_ATTACK,

	## Turn events
	TURN_START,
	DRAW_PHASE_START,
	STANDBY_PHASE_START,
	MAIN_PHASE_1_START,
	BATTLE_PHASE_START,
	MAIN_PHASE_2_START,
	END_PHASE_START,
	CARD_DRAWN,

	## Effect events
	EFFECT_ACTIVATED,
	EFFECT_NEGATED,
	SUMMON_NEGATED,

	## LP events
	LP_DECREASED,
	LP_INCREASED,
}

# ─── Core Fields ──────────────────────────────────────────────────────────────

var event_type: EventType

## The primary card involved (the summoned card, destroyed card, attacker, etc.)
var primary_card: CardInstance = null

## Secondary card (e.g. the attack target, the equip target).
var secondary_card: CardInstance = null

## The player who caused or is most responsible for this event.
var cause_player: Player = null

## The player who is the subject of this event (e.g. who took damage).
var subject_player: Player = null

## Numeric data associated with the event (damage amount, LP change, etc.)
var value: int = 0

## The move reason that caused a card to change zone (for zone-change events).
var move_reason: ZoneManager.MoveReason = ZoneManager.MoveReason.RULE

## Additional payload for complex events.
var data: Dictionary = {}

# ─── Factory Methods ──────────────────────────────────────────────────────────

static func card_summoned(card: CardInstance, normal: bool) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.CARD_SUMMONED_NORMAL if normal else EventType.CARD_SUMMONED_SPECIAL
	e.primary_card = card
	e.cause_player = card.controller
	return e

static func card_destroyed(card: CardInstance, by_player: Player, reason: ZoneManager.MoveReason) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.CARD_DESTROYED
	e.primary_card = card
	e.cause_player = by_player
	e.move_reason  = reason
	return e

static func card_sent_to_gy(card: CardInstance, by_player: Player, reason: ZoneManager.MoveReason) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.CARD_SENT_TO_GY
	e.primary_card = card
	e.cause_player = by_player
	e.move_reason  = reason
	return e

static func card_banished(card: CardInstance, by_player: Player) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.CARD_BANISHED
	e.primary_card = card
	e.cause_player = by_player
	return e

static func attack_declared(attacker: CardInstance, target: CardInstance, by_player: Player) -> GameEvent:
	var e := GameEvent.new()
	e.event_type      = EventType.ATTACK_DECLARED
	e.primary_card    = attacker
	e.secondary_card  = target
	e.cause_player    = by_player
	return e

static func damage_dealt(amount: int, to_player: Player, by_player: Player, from_battle: bool) -> GameEvent:
	var e := GameEvent.new()
	e.event_type    = EventType.BATTLE_DAMAGE_DEALT if from_battle else EventType.EFFECT_DAMAGE_DEALT
	e.value         = amount
	e.subject_player = to_player
	e.cause_player   = by_player
	return e

static func card_drawn(card: CardInstance, by_player: Player) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.CARD_DRAWN
	e.primary_card = card
	e.cause_player = by_player
	return e

static func phase_started(type: EventType, active_player: Player) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = type
	e.cause_player = active_player
	return e

static func effect_activated(ctx: EffectContext) -> GameEvent:
	var e := GameEvent.new()
	e.event_type   = EventType.EFFECT_ACTIVATED
	e.primary_card = ctx.source_card
	e.cause_player = ctx.controller
	e.data[&"context"] = ctx
	return e

# ─── Matching Helpers ─────────────────────────────────────────────────────────

## Maps EffectDefinition.EffectTrigger values to the GameEvent types that satisfy them.
static func triggers_match(trigger: EffectDefinition.EffectTrigger, event: GameEvent) -> bool:
	match trigger:
		EffectDefinition.EffectTrigger.ON_SUMMON:
			return event.event_type in [
				EventType.CARD_SUMMONED_NORMAL,
				EventType.CARD_SUMMONED_SPECIAL,
				EventType.CARD_SUMMONED_FLIP,
			]
		EffectDefinition.EffectTrigger.ON_DESTROY:
			return event.event_type == EventType.CARD_DESTROYED
		EffectDefinition.EffectTrigger.ON_SEND_TO_GY:
			return event.event_type == EventType.CARD_SENT_TO_GY
		EffectDefinition.EffectTrigger.ON_BANISH:
			return event.event_type == EventType.CARD_BANISHED
		EffectDefinition.EffectTrigger.ON_FLIP:
			return event.event_type == EventType.CARD_SUMMONED_FLIP
		EffectDefinition.EffectTrigger.ON_DRAW:
			return event.event_type == EventType.CARD_DRAWN
		EffectDefinition.EffectTrigger.ON_DAMAGE:
			return event.event_type in [
				EventType.BATTLE_DAMAGE_DEALT,
				EventType.EFFECT_DAMAGE_DEALT,
			]
		EffectDefinition.EffectTrigger.ON_ATTACK:
			return event.event_type == EventType.ATTACK_DECLARED
		EffectDefinition.EffectTrigger.STANDBY_PHASE:
			return event.event_type == EventType.STANDBY_PHASE_START
		EffectDefinition.EffectTrigger.START_OF_TURN:
			return event.event_type == EventType.TURN_START
		EffectDefinition.EffectTrigger.END_OF_TURN:
			return event.event_type == EventType.END_PHASE_START
	return false

func _to_string() -> String:
	return "GameEvent(%s, card=%s)" % [
		EventType.keys()[event_type],
		primary_card.definition.card_name if primary_card else "none"
	]
