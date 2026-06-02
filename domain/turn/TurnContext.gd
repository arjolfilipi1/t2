## TurnContext.gd
## Lightweight snapshot of turn state.
## Passed into RuleEngine alongside ZoneManager so every check is
## stateless and testable without needing a running TurnManager node.
##
## TurnManager creates and owns one of these each turn,
## updating it as phases advance. RuleEngine reads it read-only.
class_name TurnContext
extends RefCounted

# ─── Phase ────────────────────────────────────────────────────────────────────

enum Phase {
	DRAW,
	STANDBY,
	MAIN_1,
	BATTLE_START,
	BATTLE_STEP,
	DAMAGE_STEP,
	BATTLE_END,
	MAIN_2,
	END,
}

## Current phase.
var phase: Phase = Phase.MAIN_1

## Turn number (increments each time the turn player changes).
var turn_number: int = 1

## The player whose turn it currently is.
var turn_player: Player = null

## The player who does NOT currently have the turn.
var non_turn_player: Player = null

## The player who currently holds priority on the chain.
var priority_holder: Player = null

## True if the effect chain is currently open (built or resolving).
var chain_open: bool = false

# ─── Phase Helpers ────────────────────────────────────────────────────────────

func is_main_phase() -> bool:
	return phase in [Phase.MAIN_1, Phase.MAIN_2]

func is_battle_phase() -> bool:
	return phase in [Phase.BATTLE_START, Phase.BATTLE_STEP, Phase.DAMAGE_STEP, Phase.BATTLE_END]

func is_damage_step() -> bool:
	return phase == Phase.DAMAGE_STEP

func phase_name() -> String:
	return Phase.keys()[phase]

# ─── Factory ──────────────────────────────────────────────────────────────────

static func make(
	current_phase: Phase,
	turn: int,
	active: Player,
	non_active: Player,
	priority: Player,
	chain_is_open: bool = false
) -> TurnContext:
	var ctx                := TurnContext.new()
	ctx.phase              = current_phase
	ctx.turn_number        = turn
	ctx.turn_player        = active
	ctx.non_turn_player    = non_active
	ctx.priority_holder    = priority
	ctx.chain_open         = chain_is_open
	return ctx

## Minimal context for testing — Main Phase 1, no chain.
static func for_test(p1: Player, p2: Player, turn: int = 1) -> TurnContext:
	return make(Phase.MAIN_1, turn, p1, p2, p1, false)

func _to_string() -> String:
	return "TurnContext(phase=%s, turn=%d, active=%s)" % [
		phase_name(), turn_number,
		turn_player.display_name if turn_player else "none"
	]
