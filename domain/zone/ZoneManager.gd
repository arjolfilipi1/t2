## ZoneManager.gd
## The ONLY system allowed to move cards between zones.
## All movement goes through move() — never mutate Zone arrays directly.
##
## Responsibilities:
##   1. Own and vend all zones for both players.
##   2. Execute card moves atomically (remove → LIMBO → add).
##   3. Fire pre/post signals so EffectStack can open trigger windows.
##   4. Maintain inverse index: instance_id → Zone for O(1) lookup.
##   5. Enforce zone capacity and placement rules.
class_name ZoneManager
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted before a card moves. EffectStack uses this to check "when X leaves field" triggers.
signal card_will_move(card: CardInstance, from_zone: Zone, to_zone: Zone, reason: MoveReason)

## Emitted after a card has fully moved and all internal state is updated.
## This is the primary signal for UI updates and trigger evaluation.
signal card_moved(card: CardInstance, from_zone: Zone, to_zone: Zone, reason: MoveReason)

## Emitted when the deck is shuffled.
signal deck_shuffled(player: Player)

## Emitted when a zone's occupancy changes (for UI slot updates).
signal zone_changed(zone: Zone)

# ─── Move Reason ──────────────────────────────────────────────────────────────

enum MoveReason {
	DRAW,           ## Normal draw
	NORMAL_SUMMON,
	SPECIAL_SUMMON,
	FLIP_SUMMON,
	SET,            ## Placing a card face-down
	EFFECT_SEND,    ## "Send to GY" by effect
	EFFECT_BANISH,  ## Banished by effect
	EFFECT_RETURN,  ## Returned to hand/deck by effect
	BATTLE_DESTROY, ## Destroyed in battle
	EFFECT_DESTROY, ## Destroyed by effect
	TRIBUTE,        ## Tributed for summon
	MATERIAL,       ## Used as Fusion/Synchro/Xyz material
	RULE,           ## Rules-based removal (e.g. field limit)
	GAME_SETUP,     ## Initial deck/hand placement
	RESOLVE,
}

## Reasons that count as "destroyed"
const DESTROY_REASONS := [MoveReason.BATTLE_DESTROY, MoveReason.EFFECT_DESTROY]

## Reasons that count as "sent to GY" (trigger for GY effects)
const SENT_TO_GY_REASONS := [
	MoveReason.DRAW,
	MoveReason.EFFECT_SEND,
	MoveReason.BATTLE_DESTROY,
	MoveReason.EFFECT_DESTROY,
	MoveReason.TRIBUTE,
	MoveReason.MATERIAL,
]

# ─── Zone References ──────────────────────────────────────────────────────────

## All zones, keyed by zone_id.
var _zones: Dictionary = {}   ## StringName → Zone

## Quick player-scoped lookups.
var _player_zones: Dictionary = {}   ## Player → Dictionary[ZoneType → Zone or Array[Zone]]

## Inverse index: instance_id → Zone. Updated on every move.
var _card_location: Dictionary = {}  ## int → Zone

## The limbo zone — transient during moves, never valid outside move().
var _limbo: Zone

# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(players: Array[Player]) -> void:
	_zones.clear()
	_player_zones.clear()
	_card_location.clear()

	_limbo = Zone.new(&"limbo", Zone.ZoneType.LIMBO, null, -1, false)

	for player in players:
		_build_player_zones(player)

func _build_player_zones(player: Player) -> void:
	var prefix := "p%d" % player.player_id
	var pz: Dictionary = {}

	# Slotted field zones
	pz[Zone.ZoneType.MAIN_MONSTER]  = _make_zone("%s_main_monster"  % prefix, Zone.ZoneType.MAIN_MONSTER,  player, 5,  true)
	pz[Zone.ZoneType.MAIN_SPELL]    = _make_zone("%s_main_spell"    % prefix, Zone.ZoneType.MAIN_SPELL,    player, 5,  true)
	pz[Zone.ZoneType.EXTRA_MONSTER] = _make_zone("%s_extra_monster" % prefix, Zone.ZoneType.EXTRA_MONSTER, player, 3,  true)
	pz[Zone.ZoneType.FIELD_SPELL]   = _make_zone("%s_field_spell"   % prefix, Zone.ZoneType.FIELD_SPELL,   player, 1,  true)

	# Unslotted zones
	pz[Zone.ZoneType.HAND]       = _make_zone("%s_hand"        % prefix, Zone.ZoneType.HAND,       player)
	pz[Zone.ZoneType.DECK]       = _make_zone("%s_deck"        % prefix, Zone.ZoneType.DECK,       player)
	pz[Zone.ZoneType.EXTRA_DECK] = _make_zone("%s_extra_deck"  % prefix, Zone.ZoneType.EXTRA_DECK, player)
	pz[Zone.ZoneType.GRAVEYARD]  = _make_zone("%s_graveyard"   % prefix, Zone.ZoneType.GRAVEYARD,  player)
	pz[Zone.ZoneType.BANISHED]   = _make_zone("%s_banished"    % prefix, Zone.ZoneType.BANISHED,   player)

	_player_zones[player] = pz

func _make_zone(
	id: String,
	type: Zone.ZoneType,
	owner: Player,
	cap: int = -1,
	slotted: bool = false
) -> Zone:
	var z := Zone.new(StringName(id), type, owner, cap, slotted)
	_zones[z.zone_id] = z
	return z

# ─── Zone Access API ──────────────────────────────────────────────────────────

func get_zone(zone_id: StringName) -> Zone:
	return _zones.get(zone_id, null)

func get_player_zone(player: Player, type: Zone.ZoneType) -> Zone:
	return _player_zones[player][type]

func hand_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.HAND)

func deck_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.DECK)

func extra_deck_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.EXTRA_DECK)

func graveyard_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.GRAVEYARD)

func banished_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.BANISHED)

func monster_zone_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.MAIN_MONSTER)

func spell_zone_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.MAIN_SPELL)

func field_spell_zone_of(player: Player) -> Zone:
	return get_player_zone(player, Zone.ZoneType.FIELD_SPELL)

func all_zones_of(player: Player) -> Array[Zone]:
	var result: Array[Zone] = []
	for zone in _player_zones[player].values():
		result.append(zone)
	return result

func all_field_zones() -> Array[Zone]:
	var result: Array[Zone] = []
	for zone in _zones.values():
		if zone.is_field_zone():
			result.append(zone)
	return result

# ─── Card Location Lookup ─────────────────────────────────────────────────────

## O(1) zone lookup by instance_id.
func locate(card: CardInstance) -> Zone:
	return _card_location.get(card.instance_id, null)

func is_on_field(card: CardInstance) -> bool:
	var z := locate(card)
	return z != null and z.is_field_zone()

func is_in_zone_type(card: CardInstance, type: Zone.ZoneType) -> bool:
	var z := locate(card)
	return z != null and z.zone_type == type

# ─── Core Move API ────────────────────────────────────────────────────────────

## Move a card to a specific slot in a slotted zone.
func move_to_slot(
	card: CardInstance,
	to_zone: Zone,
	slot: int,
	reason: MoveReason = MoveReason.RULE
) -> void:
	assert(to_zone.is_slotted, "move_to_slot() called on unslotted zone")
	assert(slot >= 0 and slot < to_zone.capacity, "Invalid slot %d" % slot)
	assert(to_zone.get_card_at(slot) == null, "Slot %d already occupied in %s" % [slot, to_zone.zone_id])
	_execute_move(card, to_zone, reason, slot)

## Move a card to the first available slot in a slotted zone.
func move_to_first_slot(
	card: CardInstance,
	to_zone: Zone,
	reason: MoveReason = MoveReason.RULE
) -> int:
	assert(to_zone.is_slotted, "move_to_first_slot() called on unslotted zone")
	assert(not to_zone.is_full(), "Zone '%s' is full" % to_zone.zone_id)
	var slot := to_zone.first_empty_slot()
	_execute_move(card, to_zone, reason, slot)
	return slot

## Move a card to an unslotted zone (hand, GY, banished, deck-bottom, etc.)
func move(
	card: CardInstance,
	to_zone: Zone,
	reason: MoveReason = MoveReason.RULE
) -> void:
	assert(not to_zone.is_slotted, "Use move_to_slot() for slotted zones")
	_execute_move(card, to_zone, reason, -1)

## Move a card to the top of the deck (index 0).
func move_to_deck_top(card: CardInstance, player: Player, reason: MoveReason = MoveReason.EFFECT_RETURN) -> void:
	var deck := deck_of(player)
	_execute_move(card, deck, reason, 0, true)  ## prepend = true

## Move a card to a specific deck position (0 = top).
func move_to_deck_position(card: CardInstance, player: Player, index: int, reason: MoveReason = MoveReason.EFFECT_RETURN) -> void:
	var deck := deck_of(player)
	_execute_move(card, deck, reason, index, false, true)  ## insert at index

# ─── Batch Moves ──────────────────────────────────────────────────────────────

## Move multiple cards simultaneously (e.g. mass destruction).
## All card_will_move signals fire first, then all card_moved signals.
## This ensures trigger windows see the correct simultaneous state.
func move_batch(
	cards: Array[CardInstance],
	to_zone: Zone,
	reason: MoveReason
) -> void:
	var from_zones: Array[Zone] = []

	# Phase 1: emit will_move for all, move to LIMBO
	for card in cards:
		var from := locate(card)
		from_zones.append(from)
		card_will_move.emit(card, from, to_zone, reason)
		_remove_from_zone(card, from)
		_limbo._append(card)

	# Phase 2: move from LIMBO to destination, emit moved for all
	for i in cards.size():
		var card := cards[i]
		var from := from_zones[i]
		_limbo._remove(card)
		_place_in_zone(card, to_zone, -1)
		card_moved.emit(card, from, to_zone, reason)
		zone_changed.emit(to_zone)
		if from != null:
			zone_changed.emit(from)

# ─── Deck Operations ──────────────────────────────────────────────────────────

func shuffle_deck(player: Player) -> void:
	deck_of(player)._shuffle()
	deck_shuffled.emit(player)

## Load a list of CardInstances into the player's deck (bottom to top order).
func load_deck(cards: Array[CardInstance], player: Player) -> void:
	var deck := deck_of(player)
	for card in cards:
		deck._append(card)
		_card_location[card.instance_id] = deck

## Load extra deck cards.
func load_extra_deck(cards: Array[CardInstance], player: Player) -> void:
	var extra := extra_deck_of(player)
	for card in cards:
		extra._append(card)
		_card_location[card.instance_id] = extra

# ─── Query Helpers ────────────────────────────────────────────────────────────

## All monsters currently on the field for a player.
func monsters_on_field(player: Player) -> Array[CardInstance]:
	return monster_zone_of(player).get_cards()

## All spells/traps currently set or active for a player.
func spells_on_field(player: Player) -> Array[CardInstance]:
	return spell_zone_of(player).get_cards()

## All cards on the field for a player (monsters + spells + extra monster zone).
func all_cards_on_field(player: Player) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	result.append_array(monster_zone_of(player).get_cards())
	result.append_array(spell_zone_of(player).get_cards())
	result.append_array(get_player_zone(player, Zone.ZoneType.EXTRA_MONSTER).get_cards())
	var fs := field_spell_zone_of(player).get_cards()
	result.append_array(fs)
	return result

## Count of monsters on a player's field.
func monster_count(player: Player) -> int:
	return monster_zone_of(player).count()

## Count of spell/trap cards on a player's field.
func spell_count(player: Player) -> int:
	return spell_zone_of(player).count()

## True if the player's monster zone has at least one empty slot.
func has_open_monster_zone(player: Player) -> bool:
	return not monster_zone_of(player).is_full()

func has_open_spell_zone(player: Player) -> bool:
	return not spell_zone_of(player).is_full()

# ─── Internal Move Execution ──────────────────────────────────────────────────

func _execute_move(
	card: CardInstance,
	to_zone: Zone,
	reason: MoveReason,
	slot: int = -1,
	prepend: bool = false,
	insert_at: bool = false
) -> void:
	var from_zone := locate(card)

	# --- Pre-move signal (trigger window hook) ---
	card_will_move.emit(card, from_zone, to_zone, reason)

	# --- Remove from current zone ---
	_remove_from_zone(card, from_zone)

	# --- Temporarily in LIMBO (prevents double-trigger) ---
	_limbo._append(card)

	# --- Apply face state based on destination ---
	_apply_face_state(card, to_zone, reason)

	# --- Remove from LIMBO, add to destination ---
	_limbo._remove(card)
	_place_in_zone(card, to_zone, slot, prepend, insert_at)

	# --- Post-move signal ---
	card_moved.emit(card, from_zone, to_zone, reason)

	# --- Zone UI refresh ---
	zone_changed.emit(to_zone)
	if from_zone != null:
		zone_changed.emit(from_zone)
	
func _remove_from_zone(card: CardInstance, zone: Zone) -> void:
	if zone == null:
		return  ## Card had no prior zone (initial placement)
	if zone.is_slotted:
		zone._remove_from_slot(card)
	else:
		zone._remove(card)
	_card_location.erase(card.instance_id)

func _place_in_zone(
	card: CardInstance,
	zone: Zone,
	slot: int = -1,
	prepend: bool = false,
	insert_at: bool = false
) -> void:
	if zone.is_slotted:
		if slot == -1:
			zone._place_in_first_slot(card)
		else:
			zone._place_at_slot(card, slot)
	else:
		if prepend:
			zone._prepend(card)
		elif insert_at and slot >= 0:
			zone._insert(card, slot)
		else:
			zone._append(card)
	_card_location[card.instance_id] = zone

func _apply_face_state(card: CardInstance, to_zone: Zone, reason: MoveReason) -> void:
	match to_zone.zone_type:
		Zone.ZoneType.GRAVEYARD, Zone.ZoneType.BANISHED, Zone.ZoneType.HAND:
			card.face_state = CardInstance.FaceState.FACE_UP
		Zone.ZoneType.MAIN_MONSTER, Zone.ZoneType.MAIN_SPELL, Zone.ZoneType.EXTRA_MONSTER:
			if reason == MoveReason.SET:
				card.face_state = CardInstance.FaceState.FACE_DOWN
			elif reason in [MoveReason.NORMAL_SUMMON, MoveReason.SPECIAL_SUMMON, MoveReason.FLIP_SUMMON]:
				card.face_state = CardInstance.FaceState.FACE_UP
		Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK:
			card.face_state = CardInstance.FaceState.FACE_DOWN

# ─── Debug ────────────────────────────────────────────────────────────────────

func debug_print_state(player: Player) -> void:
	print("=== ZoneManager state for Player %d ===" % player.player_id)
	for zone in all_zones_of(player):
		print("  %s: %d card(s)" % [zone.zone_id, zone.count()])
		for card in zone.get_cards():
			print("    - %s" % card)
