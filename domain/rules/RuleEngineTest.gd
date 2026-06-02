## RuleEngineTest.gd
## Full test suite for RuleEngine. Attach to a Node in a test scene.
## Each test prints PASS/FAIL and what went wrong.
extends Node

var p1: Player
var p2: Player
var zm: ZoneManager
var stack: EffectStack
var ctx: TurnContext

func _ready() -> void:
	print("\n=== RuleEngine Tests ===\n")
	_setup()
	_test_normal_summon()
	_test_tribute_summon()
	_test_set()
	_test_attack()
	_test_direct_attack()
	_test_battle_damage()
	_test_effect_activation()
	_test_legal_actions_aggregate()
	_test_change_position()
	print("\n=== All RuleEngine tests passed ===\n")

# ─── Setup ────────────────────────────────────────────────────────────────────

func _setup() -> void:
	CardFactory.reset_counter()
	p1    = Player.make(1, "P1")
	p2    = Player.make(2, "P2")
	zm    = ZoneManager.new()
	add_child(zm)
	zm.setup([p1, p2])
	stack = EffectStack.new()
	add_child(stack)
	stack.setup([p1, p2], zm)
	ctx   = TurnContext.for_test(p1, p2, 1)
	EffectResolutionStep.zone_manager = zm
	EffectResolutionStep.players      = [p1, p2]

func _reset_field() -> void:
	# Clear all zones by re-creating zm
	zm.queue_free()
	stack.queue_free()
	_setup()

# ─── Card factories ───────────────────────────────────────────────────────────

func _monster(name: String, owner: Player, lvl: int = 4, atk: int = 1500, def: int = 1200) -> CardInstance:
	var d          := CardDefinition.new()
	d.card_id      = StringName(name.to_lower().replace(" ", "_"))
	d.card_name    = name
	d.card_type    = CardDefinition.CardType.MONSTER
	d.attribute    = CardDefinition.Attribute.DARK
	d.monster_type = "Warrior"
	d.monster_kind = CardDefinition.MonsterKind.EFFECT
	d.level        = lvl
	d.atk          = atk
	d.def          = def
	return CardFactory.create(d, owner)

func _spell(name: String, owner: Player) -> CardInstance:
	var d        := CardDefinition.new()
	d.card_id    = StringName(name.to_lower().replace(" ", "_"))
	d.card_name  = name
	d.card_type  = CardDefinition.CardType.SPELL
	d.spell_type = CardDefinition.SpellType.NORMAL
	return CardFactory.create(d, owner)

func _trap(name: String, owner: Player) -> CardInstance:
	var d        := CardDefinition.new()
	d.card_id    = StringName(name.to_lower().replace(" ", "_"))
	d.card_name  = name
	d.card_type  = CardDefinition.CardType.TRAP
	d.trap_type  = CardDefinition.TrapType.NORMAL
	return CardFactory.create(d, owner)

func _place_in_hand(card: CardInstance, player: Player) -> void:
	zm.load_deck([card], player)
	zm.move(card, zm.hand_of(player), ZoneManager.MoveReason.DRAW)

func _place_on_field(card: CardInstance, player: Player, slot: int = -1) -> void:
	_place_in_hand(card, player)
	if slot == -1:
		zm.move_to_first_slot(card, zm.monster_zone_of(player), ZoneManager.MoveReason.NORMAL_SUMMON)
	else:
		zm.move_to_slot(card, zm.monster_zone_of(player), slot, ZoneManager.MoveReason.NORMAL_SUMMON)
	card.face_state = CardInstance.FaceState.FACE_UP
	card.position   = CardDefinition.Position.ATK
	card.summoned_on_turn = 0  ## Turn 0 so no sickness on turn 1

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		push_error("FAIL: %s" % msg)
		assert(false, msg)

func _assert_ok(result: RuleResult, msg: String) -> void:
	_assert(result.valid, "%s — expected OK, got: %s" % [msg, result])

func _assert_fail(result: RuleResult, expected_reason: RuleResult.Reason, msg: String) -> void:
	_assert(not result.valid, "%s — expected FAIL, got OK" % msg)
	_assert(result.reason == expected_reason,
		"%s — expected reason %s, got %s" % [msg, RuleResult.Reason.keys()[expected_reason], RuleResult.Reason.keys()[result.reason]])

# ─── Tests ────────────────────────────────────────────────────────────────────

func _test_normal_summon() -> void:
	print("[TEST] Normal summon rules")
	_reset_field()

	var m := _monster("Test Monster", p1, 4)
	_place_in_hand(m, p1)

	# Happy path
	_assert_ok(RuleEngine.can_normal_summon(m, p1, zm, ctx), "Level 4 from hand")

	# Wrong phase
	var battle_ctx := TurnContext.make(TurnContext.Phase.BATTLE_STEP, 1, p1, p2, p1)
	_assert_fail(RuleEngine.can_normal_summon(m, p1, zm, battle_ctx),
		RuleResult.Reason.WRONG_PHASE, "Cannot summon in battle phase")

	# Not your turn
	_assert_fail(RuleEngine.can_normal_summon(m, p2, zm, ctx),
		RuleResult.Reason.NOT_YOUR_TURN, "P2 cannot summon on P1 turn")

	# Used normal summon
	p1.normal_summons_remaining = 0
	_assert_fail(RuleEngine.can_normal_summon(m, p1, zm, ctx),
		RuleResult.Reason.NO_NORMAL_SUMMONS_LEFT, "No summons remaining")
	p1.normal_summons_remaining = 1

	# Spell cannot be normal summoned
	var s := _spell("Test Spell", p1)
	_place_in_hand(s, p1)
	_assert_fail(RuleEngine.can_normal_summon(s, p1, zm, ctx),
		RuleResult.Reason.NOT_A_MONSTER, "Spell cannot be normal summoned")

	# Not in hand
	var m2 := _monster("Field Monster", p1, 4)
	_place_on_field(m2, p1)
	_assert_fail(RuleEngine.can_normal_summon(m2, p1, zm, ctx),
		RuleResult.Reason.NOT_IN_HAND, "Field monster cannot be normal summoned")

	# Monster zone full
	for i in 4:
		var filler := _monster("Filler %d" % i, p1, 4)
		_place_on_field(filler, p1)
	_assert_fail(RuleEngine.can_normal_summon(m, p1, zm, ctx),
		RuleResult.Reason.MONSTER_ZONE_FULL, "Full field blocks normal summon")

	print("  PASS: normal summon rules")


func _test_tribute_summon() -> void:
	print("[TEST] Tribute summon rules")
	_reset_field()

	var lv7 := _monster("Lv7 Monster", p1, 7, 2500, 2100)
	_place_in_hand(lv7, p1)

	# Insufficient tributes (no monsters on field)
	_assert_fail(RuleEngine.can_normal_summon(lv7, p1, zm, ctx),
		RuleResult.Reason.INSUFFICIENT_TRIBUTES, "Need 2 tributes, have 0")

	# One tribute — still insufficient for lv7
	var t1 := _monster("Tribute 1", p1, 4)
	_place_on_field(t1, p1)
	_assert_fail(RuleEngine.can_normal_summon(lv7, p1, zm, ctx),
		RuleResult.Reason.INSUFFICIENT_TRIBUTES, "Need 2 tributes, have 1")

	# Two tributes — OK
	var t2 := _monster("Tribute 2", p1, 4)
	_place_on_field(t2, p1)
	_assert_ok(RuleEngine.can_normal_summon(lv7, p1, zm, ctx), "Level 7 with 2 tributes")

	# Validate specific tribute targets — wrong controller
	t1.controller = p2
	_assert_fail(
		RuleEngine.can_normal_summon(lv7, p1, zm, ctx, [t1, t2]),
		RuleResult.Reason.INSUFFICIENT_TRIBUTES,
		"Cannot tribute opponent's monster"
	)
	t1.controller = p1

	print("  PASS: tribute summon rules")


func _test_set() -> void:
	print("[TEST] Set rules")
	_reset_field()

	var s := _spell("Test Spell", p1)
	_place_in_hand(s, p1)
	_assert_ok(RuleEngine.can_set(s, p1, zm, ctx), "Can set spell")

	var t := _trap("Test Trap", p1)
	_place_in_hand(t, p1)
	_assert_ok(RuleEngine.can_set(t, p1, zm, ctx), "Can set trap")

	var m := _monster("Test Monster", p1, 4)
	_place_in_hand(m, p1)
	_assert_ok(RuleEngine.can_set(m, p1, zm, ctx), "Can set lv4 monster")

	# Lv5 monster cannot be set without tribute
	var lv5 := _monster("Lv5", p1, 5)
	_place_in_hand(lv5, p1)
	_assert_fail(RuleEngine.can_set(lv5, p1, zm, ctx),
		RuleResult.Reason.WRONG_SUMMON_METHOD, "Lv5 cannot be set")

	print("  PASS: set rules")


func _test_attack() -> void:
	print("[TEST] Attack rules")
	_reset_field()

	var attacker := _monster("Attacker", p1, 4, 1800)
	var target   := _monster("Target", p2, 4, 1200)
	_place_on_field(attacker, p1)
	_place_on_field(target, p2)

	var battle_ctx := TurnContext.make(TurnContext.Phase.BATTLE_STEP, 1, p1, p2, p1)

	_assert_ok(RuleEngine.can_attack(attacker, target, p1, zm, battle_ctx),
		"Basic attack")

	# Wrong phase
	_assert_fail(RuleEngine.can_attack(attacker, target, p1, zm, ctx),
		RuleResult.Reason.NOT_BATTLE_PHASE, "Cannot attack in main phase")

	# Already attacked
	attacker.has_attacked = true
	_assert_fail(RuleEngine.can_attack(attacker, target, p1, zm, battle_ctx),
		RuleResult.Reason.ALREADY_ATTACKED, "Already attacked")
	attacker.has_attacked = false

	# Summoning sickness
	attacker.summoned_on_turn    = 1
	attacker.was_special_summoned = false
	_assert_fail(RuleEngine.can_attack(attacker, target, p1, zm, battle_ctx),
		RuleResult.Reason.SUMMONING_SICKNESS, "Sickness on normal summon turn")
	attacker.summoned_on_turn = 0

	# DEF position cannot attack
	attacker.position = CardDefinition.Position.DEF
	_assert_fail(RuleEngine.can_attack(attacker, target, p1, zm, battle_ctx),
		RuleResult.Reason.CANNOT_ATTACK, "DEF position cannot attack")
	attacker.position = CardDefinition.Position.ATK

	# Cannot attack own monster
	_assert_fail(RuleEngine.can_attack(attacker, attacker, p1, zm, battle_ctx),
		RuleResult.Reason.NO_VALID_ATTACK_TARGET, "Cannot attack own monster")

	print("  PASS: attack rules")


func _test_direct_attack() -> void:
	print("[TEST] Direct attack rules")
	_reset_field()

	var attacker := _monster("Attacker", p1, 4, 1800)
	_place_on_field(attacker, p1)
	var battle_ctx := TurnContext.make(TurnContext.Phase.BATTLE_STEP, 1, p1, p2, p1)

	# P2 has no monsters — direct attack OK
	_assert_ok(RuleEngine.can_attack(attacker, null, p1, zm, battle_ctx),
		"Direct attack when opponent has no monsters")

	# P2 gets a monster — direct attack blocked
	var blocker := _monster("Blocker", p2, 4, 1000)
	_place_on_field(blocker, p2)
	_assert_fail(RuleEngine.can_attack(attacker, null, p1, zm, battle_ctx),
		RuleResult.Reason.DIRECT_ATTACK_BLOCKED, "Direct attack blocked by monster")

	print("  PASS: direct attack rules")


func _test_battle_damage() -> void:
	print("[TEST] Battle damage calculation")
	_reset_field()

	var high := _monster("High ATK", p1, 4, 2000)
	var low  := _monster("Low ATK",  p2, 4, 1000)

	# ATK > ATK → defender destroyed, defender takes difference
	var r1 := RuleEngine.resolve_battle(high, low)
	_assert(r1.target_destroyed,    "Low ATK monster destroyed")
	_assert(not r1.attacker_destroyed, "High ATK survives")
	_assert(r1.defender_damage == 1000, "Defender takes 1000 damage")
	_assert(r1.attacker_damage == 0,    "Attacker takes 0 damage")

	# ATK < ATK → attacker destroyed
	var r2 := RuleEngine.resolve_battle(low, high)
	_assert(r2.attacker_destroyed,    "Low ATK attacker destroyed")
	_assert(r2.attacker_damage == 1000, "Attacker controller takes 1000")

	# Equal ATK → both destroyed
	var eq := _monster("Equal", p2, 4, 2000)
	var r3 := RuleEngine.resolve_battle(high, eq)
	_assert(r3.attacker_destroyed and r3.target_destroyed, "Both destroyed on tie")
	_assert(r3.attacker_damage == 0 and r3.defender_damage == 0, "No damage on tie")

	# ATK vs DEF — no piercing
	var def_monster := _monster("DEF", p2, 4, 500, 2500)
	def_monster.position = CardDefinition.Position.DEF
	var r4 := RuleEngine.resolve_battle(high, def_monster)
	_assert(not r4.target_destroyed,   "DEF 2500 survives ATK 2000")
	_assert(r4.attacker_damage == 500, "Attacker takes 500 from failed DEF attack")

	# ATK vs lower DEF — no piercing
	var low_def := _monster("LowDEF", p2, 4, 100, 800)
	low_def.position = CardDefinition.Position.DEF
	var r5 := RuleEngine.resolve_battle(high, low_def)
	_assert(r5.target_destroyed,     "Low DEF monster destroyed")
	_assert(r5.defender_damage == 0, "No piercing damage by default")

	# Piercing
	high.set_flag(&"piercing")
	var r6 := RuleEngine.resolve_battle(high, low_def)
	_assert(r6.defender_damage == 1200, "Piercing deals 1200 damage (2000-800)")
	high.clear_flag(&"piercing")

	# Direct attack
	var r7 := RuleEngine.resolve_battle(high, null)
	_assert(r7.is_direct_attack(),       "Is direct attack")
	_assert(r7.defender_damage == 2000,  "Direct attack damage = ATK")
	_assert(not r7.target_destroyed,     "No target to destroy")

	print("  PASS: battle damage calculation")


func _test_effect_activation() -> void:
	print("[TEST] Effect activation rules")
	_reset_field()

	var card := _monster("Effect Monster", p1, 4)
	_place_on_field(card, p1)

	# Build a simple ignition effect
	var eff := EffectDefinition.new()
	eff.effect_name   = "Test Ignition"
	eff.spell_speed   = 1
	eff.timing        = EffectDefinition.EffectTiming.OPTIONAL
	eff.category      = EffectDefinition.EffectCategory.IGNITION
	eff.once_per_turn = true
	eff.is_continuous = false
	card.definition.effects = [eff]

	_assert_ok(
		RuleEngine.can_activate_effect(card, 0, p1, zm, ctx, stack),
		"Basic ignition activation"
	)

	# Wrong phase
	var battle_ctx := TurnContext.make(TurnContext.Phase.BATTLE_STEP, 1, p1, p2, p1)
	_assert_fail(
		RuleEngine.can_activate_effect(card, 0, p1, zm, battle_ctx, stack),
		RuleResult.Reason.WRONG_TIMING,
		"Ignition cannot activate in battle phase"
	)

	# Once per turn used
	card.mark_effect_used(0, ctx.turn_number)
	_assert_fail(
		RuleEngine.can_activate_effect(card, 0, p1, zm, ctx, stack),
		RuleResult.Reason.ONCE_PER_TURN_USED,
		"Once per turn already used"
	)
	card.used_effects.clear()

	# Out of range effect index
	_assert_fail(
		RuleEngine.can_activate_effect(card, 99, p1, zm, ctx, stack),
		RuleResult.Reason.EFFECT_NOT_FOUND,
		"Invalid effect index"
	)

	print("  PASS: effect activation rules")


func _test_change_position() -> void:
	print("[TEST] Change battle position rules")
	_reset_field()

	var m := _monster("Test", p1, 4)
	_place_on_field(m, p1)

	_assert_ok(RuleEngine.can_change_battle_position(m, p1, ctx), "Can change position")

	m.set_flag(&"position_changed_this_turn")
	_assert_fail(RuleEngine.can_change_battle_position(m, p1, ctx),
		RuleResult.Reason.CANNOT_CHANGE_POSITION, "Already changed position")
	m.clear_flag(&"position_changed_this_turn")

	m.summoned_on_turn    = 1
	m.was_special_summoned = false
	_assert_fail(RuleEngine.can_change_battle_position(m, p1, ctx),
		RuleResult.Reason.CANNOT_CHANGE_POSITION, "Sickness prevents position change")

	print("  PASS: change battle position rules")


func _test_legal_actions_aggregate() -> void:
	print("[TEST] get_all_legal_actions aggregate")
	_reset_field()

	# Empty field and hand
	var la_empty := RuleEngine.get_all_legal_actions(p1, zm, ctx, stack)
	_assert(not la_empty.has_any_action(), "No actions on empty field")

	# Add a monster to hand
	var m := _monster("Hand Monster", p1, 4)
	_place_in_hand(m, p1)
	var la := RuleEngine.get_all_legal_actions(p1, zm, ctx, stack)
	_assert(m in la.can_normal_summon, "Hand monster appears in can_normal_summon")
	_assert(m in la.can_set,           "Hand monster appears in can_set")

	# Battle phase — attack should appear for field monster
	var attacker := _monster("Field Attacker", p1, 4, 1800)
	_place_on_field(attacker, p1)
	var blocker := _monster("Blocker", p2, 4, 1000)
	_place_on_field(blocker, p2)
	var battle_ctx := TurnContext.make(TurnContext.Phase.BATTLE_STEP, 1, p1, p2, p1)
	var la_battle := RuleEngine.get_all_legal_actions(p1, zm, battle_ctx, stack)
	_assert(la_battle.can_card_attack(attacker), "Field monster can attack")
	_assert(blocker in la_battle.attack_targets_for(attacker), "Blocker is valid target")

	print("  PASS: get_all_legal_actions aggregate")
