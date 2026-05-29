## EffectContext.gd
## Immutable snapshot of the game state at the moment a ChainLink is pushed.
## Passed to EffectDefinition.resolve() when the link resolves.
##
## WHY SNAPSHOT?
##   Yu-Gi-Oh resolves chains LIFO. By the time ChainLink 1 resolves,
##   the board may look nothing like it did when the effect was activated.
##   Targets are locked in at activation; illegal targets at resolution
##   cause the effect to "do nothing" for that target — not an error.
##
## This class is write-once: built by EffectStack when a link is pushed,
## then handed read-only to resolve(). Nothing in resolution should mutate it.
class_name EffectContext
extends RefCounted

# ─── Activation Context ───────────────────────────────────────────────────────

## The player who activated this effect.
var controller: Player

## The card the effect belongs to (may have moved zones by resolution time).
var source_card: CardInstance

## Index into source_card.definition.effects for this specific effect.
var effect_index: int

## The EffectDefinition being resolved (convenience ref). Null for test/mock contexts.
var effect: EffectDefinition = null

## Which chain link index this is (1 = bottom of chain, N = top).
var chain_index: int

# ─── Targets ──────────────────────────────────────────────────────────────────

## Cards targeted by this effect at activation time.
## Locked in — do NOT re-query the board during resolution.
## Check target.is_on_field() etc. at resolution time to handle mid-chain removal.
var targets: Array[CardInstance] = []

## Additional named targets for effects that target multiple distinct groups.
## e.g. { &"equip_target": card, &"material_targets": [c1, c2] }
var named_targets: Dictionary = {}

# ─── Board Snapshot ───────────────────────────────────────────────────────────

## Snapshot of each player's life points at activation time.
## Used by damage calculation effects that care about "damage equal to ATK at activation."
var life_points_snapshot: Dictionary = {}   ## Player → int

## Snapshot of the source card's stats at activation time.
## e.g. for "deal damage equal to this card's ATK" effects.
var source_atk_snapshot: int = 0
var source_def_snapshot: int = 0
var source_level_snapshot: int = 0

## The game event that triggered this effect, if any (for trigger effects).
## Null for manually activated effects.
var trigger_event: GameEvent = null

# ─── Resolution State ─────────────────────────────────────────────────────────

## Populated during resolution. Resolution steps can write here to
## pass data to subsequent steps (e.g. "cards that were actually destroyed").
var resolution_data: Dictionary = {}

## True if the effect was negated before resolution (by Solemn Judgment etc.)
var was_negated: bool = false

## True if the cost was paid (set before the link goes on the chain).
var cost_paid: bool = false

# ─── Constructor ──────────────────────────────────────────────────────────────

static func create(
	activating_player: Player,
	card: CardInstance,
	eff_index: int,
	link_index: int,
	target_list: Array[CardInstance] = []
) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.controller        = activating_player
	ctx.source_card       = card
	ctx.effect_index      = eff_index
	# Guard: effects array may be empty in test cards that have no effects defined
	if eff_index >= 0 and eff_index < card.definition.effects.size():
		ctx.effect = card.definition.effects[eff_index]
	ctx.chain_index       = link_index
	ctx.targets           = target_list.duplicate()

	# Snapshot stats at activation time
	ctx.source_atk_snapshot   = card.get_atk()
	ctx.source_def_snapshot   = card.get_def()
	ctx.source_level_snapshot = card.get_level()

	return ctx

# ─── Target Helpers ───────────────────────────────────────────────────────────

## Returns targets that are still valid at resolution time
## (still on the field, in the expected zone, etc.)
func valid_targets() -> Array[CardInstance]:
	return targets.filter(func(t): return t.is_on_field())

## True if at least one target is still valid.
func has_valid_target() -> bool:
	return valid_targets().size() > 0

func get_named_target(key: StringName) -> CardInstance:
	return named_targets.get(key, null)

func get_named_targets(key: StringName) -> Array[CardInstance]:
	return named_targets.get(key, [])

# ─── Resolution Data Helpers ──────────────────────────────────────────────────

func set_data(key: StringName, value: Variant) -> void:
	resolution_data[key] = value

func get_data(key: StringName, default: Variant = null) -> Variant:
	return resolution_data.get(key, default)

func _to_string() -> String:
	return "EffectContext(link=%d, source=%s, targets=%d)" % [
		chain_index,
		source_card.definition.card_name,
		targets.size()
	]
