## CardFactory.gd
## Creates CardInstance objects from CardDefinition resources.
## Also handles deck loading from JSON or .tres resource arrays.
## Keeps instance_id unique across the entire session.
class_name CardFactory
extends RefCounted

# ─── Instance ID Counter ──────────────────────────────────────────────────────

## Reset at the start of each game session.
static var _counter: int = 0

static func reset_counter() -> void:
	_counter = 0

# ─── Creation ─────────────────────────────────────────────────────────────────

static func create(definition: CardDefinition, owner: Player) -> CardInstance:
	assert(definition != null, "CardFactory.create: definition is null")
	var inst := CardInstance.new()
	inst.instance_id = _counter
	_counter += 1
	inst.definition  = definition
	inst.owner       = owner
	inst.controller  = owner
	return inst

## Create multiple copies of the same definition (e.g. 3x copies in a deck).
static func create_copies(definition: CardDefinition, owner: Player, count: int) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for i in count:
		result.append(create(definition, owner))
	return result

# ─── Deck Loading ─────────────────────────────────────────────────────────────

## Build a list of CardInstances from a deck definition dictionary.
## deck_def format:
##   {
##     "main": [ { "id": "dark_magician", "count": 3 }, ... ],
##     "extra": [ ... ],
##     "side":  [ ... ]
##   }
## card_db: Dictionary[StringName → CardDefinition]
static func build_deck(
	deck_def: Dictionary,
	card_db: Dictionary,
	owner: Player
) -> Dictionary:
	var result := {
		"main":  [] as Array[CardInstance],
		"extra": [] as Array[CardInstance],
		"side":  [] as Array[CardInstance],
	}

	for section in ["main", "extra", "side"]:
		if not deck_def.has(section):
			continue
		for entry in deck_def[section]:
			var card_id: StringName = StringName(entry["id"])
			var count: int = entry.get("count", 1)
			var def: CardDefinition = card_db.get(card_id, null)
			if def == null:
				push_error("CardFactory: unknown card id '%s'" % card_id)
				continue
			for i in count:
				result[section].append(create(def, owner))

	return result

## Load a deck JSON file and return the raw dictionary.
static func load_deck_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CardFactory: deck file not found at '%s'" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("CardFactory: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return {}
	return json.data

# ─── Example Deck JSON Format ─────────────────────────────────────────────────
##
## res://data/decks/dark_magician.json
## {
##   "name": "Dark Magician",
##   "main": [
##     { "id": "dark_magician",          "count": 3 },
##     { "id": "dark_magician_girl",     "count": 2 },
##     { "id": "eternal_soul",           "count": 3 },
##     { "id": "dark_magic_circle",      "count": 3 },
##     { "id": "illusion_magic",         "count": 2 }
##   ],
##   "extra": [
##     { "id": "dark_paladin",           "count": 1 },
##     { "id": "amulet_dragon",          "count": 1 }
##   ],
##   "side": []
## }
