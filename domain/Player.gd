## Player.gd
## Lightweight player model. Holds identity, life points, and turn state.
## In production this would also hold a reference to the PlayerController
## (HumanController or AIController). Here it's a plain data object.
class_name Player
extends RefCounted

# ─── Signals ──────────────────────────────────────────────────────────────────

signal life_points_changed(player: Player, old_lp: int, new_lp: int)
signal hand_size_changed(player: Player, new_size: int)

# ─── Identity ─────────────────────────────────────────────────────────────────

var player_id:    int    = 0
var display_name: String = ""
var is_human  := false
# ─── Game State ───────────────────────────────────────────────────────────────

var life_points: int = 8000

## Normal summons remaining this turn (usually 1, some effects grant more).
var normal_summons_remaining: int = 1

## Flags that affect what the player can or cannot do.
## e.g.  { &"cannot_draw": true, &"cannot_normal_summon": true }
var flags: Dictionary = {}

# ─── LP Management ────────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	var old := life_points
	life_points = max(0, life_points - amount)
	life_points_changed.emit(self, old, life_points)

func gain_lp(amount: int) -> void:
	var old := life_points
	life_points += amount
	life_points_changed.emit(self, old, life_points)

func is_alive() -> bool:
	return life_points > 0

# ─── Turn Housekeeping ────────────────────────────────────────────────────────

func reset_for_new_turn() -> void:
	normal_summons_remaining = 1

# ─── Flag Helpers ─────────────────────────────────────────────────────────────

func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value

func has_flag(flag: StringName) -> bool:
	return flags.get(flag, false) == true

func clear_flag(flag: StringName) -> void:
	flags.erase(flag)

# ─── Factory ──────────────────────────────────────────────────────────────────

static func make(id: int, name: String = "") -> Player:
	var p          := Player.new()
	p.player_id    = id
	p.display_name = name if name != "" else "Player %d" % id
	return p

func _to_string() -> String:
	return "Player(%d, LP=%d)" % [player_id, life_points]
