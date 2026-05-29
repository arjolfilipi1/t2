## CardDatabase.gd
## Singleton (AutoLoad) that loads all CardDefinition resources at startup.
## Vends definitions by ID. Never holds CardInstance objects.
##
## Usage:
##   var def := CardDatabase.get_card(&"dark_magician")
class_name CardDatabase
extends Node

# ─── Storage ──────────────────────────────────────────────────────────────────

## All loaded definitions, keyed by card_id.
var _definitions: Dictionary = {}  ## StringName → CardDefinition

# ─── Initialization ───────────────────────────────────────────────────────────

## Call once at game startup. Path should contain *.tres files.
func load_from_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("CardDatabase: cannot open directory '%s'" % dir_path)
		return

	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var full_path := dir_path.path_join(filename)
			var res := ResourceLoader.load(full_path)
			if res is CardDefinition:
				_register(res)
			else:
				push_warning("CardDatabase: '%s' is not a CardDefinition" % full_path)
		filename = dir.get_next()
	dir.list_dir_end()

	print("CardDatabase: loaded %d definitions" % _definitions.size())

## Register a single definition (useful for tests or runtime additions).
func _register(def: CardDefinition) -> void:
	if _definitions.has(def.card_id):
		push_warning("CardDatabase: duplicate card_id '%s' — overwriting" % def.card_id)
	_definitions[def.card_id] = def

# ─── Access ───────────────────────────────────────────────────────────────────

func get_card(card_id: StringName) -> CardDefinition:
	var def := _definitions.get(card_id, null)
	if def == null:
		push_error("CardDatabase: card '%s' not found" % card_id)
	return def

func has_card(card_id: StringName) -> bool:
	return _definitions.has(card_id)

func all_definitions() -> Array[CardDefinition]:
	var result: Array[CardDefinition] = []
	for def in _definitions.values():
		result.append(def)
	return result

## Return definitions filtered by card type.
func get_by_type(type: CardDefinition.CardType) -> Array[CardDefinition]:
	return all_definitions().filter(func(d): return d.card_type == type)

## Return definitions filtered by attribute.
func get_by_attribute(attr: CardDefinition.Attribute) -> Array[CardDefinition]:
	return all_definitions().filter(func(d): return d.attribute == attr)

## Return definitions matching a monster type string (e.g. "Dragon").
func get_by_monster_type(monster_type: String) -> Array[CardDefinition]:
	return all_definitions().filter(
		func(d): return d.is_monster() and d.monster_type == monster_type
	)

func card_count() -> int:
	return _definitions.size()
