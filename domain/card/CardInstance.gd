## CardInstance.gd
## Runtime representation of a single card in play.
## Wraps an immutable CardDefinition and holds all mutable game state.
## One instance per physical card in a game session — never reused across games.
class_name CardInstance
extends RefCounted

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after any stat is changed by a modifier (atk, def, level, etc.)
signal stat_changed(card: CardInstance, stat: StringName, old_value: int, new_value: int)

## Emitted when this card moves to a new zone (handled by ZoneManager, but re-emitted here)
signal zone_changed(card: CardInstance, from_zone: Zone, to_zone: Zone)

## Emitted when a counter is added or removed
signal counter_changed(card: CardInstance, counter_name: StringName, old_count: int, new_count: int)

## Emitted when this card is destroyed (before it moves to GY)
signal destroyed(card: CardInstance, cause: DestroyedCause)

## Emitted when a flag is set or cleared
signal flag_changed(card: CardInstance, flag: StringName, value: Variant)

# ─── Enums ────────────────────────────────────────────────────────────────────

enum DestroyedCause { BATTLE, EFFECT, RULE }

enum FaceState { FACE_UP, FACE_DOWN }

# ─── Identity ─────────────────────────────────────────────────────────────────

## Globally unique within a game session. Assigned by CardFactory.
var instance_id: int

## Immutable card definition — NEVER write to this.
var definition: CardDefinition

# ─── Ownership ────────────────────────────────────────────────────────────────

## The player who owns this card (per deck origin). Does not change.
var owner: Player

## The player currently controlling this card. Can change via effects.
var controller: Player

# ─── Location ─────────────────────────────────────────────────────────────────

## Current zone. Null only before the first zone assignment.
var current_zone: Zone = null

## Slot index within the zone (-1 for unordered zones like hand/GY).
var slot_index: int = -1

## Face-up or face-down.
var face_state: FaceState = FaceState.FACE_DOWN

## Battle position (ATK / DEF). Only meaningful for monsters on the field.
var position: CardDefinition.Position = CardDefinition.Position.ATK

# ─── Runtime Stats (modified from base definition values) ─────────────────────

## Current ATK after all modifiers. Computed lazily via _compute_stat().
var _atk_modifiers: Array[StatModifier] = []
var _def_modifiers: Array[StatModifier] = []
var _level_modifiers: Array[StatModifier] = []

# ─── Counters ─────────────────────────────────────────────────────────────────

## Generic counter storage. Key = counter type name, value = count (int).
## e.g.  { &"spell_counter": 3, &"psyframe_counter": 1 }
var counters: Dictionary = {}

# ─── Flags ────────────────────────────────────────────────────────────────────

## Temporary boolean or value overrides applied by effects.
## e.g.  { &"cannot_attack": true, &"unaffected_by_effects": true }
var flags: Dictionary = {}

# ─── Effect Tracking ──────────────────────────────────────────────────────────

## Tracks which effects have been used this turn.
## Key = effect index in definition.effects. Value = turn number it was used.
var used_effects: Dictionary = {}

## Tracks which once-per-duel effects have been used.
var used_effects_duel: Dictionary = {}

## Turn this card was summoned (used for "summoning sickness" and timing checks).
var summoned_on_turn: int = -1

## Whether this monster has already attacked this turn.
var has_attacked: bool = false

## Whether this card was Special Summoned (relevant for some effect conditions).
var was_special_summoned: bool = false

## The Special Summon method used, if any.
var special_summon_method: StringName = &""

# ─── Equip / Attachment ───────────────────────────────────────────────────────

## Cards attached to this card (Xyz materials, Equip spells targeting this).
var attached_cards: Array[CardInstance] = []

## The card this instance is attached to (if it is a material/equip).
var attached_to: CardInstance = null

# ─── Factory / Initializer ────────────────────────────────────────────────────

static var _next_id: int = 0

static func create(def: CardDefinition, owner_player: Player) -> CardInstance:
	var inst := CardInstance.new()
	inst.instance_id = _next_id
	_next_id += 1
	inst.definition = def
	inst.owner = owner_player
	inst.controller = owner_player
	return inst

# ─── Stat Access ──────────────────────────────────────────────────────────────

func get_atk() -> int:
	return _compute_stat(&"atk", definition.atk, _atk_modifiers)

func get_def() -> int:
	return _compute_stat(&"def", definition.def, _def_modifiers)

func get_level() -> int:
	return _compute_stat(&"level", definition.level, _level_modifiers)

func _compute_stat(stat_name: StringName, base: int, modifiers: Array[StatModifier]) -> int:
	var result := base
	# Apply additive modifiers first
	for mod in modifiers:
		if mod.type == StatModifier.ModType.ADDITIVE:
			result += mod.value
	# Then apply SET modifiers (last SET wins)
	for mod in modifiers:
		if mod.type == StatModifier.ModType.SET:
			result = mod.value
	return max(0, result)

# ─── Modifier Management ──────────────────────────────────────────────────────

func add_modifier(mod: StatModifier) -> void:
	var stat := mod.stat
	var old_val := _get_stat_value(stat)
	match stat:
		&"atk":   _atk_modifiers.append(mod)
		&"def":   _def_modifiers.append(mod)
		&"level": _level_modifiers.append(mod)
		_:
			push_warning("CardInstance: unknown stat '%s' for modifier" % stat)
			return
	var new_val := _get_stat_value(stat)
	if old_val != new_val:
		stat_changed.emit(self, stat, old_val, new_val)

func remove_modifier(mod: StatModifier) -> void:
	var stat := mod.stat
	var old_val := _get_stat_value(stat)
	match stat:
		&"atk":   _atk_modifiers.erase(mod)
		&"def":   _def_modifiers.erase(mod)
		&"level": _level_modifiers.erase(mod)
	var new_val := _get_stat_value(stat)
	if old_val != new_val:
		stat_changed.emit(self, stat, old_val, new_val)

## Remove all modifiers that were applied by a specific source card.
func remove_modifiers_from(source_id: int) -> void:
	var stats := [
		[&"atk",   _atk_modifiers],
		[&"def",   _def_modifiers],
		[&"level", _level_modifiers],
	]
	for pair in stats:
		var stat: StringName = pair[0]
		var list: Array = pair[1]
		var old_val := _get_stat_value(stat)
		list = list.filter(func(m): return m.source_instance_id != source_id)
		var new_val := _get_stat_value(stat)
		if old_val != new_val:
			stat_changed.emit(self, stat, old_val, new_val)

func _get_stat_value(stat: StringName) -> int:
	match stat:
		&"atk":   return get_atk()
		&"def":   return get_def()
		&"level": return get_level()
	return 0

# ─── Counter Management ───────────────────────────────────────────────────────

func add_counter(counter_name: StringName, amount: int = 1) -> void:
	var old = counters.get(counter_name, 0)
	counters[counter_name] = old + amount
	counter_changed.emit(self, counter_name, old, counters[counter_name])

func remove_counter(counter_name: StringName, amount: int = 1) -> bool:
	var old = counters.get(counter_name, 0)
	if old < amount:
		return false   ## Not enough counters
	counters[counter_name] = old - amount
	if counters[counter_name] == 0:
		counters.erase(counter_name)
	counter_changed.emit(self, counter_name, old, counters.get(counter_name, 0))
	return true

func get_counter(counter_name: StringName) -> int:
	return counters.get(counter_name, 0)

func has_counter(counter_name: StringName, min_amount: int = 1) -> bool:
	return counters.get(counter_name, 0) >= min_amount

# ─── Flag Management ──────────────────────────────────────────────────────────

func set_flag(flag: StringName, value: Variant = true) -> void:
	var old = flags.get(flag, null)
	flags[flag] = value
	if old != value:
		flag_changed.emit(self, flag, value)

func clear_flag(flag: StringName) -> void:
	if flags.has(flag):
		flags.erase(flag)
		flag_changed.emit(self, flag, null)

func has_flag(flag: StringName) -> bool:
	return flags.get(flag, false) == true

# ─── Effect Usage Tracking ────────────────────────────────────────────────────

func mark_effect_used(effect_index: int, turn_number: int) -> void:
	used_effects[effect_index] = turn_number

func was_effect_used_this_turn(effect_index: int, current_turn: int) -> bool:
	print("checked once per turn for ",definition.card_id)
	print("result ",used_effects)
	return used_effects.get(effect_index, -1) == current_turn

func mark_effect_used_duel(effect_index: int) -> void:
	used_effects_duel[effect_index] = true

func was_effect_used_this_duel(effect_index: int) -> bool:
	return used_effects_duel.get(effect_index, false)

func reset_turn_state() -> void:
	## Called at the start of each turn by TurnManager.
	has_attacked = false
	used_effects.clear()

# ─── Attachment Management ────────────────────────────────────────────────────

func attach(card: CardInstance) -> void:
	if card in attached_cards:
		return
	attached_cards.append(card)
	card.attached_to = self

func detach(card: CardInstance) -> void:
	attached_cards.erase(card)
	card.attached_to = null

func detach_all() -> Array[CardInstance]:
	var detached := attached_cards.duplicate()
	for card in detached:
		card.attached_to = null
	attached_cards.clear()
	return detached

# ─── Summon State ─────────────────────────────────────────────────────────────

func record_normal_summon(turn: int) -> void:
	summoned_on_turn = turn
	was_special_summoned = false
	position = CardDefinition.Position.ATK
	face_state = FaceState.FACE_UP

func record_special_summon(turn: int, method: StringName) -> void:
	summoned_on_turn = turn
	was_special_summoned = true
	special_summon_method = method

func has_summoning_sickness(current_turn: int) -> bool:
	## A monster cannot attack on the same turn it was Normal Summoned,
	## unless it has an effect that negates this.
	if has_flag(&"can_attack_immediately"):
		return false
	return (not was_special_summoned) and (summoned_on_turn == current_turn)

# ─── Convenience Accessors ────────────────────────────────────────────────────
func is_in_deck() -> bool:
	if current_zone == null:
		return false
	return current_zone.zone_type in [
		Zone.ZoneType.DECK,
		Zone.ZoneType.EXTRA_DECK
	]
func is_on_field() -> bool:
	if current_zone == null:
		return false
	return current_zone.zone_type in [
		Zone.ZoneType.MAIN_MONSTER,
		Zone.ZoneType.EXTRA_MONSTER,
		Zone.ZoneType.MAIN_SPELL,
		Zone.ZoneType.FIELD_SPELL,
	]

func is_in_hand() -> bool:
	return current_zone != null and current_zone.zone_type == Zone.ZoneType.HAND

func is_in_graveyard() -> bool:
	return current_zone != null and current_zone.zone_type == Zone.ZoneType.GRAVEYARD

func is_banished() -> bool:
	return current_zone != null and current_zone.zone_type == Zone.ZoneType.BANISHED

func is_face_up() -> bool:
	return face_state == FaceState.FACE_UP

func is_face_down() -> bool:
	return face_state == FaceState.FACE_DOWN

func is_in_atk_position() -> bool:
	return position == CardDefinition.Position.ATK

func is_in_def_position() -> bool:
	return position in [
		CardDefinition.Position.DEF,
		CardDefinition.Position.FACE_DOWN_DEF,
	]

# ─── Debug ────────────────────────────────────────────────────────────────────

func _to_string() -> String:
	return "CardInstance(id=%d, name=%s, zone=%s)" % [
		instance_id,
		definition.card_name,
		current_zone.zone_id if current_zone else "none"
	]
