## StatModifier.gd
## A single modification to a card stat, applied at runtime.
## Modifiers are owned by the effect that created them and
## removed when that effect expires (end of turn, card leaves field, etc.)
class_name StatModifier
extends RefCounted

enum ModType {
	ADDITIVE,  ## Adds value to the base stat  (+500, -200, etc.)
	SET,       ## Overrides the stat to a fixed value (e.g. "ATK becomes 0")
}

## The stat this modifier targets.
var stat: StringName  ## &"atk", &"def", &"level"

## Modifier type.
var type: ModType = ModType.ADDITIVE

## The value to add or set.
var value: int

## Which CardInstance created this modifier (for cleanup).
var source_instance_id: int

## Which EffectDefinition index on the source card created this.
var source_effect_index: int

## Which turn this modifier expires. -1 = permanent (until source leaves field).
var expires_on_turn: int = -1

## Human-readable label for debugging and UI tooltips.
var label: String = ""

static func additive(
	stat_name: StringName,
	amount: int,
	source_id: int,
	effect_idx: int = -1,
	expires: int = -1,
	lbl: String = ""
) -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_name
	m.type = ModType.ADDITIVE
	m.value = amount
	m.source_instance_id = source_id
	m.source_effect_index = effect_idx
	m.expires_on_turn = expires
	m.label = lbl
	return m

static func set_value(
	stat_name: StringName,
	fixed_value: int,
	source_id: int,
	effect_idx: int = -1,
	expires: int = -1,
	lbl: String = ""
) -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_name
	m.type = ModType.SET
	m.value = fixed_value
	m.source_instance_id = source_id
	m.source_effect_index = effect_idx
	m.expires_on_turn = expires
	m.label = lbl
	return m

func _to_string() -> String:
	var type_str := "+" if type == ModType.ADDITIVE else "="
	return "StatModifier(%s %s%d from #%d)" % [stat, type_str, value, source_instance_id]
