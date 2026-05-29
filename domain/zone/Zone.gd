## Zone.gd
## Base class for all card zones.
## All mutations go through ZoneManager — zones do not move cards themselves.
## Zones emit signals; ZoneManager listens and re-emits board-level signals.
class_name Zone
extends RefCounted

# ─── Enums ────────────────────────────────────────────────────────────────────

enum ZoneType {
	MAIN_MONSTER,   ## 5 indexed slots on main field
	MAIN_SPELL,     ## 5 indexed spell/trap slots
	EXTRA_MONSTER,  ## 3 Extra Monster Zones (shared, one per side + center)
	FIELD_SPELL,    ## 1 slot, Field Spell Zone
	HAND,           ## Private; no slot index
	DECK,           ## Ordered (top = index 0); private
	EXTRA_DECK,     ## Ordered; private
	GRAVEYARD,      ## Ordered (most recent = top); public
	BANISHED,       ## Ordered; public (face-up) or private (face-down)
	LIMBO,          ## Transient state during moves; never rendered
}

## Which zones are considered "the field" (on-field presence matters for effects)
const FIELD_ZONE_TYPES := [
	ZoneType.MAIN_MONSTER,
	ZoneType.EXTRA_MONSTER,
	ZoneType.MAIN_SPELL,
	ZoneType.FIELD_SPELL,
]

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after a card is added to this zone.
signal card_added(card: CardInstance, slot: int)

## Emitted after a card is removed from this zone.
signal card_removed(card: CardInstance, slot: int)

# ─── Identity ─────────────────────────────────────────────────────────────────

var zone_id:   StringName   ## e.g. &"p1_main_monster", &"p2_graveyard"
var zone_type: ZoneType
var owner:     Player        ## Which player this zone belongs to

# ─── Capacity ─────────────────────────────────────────────────────────────────

## -1 = unlimited (hand, GY, banished).
## Slotted zones (main field, extra monster) have fixed capacity.
var capacity: int = -1

## If true, each card occupies a numbered slot. Empty slots are null.
## If false, cards are stored as a simple ordered array.
var is_slotted: bool = false

# ─── Card Storage ─────────────────────────────────────────────────────────────

## For slotted zones: fixed-size array, null = empty slot.
## For unslotted zones: ordered list, newest at end (GY) or front (deck top = 0).
var _cards: Array = []   ## Array[CardInstance?] for slotted, Array[CardInstance] for unslotted

# ─── Initialization ───────────────────────────────────────────────────────────

func _init(id: StringName, type: ZoneType, zone_owner: Player, cap: int = -1, slotted: bool = false) -> void:
	zone_id   = id
	zone_type = type
	owner     = zone_owner
	capacity  = cap
	is_slotted = slotted

	if slotted and cap > 0:
		_cards.resize(cap)
		_cards.fill(null)

# ─── Read API ─────────────────────────────────────────────────────────────────

## All cards currently in this zone (no nulls).
func get_cards() -> Array:
	if is_slotted:
		var result: Array[CardInstance] = []
		for c in _cards:
			if c != null:
				result.append(c)
		return result
	return _cards.duplicate()  ## typed Array[CardInstance] cast below

func get_card_at(slot: int) -> CardInstance:
	assert(is_slotted, "get_card_at() called on unslotted zone '%s'" % zone_id)
	assert(slot >= 0 and slot < _cards.size(), "Slot %d out of range for zone '%s'" % [slot, zone_id])
	return _cards[slot]

func count() -> int:
	if is_slotted:
		var n := 0
		for c in _cards:
			if c != null:
				n += 1
		return n
	return _cards.size()

func is_empty() -> bool:
	return count() == 0

func is_full() -> bool:
	if capacity == -1:
		return false
	return count() >= capacity

func contains(card: CardInstance) -> bool:
	if is_slotted:
		return _cards.has(card)
	return _cards.has(card)

## For deck: top card (index 0).
func peek_top() -> CardInstance:
	if _cards.is_empty():
		return null
	return _cards[0]

## Returns the slot index of the given card, or -1 if not found.
func slot_of(card: CardInstance) -> int:
	return _cards.find(card)

## First empty slot index, or -1 if none.
func first_empty_slot() -> int:
	assert(is_slotted, "first_empty_slot() on unslotted zone")
	for i in _cards.size():
		if _cards[i] == null:
			return i
	return -1

func empty_slot_count() -> int:
	if not is_slotted:
		return 0
	var n := 0
	for c in _cards:
		if c == null:
			n += 1
	return n

# ─── Write API (called only by ZoneManager) ───────────────────────────────────

## Place a card into a specific slot (slotted zones only).
func _place_at_slot(card: CardInstance, slot: int) -> void:
	assert(is_slotted, "_place_at_slot() on unslotted zone")
	assert(_cards[slot] == null, "Slot %d in '%s' already occupied" % [slot, zone_id])
	_cards[slot] = card
	card.slot_index = slot
	card.current_zone = self
	card_added.emit(card, slot)

## Place a card in the first available slot (slotted zones only).
func _place_in_first_slot(card: CardInstance) -> int:
	var slot := first_empty_slot()
	assert(slot != -1, "Zone '%s' is full" % zone_id)
	_place_at_slot(card, slot)
	return slot

## Append a card to the end (unslotted zones).
func _append(card: CardInstance) -> void:
	assert(not is_slotted, "_append() on slotted zone")
	_cards.append(card)
	card.slot_index = -1
	card.current_zone = self
	card_added.emit(card, -1)

## Prepend a card to position 0 (used for returning to top of deck).
func _prepend(card: CardInstance) -> void:
	assert(not is_slotted)
	_cards.insert(0, card)
	card.slot_index = -1
	card.current_zone = self
	card_added.emit(card, 0)

## Insert card at a specific index in an unslotted zone.
func _insert(card: CardInstance, index: int) -> void:
	assert(not is_slotted)
	_cards.insert(index, card)
	card.slot_index = -1
	card.current_zone = self
	card_added.emit(card, index)

## Remove a card from a slotted zone, clearing its slot.
func _remove_from_slot(card: CardInstance) -> int:
	assert(is_slotted)
	var slot := _cards.find(card)
	assert(slot != -1, "Card not found in slotted zone '%s'" % zone_id)
	_cards[slot] = null
	card.slot_index = -1
	card_removed.emit(card, slot)
	return slot

## Remove a card from an unslotted zone.
func _remove(card: CardInstance) -> void:
	assert(not is_slotted)
	var idx := _cards.find(card)
	assert(idx != -1, "Card not found in zone '%s'" % zone_id)
	_cards.remove_at(idx)
	card.slot_index = -1
	card_removed.emit(card, idx)

## Shuffle the zone (deck only).
func _shuffle() -> void:
	assert(not is_slotted, "Cannot shuffle a slotted zone")
	_cards.shuffle()

# ─── Helpers ──────────────────────────────────────────────────────────────────

func is_field_zone() -> bool:
	return zone_type in FIELD_ZONE_TYPES

func _to_string() -> String:
	return "Zone(%s [%s] %d/%s)" % [
		zone_id,
		ZoneType.keys()[zone_type],
		count(),
		str(capacity) if capacity != -1 else "∞"
	]
