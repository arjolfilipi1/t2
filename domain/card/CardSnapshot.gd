## CardSnapshot.gd
## Captures every mutable field of a single CardInstance so it can be
## restored exactly later. Does NOT capture `definition`, `owner`, or
## `instance_id` — those never change after creation, so there is nothing
## to snapshot there; restoring just writes the captured values back onto
## the SAME CardInstance object (never creates a new one), which keeps
## every other reference to that card (in Zone arrays, attached_cards
## lists, etc.) automatically valid after restore.
class_name CardSnapshot
extends RefCounted

var instance_id:           int
var controller:            Player
var current_zone_id:       StringName   ## Zone is restored by ID, not by ref
var slot_index:            int
var face_state:            CardInstance.FaceState
var position:              CardDefinition.Position

## Stat modifiers are RefCounted value objects with no card-instance back-
## references, so they can be shared directly between snapshot and live
## state without needing their own deep copy.
var atk_modifiers:         Array[StatModifier]
var def_modifiers:         Array[StatModifier]
var level_modifiers:       Array[StatModifier]

var counters:               Dictionary   ## shallow copy is sufficient (StringName → int)
var flags:                  Dictionary   ## shallow copy is sufficient
var used_effects:           Dictionary
var used_effects_duel:      Dictionary

var summoned_on_turn:        int
var has_attacked:            bool
var was_special_summoned:    bool
var special_summon_method:   StringName

## Attachments are captured by instance_id, not by reference, and resolved
## back to live CardInstance objects during restore via the id→card map
## the caller (BoardSnapshot) provides.
var attached_card_ids:       Array
var attached_to_id:          int   ## -1 = not attached to anything

# ─── Capture ──────────────────────────────────────────────────────────────────

static func capture(card: CardInstance) -> CardSnapshot:
	var s := CardSnapshot.new()
	s.instance_id         = card.instance_id
	s.controller          = card.controller
	s.current_zone_id     = card.current_zone.zone_id if card.current_zone != null else &""
	s.slot_index          = card.slot_index
	s.face_state          = card.face_state
	s.position            = card.position

	s.atk_modifiers       = card._atk_modifiers.duplicate()
	s.def_modifiers       = card._def_modifiers.duplicate()
	s.level_modifiers     = card._level_modifiers.duplicate()

	s.counters            = card.counters.duplicate()
	s.flags               = card.flags.duplicate()
	s.used_effects        = card.used_effects.duplicate()
	s.used_effects_duel   = card.used_effects_duel.duplicate()

	s.summoned_on_turn        = card.summoned_on_turn
	s.has_attacked            = card.has_attacked
	s.was_special_summoned    = card.was_special_summoned
	s.special_summon_method   = card.special_summon_method

	s.attached_card_ids = card.attached_cards.map(func(c: CardInstance) -> int: return c.instance_id)
	s.attached_to_id    = card.attached_to.instance_id if card.attached_to != null else -1

	return s

# ─── Restore ──────────────────────────────────────────────────────────────────

## Writes every captured field back onto `card` in place.
## `zone_lookup` resolves current_zone_id → Zone (pass ZoneManager.get_zone
## bound, or the dictionary directly).
## `card_lookup` resolves instance_id → CardInstance for attachments
## (pass BoardSnapshot's id→card map — see BoardSnapshot.gd).
func restore_onto(card: CardInstance, zone_lookup: Callable, card_lookup: Callable) -> void:
	card.controller   = controller
	card.current_zone = zone_lookup.call(current_zone_id) if current_zone_id != &"" else null
	card.slot_index   = slot_index
	card.face_state   = face_state
	card.position     = position

	card._atk_modifiers   = atk_modifiers.duplicate()
	card._def_modifiers   = def_modifiers.duplicate()
	card._level_modifiers = level_modifiers.duplicate()

	card.counters          = counters.duplicate()
	card.flags             = flags.duplicate()
	card.used_effects      = used_effects.duplicate()
	card.used_effects_duel = used_effects_duel.duplicate()

	card.summoned_on_turn      = summoned_on_turn
	card.has_attacked          = has_attacked
	card.was_special_summoned = was_special_summoned
	card.special_summon_method = special_summon_method

	var restored_attached: Array[CardInstance] = []
	for id in attached_card_ids:
		var c: CardInstance = card_lookup.call(id)
		if c != null:
			restored_attached.append(c)
	card.attached_cards = restored_attached
	card.attached_to    = card_lookup.call(attached_to_id) if attached_to_id != -1 else null
