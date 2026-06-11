## EffectDefinition.gd
## Declarative description of a single card effect.
## Simple effects are pure data. Complex ones override resolve().
class_name EffectDefinition
extends Resource

# ─── Enums ────────────────────────────────────────────────────────────────────

enum EffectTrigger {
	NONE,          ## Spell/Trap activation; manually activated
	ON_SUMMON,     ## Fires when this card is successfully summoned
	ON_DESTROY,    ## Fires when this card is destroyed
	ON_SEND_TO_GY, ## Fires when sent to Graveyard by any means
	ON_BANISH,
	ON_FLIP,       ## Flip effects
	ON_DRAW,
	ON_DAMAGE,     ## Battle / effect damage received
	ON_BATTLE,     ## When this card battles
	ON_ATTACK,     ## When this card declares an attack
	START_OF_TURN,
	END_OF_TURN,
	STANDBY_PHASE,
}

enum EffectTiming {
	MANDATORY,    ## Must activate if conditions are met (no opt-out)
	OPTIONAL,     ## Player chooses to activate (once per turn window)
	QUICK_EFFECT, ## Can be activated during opponent's turn (has spell speed 2)
	COUNTER,      ## Spell speed 3 — can only be chained to other counters
}

enum EffectCategory {
	IGNITION,   ## Activated from the field during your Main Phase
	TRIGGER,    ## Activates in response to a game event
	QUICK,      ## Quick effect / hand trap
	CONTINUOUS, ## Persistent condition; not placed on the chain
	FLIP,
}

# ─── Identity ─────────────────────────────────────────────────────────────────

@export var effect_name: String = ""  ## Human-readable, e.g. "Search Effect"
@export var effect_text: String = ""  ## Card text segment for this effect

# ─── Activation Rules ─────────────────────────────────────────────────────────

@export var trigger:   EffectTrigger  = EffectTrigger.NONE
@export var timing:    EffectTiming   = EffectTiming.OPTIONAL
@export var category:  EffectCategory = EffectCategory.IGNITION
@export var min_chain_link:int        = 0
@export var max_chain_link:int        = 0
@export var exact_chain_link:int        = 0
@export var spell_speed: int = 1  ## 1 = Ignition/Trigger, 2 = Quick, 3 = Counter

## If true, activating this effect does not start a chain (continuous effects)
@export var is_continuous: bool = false

## Once per turn? Tracked at runtime via CardInstance.used_effects
@export var once_per_turn: bool = true
@export var once_per_turn_per_player: bool = false
@export var once_per_duel_per_player: bool = false

## Once per duel?
@export var once_per_duel: bool = false
var chain_condition: Callable = Callable()
# ─── Costs ────────────────────────────────────────────────────────────────────
## Paid before the effect goes on the chain. Non-optional once activation starts.
## Typed as Array because EffectCost inner classes can't be used in typed arrays.
var costs: Array = []            ## Array[EffectCost]

# ─── Conditions ───────────────────────────────────────────────────────────────
## All must return true for the effect to be activatable.
var conditions: Array = []       ## Array[EffectCondition]

# ─── Targeting ────────────────────────────────────────────────────────────────

@export var targets_required: int = 0   ## 0 = no targeting
var target_conditions: Array = []       ## Array[EffectCondition]

# ─── Resolution Steps ─────────────────────────────────────────────────────────
## Executed in order when this ChainLink resolves.
var resolution_steps: Array = [] ## Array[EffectResolutionStep]

# ─── Runtime Interface ────────────────────────────────────────────────────────

## Override in subclasses for complex card logic.
func resolve(context: EffectContext) -> void:
	for step in resolution_steps:
		
		step.execute(context)

## Returns true if this effect can currently be activated.
## Evaluates all conditions against the live board.
func can_activate(source: CardInstance, zm: ZoneManager, player: Player) -> bool:
	for condition in conditions:
		if not condition.evaluate(source, zm, player):
			return false
	return true

func _to_string() -> String:
	return "EffectDefinition(%s)" % effect_name
