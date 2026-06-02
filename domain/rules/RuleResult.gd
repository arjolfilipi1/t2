## RuleResult.gd
## Returned by every RuleEngine query.
## Carries a validity flag, a machine-readable reason code, and a
## human-readable message for UI hints and debug output.
##
## Usage:
##   var result := RuleEngine.can_normal_summon(card, player, zm, turn)
##   if not result.valid:
##       tooltip.show_error(result.message)
class_name RuleResult
extends RefCounted

# ─── Reason Codes ─────────────────────────────────────────────────────────────
## Machine-readable — use these in game logic, not the message string.

enum Reason {
	OK,

	# Summon reasons
	NOT_A_MONSTER,
	NOT_IN_HAND,
	MONSTER_ZONE_FULL,
	NO_NORMAL_SUMMONS_LEFT,
	INSUFFICIENT_TRIBUTES,
	WRONG_SUMMON_METHOD,        ## e.g. trying to normal summon an extra deck monster
	SUMMONING_NEGATED,
	CANNOT_SPECIAL_SUMMON,      ## Flag set by an effect
	EXTRA_DECK_ZONE_FULL,
	MISSING_MATERIALS,

	# Attack reasons
	NOT_A_FIELD_MONSTER,
	ALREADY_ATTACKED,
	SUMMONING_SICKNESS,
	CANNOT_ATTACK,              ## Flag
	NO_VALID_ATTACK_TARGET,
	NOT_BATTLE_PHASE,
	CHAIN_OPEN,                 ## Cannot declare attack while chain is open
	DIRECT_ATTACK_BLOCKED,

	# Activation reasons
	NO_EFFECTS,
	EFFECT_NOT_FOUND,
	WRONG_TIMING,               ## Not the right phase
	SPELL_SPEED_TOO_LOW,
	COST_CANNOT_BE_PAID,
	CONDITIONS_NOT_MET,
	ONCE_PER_TURN_USED,
	ONCE_PER_DUEL_USED,
	NOT_YOUR_PRIORITY,
	CONTINUOUS_ALREADY_ACTIVE,
	NO_VALID_TARGET,            ## Targeting required but no legal targets

	# Set reasons
	NOT_A_SPELL_OR_TRAP,
	SPELL_ZONE_FULL,
	CANNOT_SET,

	# Battle position reasons
	ALREADY_IN_POSITION,
	CANNOT_CHANGE_POSITION,     ## Changed position this turn already
	NOT_ON_FIELD,

	# General
	WRONG_PHASE,
	NOT_YOUR_TURN,
	GAME_OVER,
}

# ─── Fields ───────────────────────────────────────────────────────────────────

var valid:   bool   = false
var reason:  Reason = Reason.OK
var message: String = ""

# ─── Factories ────────────────────────────────────────────────────────────────

static func ok() -> RuleResult:
	var r := RuleResult.new()
	r.valid   = true
	r.reason  = Reason.OK
	r.message = ""
	return r

static func fail(reason_code: Reason, msg: String = "") -> RuleResult:
	var r := RuleResult.new()
	r.valid   = false
	r.reason  = reason_code
	r.message = msg if msg != "" else Reason.keys()[reason_code].to_lower().replace("_", " ")
	return r

# ─── Helpers ──────────────────────────────────────────────────────────────────

func is_ok() -> bool:
	return valid

func _to_string() -> String:
	if valid:
		return "RuleResult(OK)"
	return "RuleResult(FAIL: %s — %s)" % [Reason.keys()[reason], message]
