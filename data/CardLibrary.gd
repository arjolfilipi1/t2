# res://data/CardLibrary.gd  (add as AutoLoad)
extends Node

var db: Dictionary = {}  # StringName → CardDefinition

func _ready() -> void:
	_register(_make_dark_magician())
	_register(_make_pot_of_greed())
	_register(_make_lightning_vortex())

func get_card(id: StringName) -> CardDefinition:
	return db.get(id, null)

func _register(def: CardDefinition) -> void:
	db[def.card_id] = def
func _make_ash_blossom() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id      = &"ash_blossom"
	d.card_name    = "Ash blossom & Joyous Spring"
	d.card_type    = CardDefinition.CardType.MONSTER
	d.attribute    = CardDefinition.Attribute.FIRE
	d.monster_type = "Zombie"
	d.monster_kind = CardDefinition.MonsterKind.EFFECT
	d.level        = 3
	d.atk          = 0
	d.def          = 1800
	d.card_text    = "Its ash."
	var eff = EffectDefinition.new()
	eff.effect_name = "Negate Search / Draw / Summon from deck"
	eff.effect_text = d.card_text
	eff.spell_speed = 3
	eff.timing      = EffectDefinition.EffectTiming.QUICK_EFFECT
	eff.category    = EffectDefinition.EffectCategory.QUICK
	eff.once_per_turn = true
	eff.is_continuous = false
	eff.costs = [EffectCost.DiscardSelfCost.new()]
	eff.conditions = [EffectCondition.SourceInZoneCondition.in_hand()]
	var negate := EffectResolutionStep.NegateTopChainLinkStep.new()
	eff.chain_condition = func(link:ChainLink)->bool:
		for step in link.effect.resolution_steps:
			if step is EffectResolutionStep.DrawCardsStep:
				return true
			if step is EffectResolutionStep.SearchDeckStep:
				return true
			if step is EffectResolutionStep.SpecialSummonFromDeckTargetStep:
				return true
		return false
	eff.resolution_steps = [negate]
	d.effects = [eff]
	return d
func _make_dark_magician() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id      = &"dark_magician"
	d.card_name    = "Dark Magician"
	d.card_type    = CardDefinition.CardType.MONSTER
	d.attribute    = CardDefinition.Attribute.DARK
	d.monster_type = "Spellcaster"
	d.monster_kind = CardDefinition.MonsterKind.NORMAL
	d.level        = 7
	d.atk          = 2500
	d.def          = 2100
	d.card_text    = "The ultimate wizard in terms of attack and defense."
	# No effects — normal monsters have empty effects array
	return d
func _make_pot_of_greed() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id   = &"pot_of_greed"
	d.card_name = "Pot of Greed"
	d.card_type = CardDefinition.CardType.SPELL
	d.spell_type = CardDefinition.SpellType.NORMAL

	var eff := EffectDefinition.new()
	eff.effect_name  = "Draw 2"
	eff.effect_text  = "Draw 2 cards."
	eff.spell_speed  = 1
	eff.timing       = EffectDefinition.EffectTiming.OPTIONAL
	eff.category     = EffectDefinition.EffectCategory.IGNITION
	eff.once_per_turn = false
	eff.is_continuous = false

	# No cost, no conditions, one resolution step
	var draw_step := EffectResolutionStep.DrawCardsStep.new()
	draw_step.count = 2
	eff.resolution_steps = [draw_step]

	d.effects = [eff]
	return d
func _make_lightning_vortex() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id    = &"lightning_vortex"
	d.card_name  = "Lightning Vortex"
	d.card_type  = CardDefinition.CardType.SPELL
	d.spell_type = CardDefinition.SpellType.NORMAL

	var eff := EffectDefinition.new()
	eff.effect_name  = "Destroy all opponent face-up monsters"
	eff.spell_speed  = 1
	eff.once_per_turn = false

	# Cost: discard 1 card from hand
	eff.costs = [EffectCost.DiscardCost.make(1)]

	# Condition: opponent must have face-up monsters
	eff.conditions = [
		EffectCondition.OpponentMonsterCountCondition.at_least(1)
	]

	# Resolution: destroy all opponent monsters
	var destroy_step := EffectResolutionStep.DestroyAllMonstersStep.new()
	destroy_step.include_controller = false
	destroy_step.include_opponent   = true
	eff.resolution_steps = [destroy_step]

	d.effects = [eff]
	return d
func _make_sangan() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id      = &"sangan"
	d.card_name    = "Sangan"
	d.card_type    = CardDefinition.CardType.MONSTER
	d.attribute    = CardDefinition.Attribute.DARK
	d.monster_type = "Fiend"
	d.monster_kind = CardDefinition.MonsterKind.EFFECT
	d.level        = 3
	d.atk          = 1000
	d.def          = 600

	var eff := EffectDefinition.new()
	eff.effect_name  = "GY Search"
	eff.effect_text  = "When this card is sent from the field to the GY: add 1 monster with 1500 or less ATK from your deck to your hand."
	eff.trigger      = EffectDefinition.EffectTrigger.ON_SEND_TO_GY
	eff.timing       = EffectDefinition.EffectTiming.MANDATORY
	eff.category     = EffectDefinition.EffectCategory.TRIGGER
	eff.spell_speed  = 1
	eff.once_per_turn = true

	# Condition: was on the field when sent (not discarded from hand)
	eff.conditions = [
		EffectCondition.SourceInZoneCondition.in_graveyard()
		# In a full implementation you'd track "was on field" via a flag
	]

	# Resolution: search for a monster with ATK ≤ 1500
	var search := EffectResolutionStep.SearchDeckStep.new()
	# The UI / GameDirector will set search.chosen_card after showing the
	# player their deck filtered by AtkRangeCondition.at_most(1500)
	eff.resolution_steps = [search]

	d.effects = [eff]
	return d
