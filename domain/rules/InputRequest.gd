## InputRequest.gd
## Describes a decision GameDirector is waiting on from a player.
## When GameDirector cannot proceed without a player choice (targeting,
## discard selection, trigger opt-in, search selection), it creates one
## of these and emits awaiting_input(request).
##
## The UI presents the choice. When the player decides, it calls
## GameDirector.resolve_input(result) which calls request.resolve(result).
class_name InputRequest
extends RefCounted

# ─── Request Types ────────────────────────────────────────────────────────────

enum RequestType {
	TARGET_SELECTION,    ## Pick N cards from a set of candidates
	DISCARD_SELECTION,   ## Pick cards to discard
	TRIBUTE_SELECTION,   ## Pick monsters to tribute
	TRIGGER_SELECTION,   ## Opt in/out of optional trigger effects
	SEARCH_SELECTION,    ## Pick a card from the deck to add to hand
	BANISH_SELECTION,    ## Pick cards to banish as cost
	POSITION_SELECTION,  ## Choose ATK or DEF for a summon
}

# ─── Fields ───────────────────────────────────────────────────────────────────

var type:        RequestType
var player:      Player          ## Who must decide
var prompt:      String          ## UI message ("Select 1 target")
var min_choices: int = 1
var max_choices: int = 1

## The pool of valid options. Type depends on RequestType:
##   TARGET/DISCARD/TRIBUTE/BANISH/SEARCH: Array[CardInstance]
##   TRIGGER: Array[PendingTrigger]
##   POSITION: Array[CardDefinition.Position]
var candidates: Array = []

## Called with the player's choice when resolve() is invoked.
## Signature: func(result: Variant) — type of result matches RequestType.
var _callback: Callable

# ─── Factories ────────────────────────────────────────────────────────────────

static func target_selection(
	selecting_player: Player,
	candidate_cards:  Array[CardInstance],
	count:            int,
	prompt_text:      String,
	callback:         Callable
) -> InputRequest:
	var r          := InputRequest.new()
	r.type         = RequestType.TARGET_SELECTION
	r.player       = selecting_player
	r.prompt       = prompt_text
	r.min_choices  = count
	r.max_choices  = count
	r.candidates   = candidate_cards
	r._callback    = callback
	return r

static func discard_selection(
	selecting_player: Player,
	hand_cards:       Array[CardInstance],
	count:            int,
	callback:         Callable
) -> InputRequest:
	var r          := InputRequest.new()
	r.type         = RequestType.DISCARD_SELECTION
	r.player       = selecting_player
	r.prompt       = "Discard %d card%s" % [count, "s" if count > 1 else ""]
	r.min_choices  = count
	r.max_choices  = count
	r.candidates   = hand_cards
	r._callback    = callback
	return r

static func tribute_selection(
	selecting_player: Player,
	field_monsters:   Array[CardInstance],
	count:            int,
	callback:         Callable
) -> InputRequest:
	var r          := InputRequest.new()
	r.type         = RequestType.TRIBUTE_SELECTION
	r.player       = selecting_player
	r.prompt       = "Select %d monster%s to tribute" % [count, "s" if count > 1 else ""]
	r.min_choices  = count
	r.max_choices  = count
	r.candidates   = field_monsters
	r._callback    = callback
	return r

static func trigger_selection(
	pending_triggers: Array,   ## Array[PendingTrigger]
	callback:         Callable
) -> InputRequest:
	var r          := InputRequest.new()
	r.type         = RequestType.TRIGGER_SELECTION
	r.prompt       = "Activate optional trigger effects?"
	r.min_choices  = 0
	r.max_choices  = pending_triggers.size()
	r.candidates   = pending_triggers
	r._callback    = callback
	return r

static func search_selection(
	selecting_player: Player,
	deck_cards:       Array[CardInstance],
	filter_desc:      String,
	callback:         Callable
) -> InputRequest:
	var r          := InputRequest.new()
	r.type         = RequestType.SEARCH_SELECTION
	r.player       = selecting_player
	r.prompt       = "Add 1 card to hand: %s" % filter_desc
	r.min_choices  = 1
	r.max_choices  = 1
	r.candidates   = deck_cards
	r._callback    = callback
	return r

# ─── Resolution ───────────────────────────────────────────────────────────────

## Called by GameDirector.resolve_input() with the player's answer.
## result type:
##   TARGET/DISCARD/TRIBUTE/BANISH/SEARCH: Array[CardInstance]
##   TRIGGER: Dictionary[PendingTrigger → bool]
##   POSITION: CardDefinition.Position
func resolve(result: Variant) -> void:
	if _callback.is_valid():
		_callback.call(result)
	else:
		push_error("InputRequest.resolve: callback is not valid")

func _to_string() -> String:
	return "InputRequest(%s, player=%s, candidates=%d)" % [
		RequestType.keys()[type],
		player.display_name if player else "none",
		candidates.size()
	]
