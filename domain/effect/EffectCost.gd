## EffectCost.gd
## Base class for all effect costs.
## Costs are paid at activation time, before the effect goes on the chain.
## Once paid they are NOT refunded even if the effect is later negated.
##
## Usage in EffectDefinition:
##   costs = [
##     DiscardCost.new(),           # discard 1 card from hand
##     LifePointCost.new_half(),    # pay half LP
##   ]
##
## The EffectStack calls:
##   1. can_pay(source, zm, player)  → bool  (check before showing activation option)
##   2. pay(source, zm, player)              (execute when player confirms activation)
class_name EffectCost
extends Resource

# ─── Interface ────────────────────────────────────────────────────────────────

## Returns true if the player is currently able to pay this cost.
## Called before offering the activation option in the UI.
func can_pay(_source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
	push_error("EffectCost.can_pay() not implemented in %s" % get_script().resource_path)
	return false

## Execute the cost payment. Only called after can_pay() returned true
## and the player confirmed they want to activate.
func pay(_source: CardInstance, _zm: ZoneManager, _player: Player) -> void:
	push_error("EffectCost.pay() not implemented in %s" % get_script().resource_path)

## Human-readable description shown in the UI activation prompt.
func describe() -> String:
	return "Pay cost"


# ══════════════════════════════════════════════════════════════════════════════
# LIFE POINT COSTS
# ══════════════════════════════════════════════════════════════════════════════

## Pay a fixed number of Life Points.
## Examples: Solemn Judgment (half LP), Card of Demise (1000 LP)
class LifePointCost extends EffectCost:
	enum Mode { FIXED, HALF }

	@export var mode:   Mode = Mode.FIXED
	@export var amount: int  = 1000   ## Used when mode == FIXED

	static func fixed(lp: int) -> LifePointCost:
		var c := LifePointCost.new()
		c.mode   = Mode.FIXED
		c.amount = lp
		return c

	static func half() -> LifePointCost:
		var c := LifePointCost.new()
		c.mode = Mode.HALF
		return c

	func _resolve_amount(player: Player) -> int:
		match mode:
			Mode.HALF:  return int(player.life_points / 2.0)
			_:           return amount

	func can_pay(_source: CardInstance, _zm: ZoneManager, player: Player) -> bool:
		var cost := _resolve_amount(player)
		return player.life_points > cost   ## Must survive the payment (> not >=)

	func pay(_source: CardInstance, _zm: ZoneManager, player: Player) -> void:
		player.take_damage(_resolve_amount(player))

	func describe() -> String:
		match mode:
			Mode.HALF:  return "Pay half your LP"
			_:           return "Pay %d LP" % amount


# ══════════════════════════════════════════════════════════════════════════════
# DISCARD COSTS
# ══════════════════════════════════════════════════════════════════════════════

## Discard one or more cards from hand to the Graveyard.
## Examples: Lightning Vortex (discard 1), Dark World Dealings (discard 1)
class DiscardCost extends EffectCost:
	@export var count: int = 1   ## Number of cards to discard

	## If set, only cards matching this filter may be discarded.
	## Filter receives (card: CardInstance) → bool
	var filter: Callable = Callable()

	static func make(n: int = 1) -> DiscardCost:
		var c := DiscardCost.new()
		c.count = n
		return c

	func can_pay(_source: CardInstance, _zm: ZoneManager, player: Player) -> bool:
		if _zm.hand_of(player).count() < count:
			return false
		if filter.is_valid():
			var matching := _zm.hand_of(player).get_cards().filter(filter)
			return matching.size() >= count
		return true

	## In a full integration the UI selects which cards to discard and passes
	## them via chosen_cards before calling pay(). Here we discard from the top.
	var chosen_cards: Array[CardInstance] = []

	func pay(_source: CardInstance, zm: ZoneManager, player: Player) -> void:
		var to_discard: Array[CardInstance]
		if chosen_cards.size() >= count:
			to_discard = chosen_cards.slice(0, count)
		else:
			# Fallback: discard last card(s) from hand (leftmost = index 0)
			var hand_cards := zm.hand_of(player).get_cards()
			to_discard = hand_cards.slice(hand_cards.size() - count)
		for card in to_discard:
			zm.move(card, zm.graveyard_of(player), ZoneManager.MoveReason.EFFECT_SEND)
		chosen_cards.clear()

	func describe() -> String:
		return "Discard %d card%s" % [count, "s" if count > 1 else ""]


## Discard the source card itself as the cost (e.g. Hand Traps).
class DiscardSelfCost extends EffectCost:
	func can_pay(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.is_in_hand()

	func pay(source: CardInstance, zm: ZoneManager, player: Player) -> void:
		zm.move(source, zm.graveyard_of(player), ZoneManager.MoveReason.EFFECT_SEND)

	func describe() -> String:
		return "Discard this card"


# ══════════════════════════════════════════════════════════════════════════════
# TRIBUTE / SEND FROM FIELD COSTS
# ══════════════════════════════════════════════════════════════════════════════

## Tribute (send to GY) monsters you control as a cost.
## Examples: Tribute to the Doomed (tribute 1 monster)
class TributeCost extends EffectCost:
	@export var count: int = 1

	var chosen_tributes: Array[CardInstance] = []

	static func make(n: int = 1) -> TributeCost:
		var c := TributeCost.new()
		c.count = n
		return c

	func can_pay(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		return zm.monster_count(player) >= count

	func pay(_source: CardInstance, zm: ZoneManager, player: Player) -> void:
		var to_tribute: Array[CardInstance]
		if chosen_tributes.size() >= count:
			to_tribute = chosen_tributes.slice(0, count)
		else:
			to_tribute = zm.monsters_on_field(player).slice(0, count)
		for card in to_tribute:
			zm.move(card, zm.graveyard_of(player), ZoneManager.MoveReason.TRIBUTE)
		chosen_tributes.clear()

	func describe() -> String:
		return "Tribute %d monster%s" % [count, "s" if count > 1 else ""]


## Send the source card itself to the Graveyard as cost (e.g. Witch of the Black Forest).
class SendSelfToGYCost extends EffectCost:
	func can_pay(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		return source.is_on_field()

	func pay(source: CardInstance, zm: ZoneManager, player: Player) -> void:
		zm.move(source, zm.graveyard_of(player), ZoneManager.MoveReason.EFFECT_SEND)

	func describe() -> String:
		return "Send this card to the GY"


## Banish cards from hand, field, or GY as cost.
## Examples: D.D. Crow (banish from hand), Chaos cards (banish from GY)
class BanishCost extends EffectCost:
	enum Source { HAND, FIELD, GRAVEYARD, ANY }

	@export var count:       int    = 1
	@export var from_source: Source = Source.GRAVEYARD

	var chosen_cards: Array[CardInstance] = []

	static func from_gy(n: int = 1) -> BanishCost:
		var c := BanishCost.new()
		c.count       = n
		c.from_source = Source.GRAVEYARD
		return c

	static func from_hand(n: int = 1) -> BanishCost:
		var c := BanishCost.new()
		c.count       = n
		c.from_source = Source.HAND
		return c

	func _available_cards(zm: ZoneManager, player: Player) -> Array[CardInstance]:
		match from_source:
			Source.HAND:       return zm.hand_of(player).get_cards()
			Source.GRAVEYARD:  return zm.graveyard_of(player).get_cards()
			Source.FIELD:      return zm.all_cards_on_field(player)
			Source.ANY:
				var all: Array[CardInstance] = []
				all.append_array(zm.hand_of(player).get_cards())
				all.append_array(zm.graveyard_of(player).get_cards())
				all.append_array(zm.all_cards_on_field(player))
				return all
		return []

	func can_pay(_source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		return _available_cards(zm, player).size() >= count

	func pay(_source: CardInstance, zm: ZoneManager, player: Player) -> void:
		var pool := _available_cards(zm, player)
		var to_banish: Array[CardInstance]
		if chosen_cards.size() >= count:
			to_banish = chosen_cards.slice(0, count)
		else:
			to_banish = pool.slice(0, count)
		for card in to_banish:
			zm.move(card, zm.banished_of(player), ZoneManager.MoveReason.EFFECT_BANISH)
		chosen_cards.clear()

	func describe() -> String:
		var src := Source.keys()[from_source].to_lower()
		return "Banish %d card%s from %s" % [count, "s" if count > 1 else "", src]


# ══════════════════════════════════════════════════════════════════════════════
# COUNTER COSTS
# ══════════════════════════════════════════════════════════════════════════════

## Remove counters from the source card as cost.
## Examples: Spell Counter removal effects (Arcanite Magician, etc.)
class RemoveCounterCost extends EffectCost:
	@export var counter_name: StringName = &"spell_counter"
	@export var count:        int        = 1
	@export var from_source:  bool       = true   ## If false, remove from any valid card

	static func make(name: StringName, n: int = 1) -> RemoveCounterCost:
		var c := RemoveCounterCost.new()
		c.counter_name = name
		c.count        = n
		return c

	func can_pay(source: CardInstance, _zm: ZoneManager, _player: Player) -> bool:
		if from_source:
			return source.has_counter(counter_name, count)
		# Could extend to check all field cards — simplified here
		return source.has_counter(counter_name, count)

	func pay(source: CardInstance, _zm: ZoneManager, _player: Player) -> void:
		if from_source:
			source.remove_counter(counter_name, count)

	func describe() -> String:
		return "Remove %d %s counter%s" % [count, counter_name, "s" if count > 1 else ""]


# ══════════════════════════════════════════════════════════════════════════════
# COMPOSITE COST
# ══════════════════════════════════════════════════════════════════════════════

## Pay multiple costs simultaneously (AND logic).
## All sub-costs must be payable, and all are paid at once.
class CompositeCost extends EffectCost:
	var sub_costs: Array[EffectCost] = []

	static func make(costs: Array[EffectCost]) -> CompositeCost:
		var c := CompositeCost.new()
		c.sub_costs = costs
		return c

	func can_pay(source: CardInstance, zm: ZoneManager, player: Player) -> bool:
		for cost in sub_costs:
			if not cost.can_pay(source, zm, player):
				return false
		return true

	func pay(source: CardInstance, zm: ZoneManager, player: Player) -> void:
		for cost in sub_costs:
			cost.pay(source, zm, player)

	func describe() -> String:
		var parts := sub_costs.map(func(c: EffectCost) -> String: return c.describe())
		return "; ".join(parts)


# ══════════════════════════════════════════════════════════════════════════════
# COST EXECUTOR  (static helper used by EffectStack)
# ══════════════════════════════════════════════════════════════════════════════

## Utility class — does NOT extend EffectCost.
## Used by EffectStack to check and pay all costs on an EffectDefinition.
class CostExecutor:
	## Returns true if ALL costs on the effect can currently be paid.
	static func can_pay_all(
		effect: EffectDefinition,
		source: CardInstance,
		zm: ZoneManager,
		player: Player
	) -> bool:
		for cost in effect.costs:
			if not cost.can_pay(source, zm, player):
				return false
		return true

	## Pays ALL costs in order. Call only after can_pay_all() returned true.
	static func pay_all(
		effect: EffectDefinition,
		source: CardInstance,
		zm: ZoneManager,
		player: Player
	) -> void:
		for cost in effect.costs:
			cost.pay(source, zm, player)

	## Human-readable summary of all costs.
	static func describe_all(effect: EffectDefinition) -> String:
		if effect.costs.is_empty():
			return ""
		var parts: Array[String] = []
		for cost in effect.costs:
			parts.append(cost.describe())
		return "; ".join(parts)
