## BoardSnapshot.gd
## A full, point-in-time copy of everything undo needs to roll back to.
##
## DESIGN: restoring a snapshot never creates new CardInstance/Player/Zone
## objects — it writes captured values back onto the SAME live objects.
## This matters because every other system (BoardView's _card_views
## dictionary keyed by instance_id, CardView nodes, AIController refs,
## etc.) holds references to these exact objects. If restore created new
## ones, every one of those references would silently go stale.
##
## WHAT IS CAPTURED:
##   - Every CardInstance currently known to the game (via CardSnapshot)
##   - Every Zone's card order/slots (via the zone's own _cards array)
##   - Every Player's LP, normal-summon count, flags
##   - TurnManager's turn number, active player index, attacker/defender,
##     attacked-this-turn list, game-over flag
##   - EffectStack's once-per-turn usage tracking
##
## WHAT IS NOT CAPTURED (deliberately):
##   - The chain itself (links, pending triggers) — undo is only offered
##     when EffectStack.is_idle(), so the chain is always empty at the
##     moment a snapshot is taken or restored. If you later want to undo
##     mid-chain, this needs to change.
##   - CardDefinition / static deck composition — these never mutate.
class_name BoardSnapshot
extends RefCounted

# ─── Captured Data ─────────────────────────────────────────────────────────────

var card_snapshots: Dictionary   ## int (instance_id) → CardSnapshot
var zone_orders:     Dictionary   ## StringName (zone_id) → Array of instance_id (-1 = empty slot)

var player_lp:             Dictionary   ## Player → int
var player_normal_summons: Dictionary   ## Player → int
var player_flags:           Dictionary   ## Player → Dictionary (shallow copy)

var turn_number:            int
var active_player_index:    int
var game_over:                bool
var current_attacker_id:     int   ## -1 = none
var current_defender_id:     int   ## -1 = none
var attacked_this_turn_ids:  Array[int]
var turn_context_phase:      TurnContext.Phase

var effect_stack_used: Dictionary   ## copy of EffectStack.player_used_effects

## Label shown in undo history UI, e.g. "Normal Summon Dark Magician"
var label: String = ""

# ─── Capture ──────────────────────────────────────────────────────────────────

static func capture(
	zm:           ZoneManager,
	tm:           TurnManager,
	stack:        EffectStack,
	players:      Array[Player],
	action_label: String = ""
) -> BoardSnapshot:
	var snap := BoardSnapshot.new()
	snap.label = action_label

	# ── Cards ────────────────────────────────────────────────────────────────
	# One CardSnapshot per card currently tracked anywhere in ZoneManager.
	snap.card_snapshots = {}
	for zone in zm._zones.values():
		for card in zone.get_cards():
			snap.card_snapshots[card.instance_id] = CardSnapshot.capture(card)

	# ── Zones (order/slots, stored as instance_id arrays, not refs) ──────────
	snap.zone_orders = {}
	for zone_id in zm._zones.keys():
		var zone: Zone = zm._zones[zone_id]
		var ids: Array = []
		for c in zone._cards:
			ids.append(c.instance_id if c != null else -1)
		snap.zone_orders[zone_id] = ids

	# ── Players ──────────────────────────────────────────────────────────────
	snap.player_lp             = {}
	snap.player_normal_summons = {}
	snap.player_flags           = {}
	for p in players:
		snap.player_lp[p]             = p.life_points
		snap.player_normal_summons[p] = p.normal_summons_remaining
		snap.player_flags[p]          = p.flags.duplicate()

	# ── Turn state ───────────────────────────────────────────────────────────
	snap.turn_number           = tm._turn_number
	snap.active_player_index   = tm._active_index
	snap.game_over              = tm._game_over
	snap.current_attacker_id   = tm._current_attacker.instance_id if tm._current_attacker != null else -1
	snap.current_defender_id   = tm._current_defender.instance_id if tm._current_defender != null else -1
	snap.attacked_this_turn_ids = []
	for c in tm._attacked_this_turn:
		snap.attacked_this_turn_ids.append(c.instance_id)
	snap.turn_context_phase = tm.context.phase if tm.context != null else TurnContext.Phase.MAIN_1

	# ── Effect stack once-per-turn tracking ──────────────────────────────────
	snap.effect_stack_used = _deep_copy_dict(stack.player_used_effects)

	return snap

static func _deep_copy_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v = d[k]
		out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out

# ─── Restore ──────────────────────────────────────────────────────────────────

## Writes this snapshot's state back onto the live ZoneManager/TurnManager/
## EffectStack/Players. `card_lookup` maps instance_id → live CardInstance —
## build it once from the current ZoneManager before calling restore
## (UndoManager does this for you).
func restore(
	zm:          ZoneManager,
	tm:          TurnManager,
	stack:       EffectStack,
	players:     Array[Player],
	card_lookup: Dictionary   ## int → CardInstance
) -> void:
	var zone_lookup_fn := func(zone_id: StringName) -> Zone: return zm.get_zone(zone_id)
	var card_by_id_fn  := func(id: int) -> CardInstance: return card_lookup.get(id, null)

	# ── Restore each card's own fields first (zone refs, flags, etc.) ────────
	for instance_id in card_snapshots.keys():
		var card: CardInstance = card_lookup.get(instance_id, null)
		if card == null:
			push_warning("BoardSnapshot.restore: card id %d no longer exists — skipping" % instance_id)
			continue
		var cs: CardSnapshot = card_snapshots[instance_id]
		cs.restore_onto(card, zone_lookup_fn, card_by_id_fn)

	# ── Restore zone order/slots and rebuild ZoneManager's location index ───
	zm._card_location.clear()
	for zone_id in zone_orders.keys():
		var zone: Zone = zm.get_zone(zone_id)
		if zone == null:
			continue
		var id_array: Array = zone_orders[zone_id]
		var restored: Array = []
		for id in id_array:
			if id == -1:
				restored.append(null)   ## empty slot
			else:
				var card: CardInstance = card_lookup.get(id, null)
				restored.append(card)
				if card != null:
					zm._card_location[id] = zone
		zone._cards = restored

	# ── Restore players ──────────────────────────────────────────────────────
	for p in players:
		if player_lp.has(p):
			p.life_points = player_lp[p]
		if player_normal_summons.has(p):
			p.normal_summons_remaining = player_normal_summons[p]
		if player_flags.has(p):
			p.flags = player_flags[p].duplicate()

	# ── Restore turn state ───────────────────────────────────────────────────
	tm._turn_number       = turn_number
	tm._active_index      = active_player_index
	tm._game_over          = game_over
	tm._current_attacker  = card_lookup.get(current_attacker_id, null) if current_attacker_id != -1 else null
	tm._current_defender  = card_lookup.get(current_defender_id, null) if current_defender_id != -1 else null

	tm._attacked_this_turn = []
	for id in attacked_this_turn_ids:
		var c: CardInstance = card_lookup.get(id, null)
		if c != null:
			tm._attacked_this_turn.append(c)

	## Rebuild context to reflect the restored turn/active-player state.
	## This mirrors what TurnManager._rebuild_context() does internally —
	## called here directly since restore happens outside the normal
	## phase-transition flow.
	tm.context = TurnContext.make(
		turn_context_phase,
		tm._turn_number,
		tm._players[tm._active_index],
		tm._players[(tm._active_index + 1) % tm._players.size()],
		stack.priority_holder if stack.priority_holder != null else tm._players[tm._active_index],
		not stack.is_idle()
	)

	# ── Restore effect stack tracking ────────────────────────────────────────
	stack.player_used_effects = _deep_copy_dict(effect_stack_used)
