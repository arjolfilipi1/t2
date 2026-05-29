## PendingTrigger.gd
## A trigger or mandatory effect that has been detected and is waiting
## for the priority window to be resolved.
##
## Mandatory triggers MUST be placed on the chain in SEGOC order
## (Simultaneous Effects Go On Chain). Optional triggers may be declined.
##
## SEGOC resolution order (official):
##   1. Turn player's mandatory effects
##   2. Non-turn player's mandatory effects
##   3. Turn player's optional effects  (player chooses which, if any)
##   4. Non-turn player's optional effects
class_name PendingTrigger
extends RefCounted

## The card whose effect triggered.
var source_card: CardInstance

## The specific effect that triggered.
var effect: EffectDefinition

## Index of the effect in source_card.definition.effects.
var effect_index: int

## The controller at the time the trigger fired.
var controller: Player

## The game event that caused this trigger.
var trigger_event: GameEvent

## Targets pre-selected for this trigger (if targetless, empty).
var targets: Array[CardInstance] = []

## Whether this trigger MUST be placed (mandatory) or is player's choice.
var is_mandatory: bool = false

## True once this trigger has been placed on the chain or explicitly declined.
var is_handled: bool = false

static func create(
	card: CardInstance,
	eff: EffectDefinition,
	eff_index: int,
	activating_player: Player,
	event: GameEvent,
	mandatory: bool = false
) -> PendingTrigger:
	var pt := PendingTrigger.new()
	pt.source_card   = card
	pt.effect        = eff
	pt.effect_index  = eff_index
	pt.controller    = activating_player
	pt.trigger_event = event
	pt.is_mandatory  = mandatory
	return pt

func _to_string() -> String:
	return "PendingTrigger(%s.%s [%s])" % [
		source_card.definition.card_name,
		effect.effect_name,
		"MANDATORY" if is_mandatory else "OPTIONAL"
	]
