## CardDefinitionLoader.gd
## Builds CardDefinition objects from plain Dictionaries (typically parsed
## from JSON card files). This is what lets most cards be written as data
## instead of GDScript.
##
## SCOPE: this loader only knows how to construct the EffectCost /
## EffectCondition / EffectResolutionStep TYPES that exist in this codebase
## right now. Adding a new step/condition/cost type to those files requires
## one line here too — see _STEP_TYPES / _CONDITION_TYPES / _COST_TYPES below.
##
## Cards needing logic beyond what the registry can express should NOT be
## forced into this format — write them as a normal EffectDefinition
## subclass (see ash_blossom for an example) and skip this loader entirely.
##
## ─── JSON CARD FORMAT ──────────────────────────────────────────────────────────
## {
##   "id": "lightning_vortex",
##   "name": "Lightning Vortex",
##   "type": "spell",                 // "monster" | "spell" | "trap"
##   "spell_type": "normal",          // only if type == "spell"
##   "text": "Discard 1 card to destroy...",
##
##   // monster-only fields:
##   "attribute": "dark",
##   "monster_type": "Spellcaster",
##   "monster_kind": "effect",
##   "level": 7, "atk": 2500, "def": 2100,
##
##   "effects": [
##     {
##       "name": "Destroy all opponent monsters",
##       "spell_speed": 1,
##       "category": "ignition",       // "ignition" | "trigger" | "quick" | "continuous" | "flip"
##       "timing": "optional",         // "mandatory" | "optional" | "quick_effect" | "counter"
##       "trigger": "none",            // EffectTrigger name, lowercase
##       "once_per_turn": false,
##       "targets_required": 0,
##       "costs": [
##         { "type": "discard", "count": 1 }
##       ],
##       "conditions": [
##         { "type": "opponent_monster_count", "min_count": 1 }
##       ],
##       "resolution": [
##         { "type": "destroy_all_monsters", "include_controller": false }
##       ]
##     }
##   ]
## }
class_name CardDefinitionLoader
extends RefCounted

# ─── Type Registries ──────────────────────────────────────────────────────────
## Maps the JSON "type" string to the GDScript class that implements it.
## Extend these dictionaries whenever a new Cost/Condition/Step is added.

const _COST_TYPES := {
	"life_points":      EffectCost.LifePointCost,
	"discard":          EffectCost.DiscardCost,
	"discard_self":     EffectCost.DiscardSelfCost,
	"tribute":          EffectCost.TributeCost,
	"send_self_to_gy":  EffectCost.SendSelfToGYCost,
	"banish":           EffectCost.BanishCost,
	"remove_counter":   EffectCost.RemoveCounterCost,
}

const _CONDITION_TYPES := {
	"phase":                  EffectCondition.PhaseCondition,
	"once_per_turn":          EffectCondition.OncePerTurnCondition,
	"once_per_duel":          EffectCondition.OncePerDuelCondition,
	"control_monster_count":  EffectCondition.ControlMonsterCountCondition,
	"opponent_monster_count": EffectCondition.OpponentMonsterCountCondition,
	"source_in_zone":         EffectCondition.SourceInZoneCondition,
	"graveyard_count":        EffectCondition.GraveyardCountCondition,
	"hand_size":              EffectCondition.HandSizeCondition,
	"life_point":             EffectCondition.LifePointCondition,
	"attribute":              EffectCondition.AttributeCondition,
	"monster_type":           EffectCondition.MonsterTypeCondition,
	"is_monster":             EffectCondition.IsMosterCondition,
	"atk_range":              EffectCondition.AtkRangeCondition,
	"level":                  EffectCondition.LevelCondition,
	"flag":                   EffectCondition.FlagCondition,
	"has_counter":            EffectCondition.HasCounterCondition,
}

const _STEP_TYPES := {
	"destroy_target":        EffectResolutionStep.DestroyTargetsStep,
	"destroy_all_monsters":  EffectResolutionStep.DestroyAllMonstersStep,
	"draw":                  EffectResolutionStep.DrawCardsStep,
	"send_to_gy":            EffectResolutionStep.SendToGraveyardStep,
	"banish":                EffectResolutionStep.BanishTargetsStep,
	"return_to_hand":        EffectResolutionStep.ReturnToHandStep,
	"special_summon_target": EffectResolutionStep.SpecialSummonTargetStep,
	"modify_stat":           EffectResolutionStep.ModifyStatStep,
	"deal_damage":           EffectResolutionStep.DealDamageStep,
	"gain_lp":               EffectResolutionStep.GainLifePointsStep,
	"search_deck":           EffectResolutionStep.SearchDeckStep,
	"add_counter":           EffectResolutionStep.AddCounterStep,
	"remove_counter":        EffectResolutionStep.RemoveCounterStep,
	"negate_top_chain_link": EffectResolutionStep.NegateTopChainLinkStep,
	"negate_summon":         EffectResolutionStep.NegateSummonStep,
	"set_flag":              EffectResolutionStep.SetFlagStep,
}

# ─── Enum Lookups ─────────────────────────────────────────────────────────────
## JSON has no enum type — every enum value arrives as a lowercase string
## and is mapped here. Keys must match CardDefinition / EffectDefinition
## enum names, lowercased.

const _CARD_TYPE := {
	"monster": CardDefinition.CardType.MONSTER,
	"spell":   CardDefinition.CardType.SPELL,
	"trap":    CardDefinition.CardType.TRAP,
}
const _ATTRIBUTE := {
	"dark": CardDefinition.Attribute.DARK, "light": CardDefinition.Attribute.LIGHT,
	"earth": CardDefinition.Attribute.EARTH, "water": CardDefinition.Attribute.WATER,
	"fire": CardDefinition.Attribute.FIRE, "wind": CardDefinition.Attribute.WIND,
	"divine": CardDefinition.Attribute.DIVINE,
}
const _SPELL_TYPE := {
	"normal": CardDefinition.SpellType.NORMAL, "continuous": CardDefinition.SpellType.CONTINUOUS,
	"equip": CardDefinition.SpellType.EQUIP, "field": CardDefinition.SpellType.FIELD,
	"quick_play": CardDefinition.SpellType.QUICK_PLAY, "ritual": CardDefinition.SpellType.RITUAL,
}
const _TRAP_TYPE := {
	"normal": CardDefinition.TrapType.NORMAL, "continuous": CardDefinition.TrapType.CONTINUOUS,
	"counter": CardDefinition.TrapType.COUNTER,
}
const _MONSTER_KIND := {
	"normal": CardDefinition.MonsterKind.NORMAL, "effect": CardDefinition.MonsterKind.EFFECT,
	"ritual": CardDefinition.MonsterKind.RITUAL, "fusion": CardDefinition.MonsterKind.FUSION,
	"synchro": CardDefinition.MonsterKind.SYNCHRO, "xyz": CardDefinition.MonsterKind.XYZ,
	"link": CardDefinition.MonsterKind.LINK, "pendulum": CardDefinition.MonsterKind.PENDULUM,
}
const _EFFECT_TRIGGER := {
	"none": EffectDefinition.EffectTrigger.NONE, "on_summon": EffectDefinition.EffectTrigger.ON_SUMMON,
	"on_destroy": EffectDefinition.EffectTrigger.ON_DESTROY, "on_send_to_gy": EffectDefinition.EffectTrigger.ON_SEND_TO_GY,
	"on_banish": EffectDefinition.EffectTrigger.ON_BANISH, "on_flip": EffectDefinition.EffectTrigger.ON_FLIP,
	"on_draw": EffectDefinition.EffectTrigger.ON_DRAW, "on_damage": EffectDefinition.EffectTrigger.ON_DAMAGE,
	"on_battle": EffectDefinition.EffectTrigger.ON_BATTLE, "on_attack": EffectDefinition.EffectTrigger.ON_ATTACK,
	"start_of_turn": EffectDefinition.EffectTrigger.START_OF_TURN, "end_of_turn": EffectDefinition.EffectTrigger.END_OF_TURN,
	"standby_phase": EffectDefinition.EffectTrigger.STANDBY_PHASE,
}
const _EFFECT_TIMING := {
	"mandatory": EffectDefinition.EffectTiming.MANDATORY, "optional": EffectDefinition.EffectTiming.OPTIONAL,
	"quick_effect": EffectDefinition.EffectTiming.QUICK_EFFECT, "counter": EffectDefinition.EffectTiming.COUNTER,
}
const _EFFECT_CATEGORY := {
	"ignition": EffectDefinition.EffectCategory.IGNITION, "trigger": EffectDefinition.EffectCategory.TRIGGER,
	"quick": EffectDefinition.EffectCategory.QUICK, "continuous": EffectDefinition.EffectCategory.CONTINUOUS,
	"flip": EffectDefinition.EffectCategory.FLIP,
}

# ─── Public API ───────────────────────────────────────────────────────────────

## Build a single CardDefinition from a parsed JSON dictionary.
## Returns null (and pushes an error) if the card data is malformed.
static func build_card(data: Dictionary) -> CardDefinition:
	if not data.has("id") or not data.has("name") or not data.has("type"):
		push_error("CardDefinitionLoader: card missing required field 'id'/'name'/'type': %s" % data)
		return null

	var def := CardDefinition.new()
	def.card_id   = StringName(data["id"])
	def.card_name = data["name"]
	def.card_text = data.get("text", "")

	var type_str: String = data["type"]
	if not _CARD_TYPE.has(type_str):
		push_error("CardDefinitionLoader: unknown card type '%s' on '%s'" % [type_str, def.card_id])
		return null
	def.card_type = _CARD_TYPE[type_str]

	match def.card_type:
		CardDefinition.CardType.MONSTER:
			_apply_monster_fields(def, data)
		CardDefinition.CardType.SPELL:
			def.spell_type = _lookup(_SPELL_TYPE, data.get("spell_type", "normal"), "spell_type", def.card_id)
		CardDefinition.CardType.TRAP:
			def.trap_type = _lookup(_TRAP_TYPE, data.get("trap_type", "normal"), "trap_type", def.card_id)

	var effects: Array = []
	for eff_data in data.get("effects", []):
		var eff := _build_effect(eff_data, def.card_id)
		if eff != null:
			effects.append(eff)
	def.effects = effects

	return def

## Load and build every card in a JSON file containing a top-level array
## of card dictionaries. Returns Dictionary[StringName → CardDefinition].
## Cards that fail to build are skipped (with an error already pushed by
## build_card) so one bad entry doesn't take down the whole file.
static func load_file(path: String) -> Dictionary:
	var result: Dictionary = {}

	if not FileAccess.file_exists(path):
		push_error("CardDefinitionLoader: file not found '%s'" % path)
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("CardDefinitionLoader: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return result

	var entries: Array = json.data
	for card_data in entries:
		var def := build_card(card_data)
		if def != null:
			result[def.card_id] = def

	return result

# ─── Monster Fields ───────────────────────────────────────────────────────────

static func _apply_monster_fields(def: CardDefinition, data: Dictionary) -> void:
	def.attribute    = _lookup(_ATTRIBUTE, data.get("attribute", "dark"), "attribute", def.card_id)
	def.monster_type  = data.get("monster_type", "")
	def.monster_kind  = _lookup(_MONSTER_KIND, data.get("monster_kind", "normal"), "monster_kind", def.card_id)
	def.level         = data.get("level", 1)
	def.atk           = data.get("atk", 0)
	def.def           = data.get("def", 0)

# ─── Effect Construction ──────────────────────────────────────────────────────

static func _build_effect(data: Dictionary, card_id: StringName) -> EffectDefinition:
	var eff := EffectDefinition.new()
	eff.effect_name   = data.get("name", "")
	eff.effect_text   = data.get("text", "")
	eff.spell_speed   = data.get("spell_speed", 1)
	eff.is_continuous = data.get("is_continuous", false)
	eff.once_per_turn = data.get("once_per_turn", true)
	eff.once_per_duel = data.get("once_per_duel", false)
	eff.targets_required = data.get("targets_required", 0)

	if data.has("trigger"):
		eff.trigger = _lookup(_EFFECT_TRIGGER, data["trigger"], "trigger", card_id)
	if data.has("timing"):
		eff.timing = _lookup(_EFFECT_TIMING, data["timing"], "timing", card_id)
	if data.has("category"):
		eff.category = _lookup(_EFFECT_CATEGORY, data["category"], "category", card_id)

	var costs: Array = []
	for c in data.get("costs", []):
		var cost := _build_typed(c, _COST_TYPES, "cost", card_id)
		if cost != null:
			costs.append(cost)
	eff.costs = costs

	var conditions: Array = []
	for c in data.get("conditions", []):
		var cond := _build_typed(c, _CONDITION_TYPES, "condition", card_id)
		if cond != null:
			conditions.append(cond)
	eff.conditions = conditions

	var target_conditions: Array = []
	for c in data.get("target_conditions", []):
		var cond := _build_typed(c, _CONDITION_TYPES, "target_condition", card_id)
		if cond != null:
			target_conditions.append(cond)
	eff.target_conditions = target_conditions

	var steps: Array = []
	for s in data.get("resolution", []):
		var step := _build_typed(s, _STEP_TYPES, "resolution step", card_id)
		if step != null:
			steps.append(step)
	eff.resolution_steps = steps

	return eff

# ─── Generic Typed-Object Construction ────────────────────────────────────────

## Builds one Cost/Condition/Step instance from its dictionary, looking up
## the class via `registry[data["type"]]`, then copying every other key in
## `data` onto the instance's matching property via set().
static func _build_typed(data: Dictionary, registry: Dictionary, kind: String, card_id: StringName) -> Variant:
	if not data.has("type"):
		push_error("CardDefinitionLoader: %s on '%s' missing 'type' field: %s" % [kind, card_id, data])
		return null

	var type_str: String = data["type"]
	if not registry.has(type_str):
		push_error("CardDefinitionLoader: unknown %s type '%s' on '%s'" % [kind, type_str, card_id])
		return null

	var instance = registry[type_str].new()

	for key in data.keys():
		if key == "type":
			continue
		_set_field(instance, key, data[key], card_id)

	return instance

## Sets one property on a Cost/Condition/Step instance, converting the raw
## JSON value (String/int/float/bool/Array) into whatever type the target
## property actually needs (StringName, enum int, etc.)
static func _set_field(instance: Object, key: String, value: Variant, card_id: StringName) -> void:
	if not (key in instance):
		push_error("CardDefinitionLoader: '%s' has no field '%s' (on card '%s')" % [
			instance.get_script().get_global_name(), key, card_id
		])
		return

	var current = instance.get(key)

	## StringName fields arrive from JSON as plain String — cast them.
	if current is StringName and value is String:
		instance.set(key, StringName(value))
		return

	## Enum fields are ints at runtime but strings in JSON. Without a global
	## "which enum does this belong to" map, the convention here is: any
	## field holding an int that receives a String value is treated as an
	## enum and looked up against EffectCost.LifePointCost.Mode-style nested
	## enums via a tiny per-class table. Most step/condition enums are
	## small enough that this direct mapping covers them.
	if current is int and value is String:
		var resolved = _resolve_local_enum(instance, key, value, card_id)
		if resolved != null:
			instance.set(key, resolved)
		return

	instance.set(key, value)

## Handles the handful of fields whose value is a string but whose target
## is a *nested* enum defined inside a specific Cost/Condition class
## (e.g. LifePointCost.Mode, LifePointCondition.Mode, BanishCost.Source).
## Add an entry here whenever a new nested enum needs JSON support.
static func _resolve_local_enum(instance: Object, key: String, value: String, card_id: StringName) -> Variant:
	var class_name_str: String = instance.get_script().get_global_name()

	match "%s.%s" % [class_name_str, key]:
		"LifePointCost.mode":
			return {"fixed": EffectCost.LifePointCost.Mode.FIXED, "half": EffectCost.LifePointCost.Mode.HALF}.get(value)
		"LifePointCondition.mode":
			return {"at_most": EffectCondition.LifePointCondition.Mode.AT_MOST, "at_least": EffectCondition.LifePointCondition.Mode.AT_LEAST}.get(value)
		"BanishCost.from_source":
			return {"hand": EffectCost.BanishCost.Source.HAND, "field": EffectCost.BanishCost.Source.FIELD, "graveyard": EffectCost.BanishCost.Source.GRAVEYARD, "any": EffectCost.BanishCost.Source.ANY}.get(value)
		"SourceInZoneCondition.required_zone":
			return {"main_monster": Zone.ZoneType.MAIN_MONSTER, "hand": Zone.ZoneType.HAND, "graveyard": Zone.ZoneType.GRAVEYARD, "banished": Zone.ZoneType.BANISHED}.get(value)
		"AttributeCondition.required_attribute":
			return _ATTRIBUTE.get(value)

	push_error("CardDefinitionLoader: no enum mapping for '%s' on card '%s' — add one to _resolve_local_enum" % [
		"%s.%s" % [class_name_str, key], card_id
	])
	return null

# ─── Enum Lookup Helper ───────────────────────────────────────────────────────

static func _lookup(table: Dictionary, key: String, field_name: String, card_id: StringName) -> int:
	if not table.has(key):
		push_error("CardDefinitionLoader: unknown %s value '%s' on card '%s'" % [field_name, key, card_id])
		return 0
	return table[key]
