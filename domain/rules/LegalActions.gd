## LegalActions.gd
## Value object returned by RuleEngine.get_all_legal_actions().
## Describes everything a player is legally allowed to do right now.
## Consumed by:
##   - CardTooltip   → which buttons to show
##   - BoardView     → which cards to highlight as activatable
##   - AIController  → enumerate moves to evaluate
class_name LegalActions
extends RefCounted

## Monsters / spells / traps in hand that can be normal summoned.
var can_normal_summon: Array[CardInstance] = []

## Cards in hand that can be set face-down.
var can_set: Array[CardInstance] = []

## Cards with at least one activatable effect.
## Key: CardInstance, Value: Array[int] (effect indices)
var can_activate: Dictionary = {}

## Monsters on field that have at least one legal attack target.
## Key: CardInstance (attacker), Value: Array (targets, null = direct)
var can_attack: Dictionary = {}

## Monsters whose battle position can be changed.
var can_change_position: Array[CardInstance] = []

# ─── Helpers ──────────────────────────────────────────────────────────────────

func has_any_action() -> bool:
	return not (
		can_normal_summon.is_empty() and
		can_set.is_empty() and
		can_activate.is_empty() and
		can_attack.is_empty() and
		can_change_position.is_empty()
	)

func can_card_attack(card: CardInstance) -> bool:
	return can_attack.has(card)

func attack_targets_for(card: CardInstance) -> Array:
	return can_attack.get(card, [])

func can_card_activate(card: CardInstance) -> bool:
	return can_activate.has(card)

func activatable_effects_for(card: CardInstance) -> Array:
	return can_activate.get(card, [])

func _to_string() -> String:
	return "LegalActions(summon=%d set=%d activate=%d attack=%d pos=%d)" % [
		can_normal_summon.size(),
		can_set.size(),
		can_activate.size(),
		can_attack.size(),
		can_change_position.size(),
	]
