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
	eff.min_chain_link = 2
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
func _make_test_magician() -> CardDefinition:
	var d := CardDefinition.new()
	d.card_id      = &"test_magician"
	d.card_name    = "Test Magician"
	d.card_type    = CardDefinition.CardType.MONSTER
	d.attribute    = CardDefinition.Attribute.LIGHT
	d.monster_type = "Spellcaster"
	d.monster_kind = CardDefinition.MonsterKind.EFFECT
	d.level        = 4
	d.atk          = 1500
	d.def          = 1200
	d.card_text    = "You can activate 1 of these effects:\n• Gain 1000 LP\n• Special Summon 1 monster from your hand"
	
	# ─── Effect 1: Gain 1000 LP ──────────────────────────────────────────────
	var eff1 := EffectDefinition.new()
	eff1.effect_name  = "Gain 1000 LP"
	eff1.effect_text  = "Gain 1000 Life Points."
	eff1.spell_speed  = 1
	eff1.timing       = EffectDefinition.EffectTiming.OPTIONAL
	eff1.category     = EffectDefinition.EffectCategory.IGNITION
	eff1.once_per_turn = true
	eff1.is_continuous = false
	eff1.targets_required = 0
	
	# Conditions: Must be on field, in Main Phase
	eff1.conditions = [
		EffectCondition.SourceInZoneCondition.on_field(),
		EffectCondition.PhaseCondition.main_phases()
	]
	
	# Resolution: Gain 1000 LP
	var gain_lp := EffectResolutionStep.GainLifePointsStep.new()
	gain_lp.amount = 1000
	eff1.resolution_steps = [gain_lp]
	
	# ─── Effect 2: Special Summon from hand ──────────────────────────────────
	var eff2 := EffectDefinition.new()
	eff2.effect_name  = "Special Summon from Hand"
	eff2.effect_text  = "Special Summon 1 monster from your hand."
	eff2.spell_speed  = 1
	eff2.timing       = EffectDefinition.EffectTiming.OPTIONAL
	eff2.category     = EffectDefinition.EffectCategory.IGNITION
	eff2.once_per_turn = true
	eff2.is_continuous = false
	eff2.targets_required = 0  # Target selection is handled by the UI
	
	# Conditions: Must be on field, in Main Phase
	eff2.conditions = [
		EffectCondition.SourceInZoneCondition.on_field(),
		EffectCondition.PhaseCondition.main_phases()
	]
	
	# Custom resolution: Special Summon from hand
	# Since we need to let the player choose which card, this uses a custom step
	var summon_step := _SummonFromHandStep.new()
	eff2.resolution_steps = [summon_step]
	
	# ─── Add both effects ──────────────────────────────────────────────────────
	d.effects = [eff1, eff2]
	return d

# ─── Custom Resolution Step for Summon from Hand ─────────────────────────────
class _SummonFromHandStep extends EffectResolutionStep:
	var chosen_card: CardInstance = null # Set by the UI before execution
	var target_slot: int = -1 
	
	func execute(context: EffectContext) -> void:
		var z := EffectResolutionStep.zm()
		var player := context.controller
		
		# If no card was chosen, pick the first monster in hand
		if chosen_card == null:
			var hand := z.hand_of(player)
			for card in hand.get_cards():
				if card.definition.is_monster():
					chosen_card = card
					break
		
		if chosen_card == null:
			print("No monster to summon!")
			return
		
		if target_slot >= 0 and target_slot < 5:
			# Use the specific slot the player selected
			if z.monster_zone_of(player).get_card_at(target_slot) == null:
				z.move_to_slot(chosen_card, z.monster_zone_of(player), target_slot, ZoneManager.MoveReason.SPECIAL_SUMMON)
				print("Summoned %s to slot %d" % [chosen_card.definition.card_name, target_slot])
			else:
				# Slot is somehow occupied - fallback to first available
				print("Slot %d occupied, using first available" % target_slot)
				z.move_to_first_slot(chosen_card, z.monster_zone_of(player), ZoneManager.MoveReason.SPECIAL_SUMMON)
		else:
			# No specific slot - use first available
			z.move_to_first_slot(chosen_card, z.monster_zone_of(player), ZoneManager.MoveReason.SPECIAL_SUMMON)
		
		chosen_card.record_special_summon(context.chain_index, &"effect")
		chosen_card = null
		target_slot = -1 # Reset
