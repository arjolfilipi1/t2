## UndoManager.gd
## Captures a BoardSnapshot before every GameAction executes, and restores
## a prior snapshot on undo()/redo().
##
## DESIGN: snapshot-based, not per-action inverse functions. A full copy of
## the board is taken before each action; undo simply restores the previous
## copy rather than trying to compute and apply the exact inverse of
## whatever the action did. This trades memory for correctness and
## simplicity — see the architecture discussion this was built from for why
## that tradeoff makes sense for a card game's state size.
##
## LIMITATIONS (intentional, matches BoardSnapshot's scope):
##   - Undo is only offered while EffectStack.is_idle(). You cannot undo
##     into the middle of an unresolved chain — the snapshot taken before
##     an action captures state with an empty chain, and restoring assumes
##     the chain is empty too.
##   - Animations are NOT rewound. Restoring a snapshot snaps the board
##     directly to the target state; BoardView's normal signal-driven
##     update path (ZoneManager.card_moved etc.) does NOT fire during a
##     restore, so the UI must be refreshed wholesale afterward — see
##     `snapshot_restored` signal below, which BoardView should use to
##     trigger a full re-render rather than relying on incremental signals.
##   - Redo is invalidated the moment a NEW action is submitted after an
##     undo — same convention as any standard undo/redo stack.
class_name UndoManager
extends RefCounted

# ─── Signals ──────────────────────────────────────────────────────────────────

## Fired after a snapshot has been restored (by undo or redo). The board
## data is already correct by the time this fires — listeners should do a
## full visual refresh, not assume any incremental ZoneManager signals
## will arrive for this change.
signal snapshot_restored(label: String)

## Fired whenever the undo/redo stack sizes change, so UI can enable/
## disable Undo/Redo buttons.
signal history_changed(can_undo: bool, can_redo: bool)

# ─── Dependencies ─────────────────────────────────────────────────────────────

var _zm:      ZoneManager  = null
var _tm:      TurnManager  = null
var _stack:   EffectStack  = null
var _players: Array[Player] = []

# ─── History ──────────────────────────────────────────────────────────────────

## Snapshots taken BEFORE each action executed. _undo_stack.back() is the
## state to restore to undo the most recently executed action.
var _undo_stack: Array[BoardSnapshot] = []

## Snapshots popped off _undo_stack by undo(), kept so redo() can restore
## forward again. Cleared whenever a new action is captured.
var _redo_stack: Array[BoardSnapshot] = []

## Hard cap so a very long game doesn't grow this unboundedly. Oldest
## entries are dropped silently once exceeded — undo that far back is an
## edge case not worth keeping unlimited memory for.
var max_history: int = 50

# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(zm: ZoneManager, tm: TurnManager, stack: EffectStack, players: Array[Player]) -> void:
	_zm      = zm
	_tm      = tm
	_stack   = stack
	_players = players

# ─── Capture (called by GameDirector before every action executes) ───────────

## Takes a snapshot of the CURRENT board state and pushes it as the undo
## point for whatever action is about to execute. Call this immediately
## before GameAction.execute() — i.e. capture the "before" state.
func capture_before_action(action_label: String) -> void:
	if not _stack.is_idle():
		## Refuse to capture mid-chain — see class doc LIMITATIONS.
		## GameDirector should simply not offer undo for actions submitted
		## while a chain is open; this guard exists so a stray call here
		## can't silently corrupt history with an inconsistent snapshot.
		push_warning("UndoManager: refused to capture snapshot — chain is not idle")
		return

	var snap := BoardSnapshot.capture(_zm, _tm, _stack, _players, action_label)
	_undo_stack.append(snap)
	if _undo_stack.size() > max_history:
		_undo_stack.pop_front()

	## Any action taken invalidates the ability to redo whatever was undone.
	_redo_stack.clear()

	_emit_history_changed()

# ─── Undo / Redo ──────────────────────────────────────────────────────────────

func can_undo() -> bool:
	return not _undo_stack.is_empty() and _stack.is_idle()

func can_redo() -> bool:
	return not _redo_stack.is_empty() and _stack.is_idle()

## Restores the board to the state it was in immediately before the most
## recently executed action. Returns true if an undo actually happened.
func undo() -> bool:
	if not can_undo():
		return false

	## Snapshot the CURRENT state first so redo() can come back to it.
	var current := BoardSnapshot.capture(_zm, _tm, _stack, _players, "")
	_redo_stack.append(current)

	var target: BoardSnapshot = _undo_stack.pop_back()
	_restore(target)

	_emit_history_changed()
	return true

## Re-applies the action that was most recently undone. Returns true if a
## redo actually happened.
func redo() -> bool:
	if not can_redo():
		return false

	## Snapshot the current (post-undo) state so a subsequent undo can
	## return to exactly here again.
	var current := BoardSnapshot.capture(_zm, _tm, _stack, _players, "")
	_undo_stack.append(current)

	var target: BoardSnapshot = _redo_stack.pop_back()
	_restore(target)

	_emit_history_changed()
	return true

## Clears all history. Call when starting a new game.
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_history_changed()

# ─── Internal Restore ─────────────────────────────────────────────────────────

func _restore(snap: BoardSnapshot) -> void:
	var card_lookup := _build_card_lookup()
	snap.restore(_zm, _tm, _stack, _players, card_lookup)
	snapshot_restored.emit(snap.label)

## Builds instance_id → CardInstance for every card object that currently
## exists anywhere in ZoneManager. Since restore never creates new
## CardInstance objects (see BoardSnapshot doc), cards are never deleted —
## only moved between zones — so scanning the live ZoneManager's current
## zones finds every card the snapshot could possibly reference, regardless
## of which zone each one happened to be in at snapshot time.
func _build_card_lookup() -> Dictionary:
	var lookup := {}
	for zone in _zm._zones.values():
		for card in zone._cards:
			if card != null:
				lookup[card.instance_id] = card
	return lookup

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _emit_history_changed() -> void:
	history_changed.emit(can_undo(), can_redo())

func undo_label() -> String:
	return _undo_stack.back().label if not _undo_stack.is_empty() else ""

func redo_label() -> String:
	return _redo_stack.back().label if not _redo_stack.is_empty() else ""
