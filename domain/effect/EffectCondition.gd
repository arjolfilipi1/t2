## EffectCondition.gd
## Base class for declarative activation conditions.
## An array of these lives on EffectDefinition.conditions.
## ALL conditions must return true for the effect to be activatable.
##
## Design rule: conditions are pure query objects — they never mutate
## game state. Only EffectCost and EffectResolutionStep mutate state.
class_name EffectCondition
extends Resource

## Returns true if this condition is currently satisfied.
## source  = the card this effect belongs to
## zm      = ZoneManager for board queries
## player  = the player trying to activate
func evaluate(
	_source: CardInstance,
	_zm: ZoneManager,
	_player: Player
) -> bool:
	push_error("EffectCondition.evaluate() not overridden in %s" % get_script().resource_path)
	return false

## Human-readable description for UI tooltips / error messages.
func describe() -> String:
	return "Condition"


# ══════════════════════════════════════════════════════════════════════════════
# PHASE CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Effect can only be activated during specific phases.
## Requires TurnManager to be registered as an Engine meta.
class PhaseCondition extends EffectCondition:
	## Allowed phase names. Match against TurnManager.current_phase_name().
	## e.g. ["MAIN_1", "MAIN_2"]  or  ["BATTLE"]
	@export var allowed_phases: Array[String] = ["MAIN_1", "MAIN_2"]

	static func main_phases() -> PhaseCondition:
		var c := PhaseCondition.new()
		c.allowed_phases = ["MAIN_1", "MAIN_2"]
		return c

	static func battle_phase() -> PhaseCondition:
		var c := PhaseCondition.new()
		c.allowed_phases = ["BATTLE_STEP", "DAMAGE_STEP"]
		return c

	static func any_phase() -> PhaseCondition:
		var c := PhaseCondition.new()
		c.allowed_phases = []   ## Empty = all phases allowed
		return c

	func evaluate(_source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		if allowed_phases.is_empty():
			return true
		var tm = Engine.get_singleton(&"TurnManager") if Engine.has_singleton(&"TurnManager") else null
		if tm == null:
			return true   ## No TurnManager in test context → always pass
		return tm.current_phase_name() in allowed_phases

	func describe() -> String:
		if allowed_phases.is_empty():
			return "Any phase"
		return "During %s" % ", ".join(allowed_phases)


# ══════════════════════════════════════════════════════════════════════════════
# ONCE-PER-TURN / ONCE-PER-DUEL
# ══════════════════════════════════════════════════════════════════════════════

## Effect can only be used once per turn.
## Delegates to CardInstance.was_effect_used_this_turn().
class OncePerTurnCondition extends EffectCondition:
	## The effect index on the source card's definition.effects array.
	## Set this when wiring up an EffectDefinition.
	@export var effect_index: int = 0

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		var tm = Engine.get_singleton(&"TurnManager") if Engine.has_singleton(&"TurnManager") else null
		var turn :int = tm.current_turn if tm != null else 0
		return not source.was_effect_used_this_turn(effect_index, turn)

	func describe() -> String:
		return "Once per turn"


class OncePerDuelCondition extends EffectCondition:
	@export var effect_index: int = 0

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return not source.was_effect_used_this_duel(effect_index)

	func describe() -> String:
		return "Once per duel"


# ══════════════════════════════════════════════════════════════════════════════
# FIELD COUNT CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Requires the activating player to control at least N monsters.
class ControlMonsterCountCondition extends EffectCondition:
	@export var min_count: int = 1
	@export var max_count: int = -1   ## -1 = no upper limit

	static func at_least(n: int) -> ControlMonsterCountCondition:
		var c := ControlMonsterCountCondition.new()
		c.min_count = n
		return c

	static func exactly(n: int) -> ControlMonsterCountCondition:
		var c := ControlMonsterCountCondition.new()
		c.min_count = n
		c.max_count = n
		return c

	static func none() -> ControlMonsterCountCondition:
		var c := ControlMonsterCountCondition.new()
		c.min_count = 0
		c.max_count = 0
		return c

	func evaluate(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		var n := zm.monster_count(player)
		if n < min_count:
			return false
		if max_count >= 0 and n > max_count:
			return false
		return true

	func describe() -> String:
		if max_count == 0:
			return "Control no monsters"
		if max_count < 0:
			return "Control at least %d monster%s" % [min_count, "s" if min_count != 1 else ""]
		return "Control %d–%d monsters" % [min_count, max_count]


## Requires the opponent to control at least N monsters.
class OpponentMonsterCountCondition extends EffectCondition:
	@export var min_count: int = 1

	static func at_least(n: int) -> OpponentMonsterCountCondition:
		var c := OpponentMonsterCountCondition.new()
		c.min_count = n
		return c

	func evaluate(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		## Find opponent — simplified: player_id XOR logic, or ask EffectStack
		var opp := _find_opponent(zm, player)
		if opp == null:
			return false
		return zm.monster_count(opp) >= min_count

	func _find_opponent(zm: ZoneManager, player: Player) -> Player:
		## Iterate all zones to find a player that isn't `player`
		for zone in zm._zones.values():
			if zone.owner != null and zone.owner != player:
				return zone.owner
		return null

	func describe() -> String:
		return "Opponent controls at least %d monster%s" % [min_count, "s" if min_count != 1 else ""]


# ══════════════════════════════════════════════════════════════════════════════
# CARD LOCATION CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Requires the source card to be in a specific zone type.
class SourceInZoneCondition extends EffectCondition:
	@export var required_zone: Zone.ZoneType = Zone.ZoneType.MAIN_MONSTER

	static func on_field() -> SourceInZoneCondition:
		var c := SourceInZoneCondition.new()
		c.required_zone = Zone.ZoneType.MAIN_MONSTER
		return c

	static func in_hand() -> SourceInZoneCondition:
		var c := SourceInZoneCondition.new()
		c.required_zone = Zone.ZoneType.HAND
		return c

	static func in_graveyard() -> SourceInZoneCondition:
		var c := SourceInZoneCondition.new()
		c.required_zone = Zone.ZoneType.GRAVEYARD
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		if source.current_zone == null:
			return false
		return source.current_zone.zone_type == required_zone

	func describe() -> String:
		return "Source must be in %s" % Zone.ZoneType.keys()[required_zone]


## Requires a minimum number of cards in the GY matching a filter.
class GraveyardCountCondition extends EffectCondition:
	@export var min_count: int = 1
	## Optional filter: receives CardInstance, returns bool.
	## If not set, counts all cards in GY.
	var filter: Callable = Callable()

	static func at_least(n: int) -> GraveyardCountCondition:
		var c := GraveyardCountCondition.new()
		c.min_count = n
		return c

	static func with_filter(n: int, f: Callable) -> GraveyardCountCondition:
		var c := GraveyardCountCondition.new()
		c.min_count = n
		c.filter    = f
		return c

	func evaluate(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		var gy_cards := zm.graveyard_of(player).get_cards()
		if filter.is_valid():
			gy_cards = gy_cards.filter(filter)
		return gy_cards.size() >= min_count

	func describe() -> String:
		return "GY has %d+ card%s" % [min_count, "s" if min_count != 1 else ""]


## Requires a minimum hand size.
class HandSizeCondition extends EffectCondition:
	@export var min_cards: int = 1

	static func at_least(n: int) -> HandSizeCondition:
		var c := HandSizeCondition.new()
		c.min_cards = n
		return c

	func evaluate(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		return zm.hand_of(player).count() >= min_cards

	func describe() -> String:
		return "Hand has %d+ card%s" % [min_cards, "s" if min_cards != 1 else ""]


# ══════════════════════════════════════════════════════════════════════════════
# LIFE POINT CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Activatable only when LP are at or below a threshold.
## Example: Last Turn, Blaze Accelerator type effects.
class LifePointCondition extends EffectCondition:
	enum Mode { AT_MOST, AT_LEAST, LESS_THAN_OPPONENT }

	@export var mode:      Mode = Mode.AT_MOST
	@export var threshold: int  = 1000

	static func at_most(lp: int) -> LifePointCondition:
		var c := LifePointCondition.new()
		c.mode      = Mode.AT_MOST
		c.threshold = lp
		return c

	static func at_least(lp: int) -> LifePointCondition:
		var c := LifePointCondition.new()
		c.mode      = Mode.AT_LEAST
		c.threshold = lp
		return c

	func evaluate(_source: CardInstance, _zm: ZoneManager, player: Player) -> bool:
		match mode:
			Mode.AT_MOST:  return player.life_points <= threshold
			Mode.AT_LEAST: return player.life_points >= threshold
		return false

	func describe() -> String:
		match mode:
			Mode.AT_MOST:  return "Your LP ≤ %d" % threshold
			Mode.AT_LEAST: return "Your LP ≥ %d" % threshold
		return "LP condition"


# ══════════════════════════════════════════════════════════════════════════════
# CARD ATTRIBUTE / TYPE CONDITIONS  (used as target conditions too)
# ══════════════════════════════════════════════════════════════════════════════

## Target / source must have a specific attribute.
class AttributeCondition extends EffectCondition:
	@export var required_attribute: CardDefinition.Attribute = CardDefinition.Attribute.DARK

	static func make(attr: CardDefinition.Attribute) -> AttributeCondition:
		var c := AttributeCondition.new()
		c.required_attribute = attr
		return c

	## When used as a target condition, pass the candidate card as `source`.
	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.definition.attribute == required_attribute

	func describe() -> String:
		return "Must be %s" % CardDefinition.Attribute.keys()[required_attribute]


## Target / source must be a specific monster type.
class MonsterTypeCondition extends EffectCondition:
	@export var required_type: String = "Dragon"

	static func make(t: String) -> MonsterTypeCondition:
		var c := MonsterTypeCondition.new()
		c.required_type = t
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.definition.is_monster() and source.definition.monster_type == required_type

	func describe() -> String:
		return "Must be %s-type" % required_type


## Target / source must be a monster (any kind).
class IsMosterCondition extends EffectCondition:
	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.definition.is_monster()

	func describe() -> String:
		return "Must be a monster"


## Target must have ATK within a range.
class AtkRangeCondition extends EffectCondition:
	@export var min_atk: int = 0
	@export var max_atk: int = 99999

	static func at_most(atk: int) -> AtkRangeCondition:
		var c := AtkRangeCondition.new()
		c.max_atk = atk
		return c

	static func at_least(atk: int) -> AtkRangeCondition:
		var c := AtkRangeCondition.new()
		c.min_atk = atk
		return c

	static func between(lo: int, hi: int) -> AtkRangeCondition:
		var c := AtkRangeCondition.new()
		c.min_atk = lo
		c.max_atk = hi
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		var atk := source.get_atk()
		return atk >= min_atk and atk <= max_atk

	func describe() -> String:
		if min_atk == 0:
			return "ATK ≤ %d" % max_atk
		if max_atk == 99999:
			return "ATK ≥ %d" % min_atk
		return "ATK %d–%d" % [min_atk, max_atk]


## Target must have a specific level / rank.
class LevelCondition extends EffectCondition:
	@export var min_level: int = 1
	@export var max_level: int = 12

	static func exactly(lvl: int) -> LevelCondition:
		var c := LevelCondition.new()
		c.min_level = lvl
		c.max_level = lvl
		return c

	static func at_most(lvl: int) -> LevelCondition:
		var c := LevelCondition.new()
		c.max_level = lvl
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		var lv := source.get_level()
		return lv >= min_level and lv <= max_level

	func describe() -> String:
		if min_level == max_level:
			return "Level %d" % min_level
		return "Level %d–%d" % [min_level, max_level]


# ══════════════════════════════════════════════════════════════════════════════
# FLAG CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Source card must (or must NOT) have a specific flag.
class FlagCondition extends EffectCondition:
	@export var flag_name: StringName = &""
	@export var must_have: bool       = true

	static func requires(flag: StringName) -> FlagCondition:
		var c := FlagCondition.new()
		c.flag_name = flag
		c.must_have = true
		return c

	static func forbids(flag: StringName) -> FlagCondition:
		var c := FlagCondition.new()
		c.flag_name = flag
		c.must_have = false
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.has_flag(flag_name) == must_have

	func describe() -> String:
		return "%s flag '%s'" % ["Has" if must_have else "No", flag_name]


# ══════════════════════════════════════════════════════════════════════════════
# COUNTER CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## Source card must have at least N of a named counter.
class HasCounterCondition extends EffectCondition:
	@export var counter_name: StringName = &"spell_counter"
	@export var min_count:    int        = 1

	static func make(name: StringName, n: int = 1) -> HasCounterCondition:
		var c := HasCounterCondition.new()
		c.counter_name = name
		c.min_count    = n
		return c

	func evaluate(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.has_counter(counter_name, min_count)

	func describe() -> String:
		return "Has %d+ %s counter%s" % [min_count, counter_name, "s" if min_count > 1 else ""]


# ══════════════════════════════════════════════════════════════════════════════
# COMPOSITE CONDITIONS
# ══════════════════════════════════════════════════════════════════════════════

## All sub-conditions must pass (AND).
class AllCondition extends EffectCondition:
	var sub_conditions: Array[EffectCondition] = []

	static func make(conditions: Array[EffectCondition]) -> AllCondition:
		var c := AllCondition.new()
		c.sub_conditions = conditions
		return c

	func evaluate(source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		for cond in sub_conditions:
			if not cond.evaluate(source, zm, player):
				return false
		return true

	func describe() -> String:
		return " AND ".join(sub_conditions.map(func(c: EffectCondition) -> String: return c.describe()))


## At least one sub-condition must pass (OR).
class AnyCondition extends EffectCondition:
	var sub_conditions: Array[EffectCondition] = []

	static func make(conditions: Array[EffectCondition]) -> AnyCondition:
		var c := AnyCondition.new()
		c.sub_conditions = conditions
		return c

	func evaluate(source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		for cond in sub_conditions:
			if cond.evaluate(source, zm, player):
				return true
		return false

	func describe() -> String:
		return " OR ".join(sub_conditions.map(func(c: EffectCondition) -> String: return c.describe()))


## Inverts a condition (NOT).
class NotCondition extends EffectCondition:
	var inner: EffectCondition = null

	static func make(condition: EffectCondition) -> NotCondition:
		var c := NotCondition.new()
		c.inner = condition
		return c

	func evaluate(source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		return not inner.evaluate(source, zm, player)

	func describe() -> String:
		return "NOT (%s)" % inner.describe()
