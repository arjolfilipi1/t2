## ChainLink.gd
## A single activation on the chain (what Yu-Gi-Oh calls a "Chain Link").
## Holds everything needed to resolve the effect regardless of what
## the board looks like by the time resolution reaches it.
##
## Lifecycle:
##   1. Created by EffectStack.push()
##   2. Context snapshot built and frozen
##   3. Cost paid (if any) before this link is confirmed
##   4. Sits in chain.links[] until resolve() pops it (LIFO)
##   5. Calls effect.resolve(context)
##   6. Emits resolved signal
class_name ChainLink
extends RefCounted

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after this link's effect fully resolves (or is negated).
signal resolved(link: ChainLink, was_negated: bool)

# ─── State ────────────────────────────────────────────────────────────────────

enum LinkState {
	PENDING,   ## On the chain, waiting for resolution
	RESOLVING, ## Currently executing resolve()
	RESOLVED,  ## Finished — effect text carried out (or negated)
	NEGATED,   ## Negated before or during resolution
}

# ─── Identity ─────────────────────────────────────────────────────────────────

## Position in the chain (1 = first activated = resolves last).
var chain_index: int

## The effect being activated.
var effect: EffectDefinition

## The card this effect belongs to.
var source_card: CardInstance

## The player who activated this effect.
var controller: Player

## The game event that caused this activation (null = manual activation).
var trigger_event: GameEvent = null

# ─── Snapshot ─────────────────────────────────────────────────────────────────

## Full resolution context — snapshotted at push time, immutable thereafter.
var context: EffectContext

# ─── Runtime State ────────────────────────────────────────────────────────────

var state: LinkState = LinkState.PENDING

## True once the cost has been paid. Costs are paid immediately on activation,
## before the window for opponents to respond.
var cost_paid: bool = false

# ─── Constructor ──────────────────────────────────────────────────────────────

static func create(
	index: int,
	eff: EffectDefinition,
	card: CardInstance,
	activating_player: Player,
	targets: Array[CardInstance] = [],
	event: GameEvent = null
) -> ChainLink:
	var link := ChainLink.new()
	link.chain_index   = index
	link.effect        = eff
	link.source_card   = card
	link.controller    = activating_player
	link.trigger_event = event

	# Build the immutable context snapshot now
	var eff_index := card.definition.effects.find(eff)
	link.context = EffectContext.create(activating_player, card, eff_index, index, targets)
	link.context.trigger_event = event

	return link

# ─── Resolution ───────────────────────────────────────────────────────────────

## Execute this link's effect resolution.
## Called by EffectStack during chain resolution (LIFO order).
func resolve() -> void:
	assert(state == LinkState.PENDING, "Cannot resolve a link in state: %s" % LinkState.keys()[state])
	state = LinkState.RESOLVING

	if context.was_negated:
		state = LinkState.NEGATED
		resolved.emit(self, true)
		return

	effect.resolve(context)
	state = LinkState.RESOLVED
	resolved.emit(self, false)

## Negate this link before or during resolution.
## The source card's activation is negated — costs already paid are NOT refunded.
func negate() -> void:
	context.was_negated = true
	if state == LinkState.PENDING:
		pass  ## Will be caught in resolve()
	elif state == LinkState.RESOLVING:
		pass  ## Mid-resolution negate (rare edge case — handled by resolve())

# ─── Helpers ──────────────────────────────────────────────────────────────────

func is_pending() -> bool:
	return state == LinkState.PENDING

func is_resolved() -> bool:
	return state in [LinkState.RESOLVED, LinkState.NEGATED]

func was_negated() -> bool:
	return state == LinkState.NEGATED or context.was_negated

## True if the source card is still on the field (relevant for some resolution checks).
func source_is_on_field() -> bool:
	return source_card.is_on_field()

func _to_string() -> String:
	return "ChainLink(%d: %s by %s [%s])" % [
		chain_index,
		effect.effect_name,
		source_card.definition.card_name,
		LinkState.keys()[state]
	]
