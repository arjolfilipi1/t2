## AnimationQueue.gd
## Serializes all board animations so they never overlap.
##
## WHY THIS EXISTS:
##   Domain signals (card_moved, chain_link_pushed, etc.) fire instantly and
##   synchronously — the moment ZoneManager moves a card, the signal fires,
##   regardless of whether the previous animation has finished playing.
##   Without a queue, an attack animation and an effect resolution animation
##   would visually stack on top of each other and the player couldn't tell
##   what happened.
##
##   This queue guarantees: enqueue(anim_a); enqueue(anim_b) always plays
##   anim_a to completion BEFORE anim_b starts, regardless of how close
##   together the two underlying domain events fired.
##
## USAGE:
##   var queue := AnimationQueue.new()
##   add_child(queue)
##   queue.enqueue(func(): return card_view.animate_move_to(pos))
##
##   The Callable passed to enqueue() MUST return a Signal (typically from
##   a helper like CardView.animate_move_to() which now returns "finished").
##   AnimationQueue awaits that signal before starting the next item.
##
## PARALLEL GROUPS:
##   Some animations should play together (e.g. two cards destroyed in the
##   same battle). Use enqueue_parallel() with an array of Callables — the
##   queue waits for ALL of them to finish before moving to the next item.
class_name AnimationQueue
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the queue transitions from empty to having work (UI can show
## a "resolving..." indicator, disable input, etc.)
signal queue_started()

## Emitted when the queue drains back to empty. UI can re-enable input here.
signal queue_finished()

## Emitted after each individual queued item finishes (for debug/HUD step-through).
signal item_finished(label: String)

# ─── Internal State ───────────────────────────────────────────────────────────

## Each entry is a Dictionary: { "callables": Array[Callable], "label": String }
## "callables" has >1 entry only for parallel groups.
var _queue: Array[Dictionary] = []

## True while an item is actively playing — prevents re-entrant _process_next calls.
var _is_playing: bool = false

# ─── Public API ───────────────────────────────────────────────────────────────

## Enqueue a single animation. `producer` must return a Signal (e.g. a Tween's
## "finished" signal, or a custom signal emitted when the animation completes).
func enqueue(producer: Callable, label: String = "") -> void:
	print("label: ",label)
	_queue.append({ "callables": [producer], "label": label })
	_maybe_start()

## Enqueue several animations that should all play simultaneously.
## The queue waits for every one of them to finish before continuing.
func enqueue_parallel(producers: Array[Callable], label: String = "") -> void:
	print(label)
	if producers.is_empty():
		return
	_queue.append({ "callables": producers, "label": label })
	_maybe_start()

## Enqueue a plain callback with no animation — useful for inserting game-logic
## side effects (e.g. "now apply LP damage") at an exact point in the sequence
## without needing a visual animation. Resolves immediately.
func enqueue_callback(action: Callable, label: String = "") -> void:
	enqueue(func() -> Signal:
		action.call()
		return _instant_signal()
	, label)

## True if anything is currently queued or playing.
func is_busy() -> bool:
	return _is_playing or not _queue.is_empty()

## Clears all pending items immediately. Does NOT stop an animation already
## in flight — only prevents anything queued after it from playing.
## Use sparingly (e.g. on game restart).
func clear() -> void:
	_queue.clear()

# ─── Internal Processing ──────────────────────────────────────────────────────

func _maybe_start() -> void:
	if _is_playing:
		return
	if _queue.is_empty():
		return
	
	_is_playing = true
	queue_started.emit()
	_process_next()

func _process_next() -> void:
	print("process next",len(_queue))
	if _queue.is_empty():
		print("play next but empty")
		_is_playing = false
		queue_finished.emit()
		return

	var item: Dictionary       = _queue.pop_front()
	var producers: Array       = item["callables"]
	var label: String          = item.get("label", "")
	print("anim queue",label,",queue:",len(_queue))
	if producers.size() == 1:
		var sig: Signal = producers[0].call()
		await sig
	else:
		var signals: Array[Signal] = []
		for p in producers:
			signals.append(p.call())
		for s in signals:
			await s
	
	item_finished.emit(label)
	_process_next()

## Returns an already-fired signal for synchronous callbacks (enqueue_callback).
## A freshly created SignalHelper node emits immediately on the next frame,
## which `await` can still correctly wait on.
func _instant_signal() -> Signal:
	var helper := _InstantSignalHelper.new()
	add_child(helper)
	helper.fire()
	return helper.done

# ─── Debug ────────────────────────────────────────────────────────────────────

func debug_queue_state() -> String:
	return "AnimationQueue(playing=%s, pending=%d)" % [_is_playing, _queue.size()]


# ──────────────────────────────────────────────────────────────────────────────
# Inner helper: fires a signal one frame later so `await` always works
# even for purely synchronous callbacks.
# ──────────────────────────────────────────────────────────────────────────────

class _InstantSignalHelper extends Node:
	signal done()

	func fire() -> void:
		call_deferred("_emit_and_free")

	func _emit_and_free() -> void:
		done.emit()
		queue_free()
