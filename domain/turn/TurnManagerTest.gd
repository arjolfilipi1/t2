## TurnManagerTest.gd
## Tests for TurnManager phase transitions, housekeeping, and win conditions.
extends Node

var p1: Player
var p2: Player
var zm: ZoneManager
var stack: EffectStack
var tm: TurnManager

func _ready() -> void:
	print("\n=== TurnManager Tests ===\n")
	_test_phase_sequence()
	_test_draw_phase()
	_test_first_turn_no_draw()
	_test_end_phase_resets()
	_test_turn_passing()
	_test_hand_limit()
	_test_lp_loss()
	_test_skip_to_phase()
	print("\n=== All TurnManager tests passed ===\n")

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
	tm    = TurnManager.new()
	add_child(tm)
	tm.setup([p1, p2], zm, stack)
	EffectResolutionStep.zone_manager = zm
	EffectResolutionStep.players      = [p1, p2]

func _teardown() -> void:
	tm.queue_free()
	stack.queue_free()
	zm.queue_free()
	await get_tree().process_frame

func _seed_deck(player: Player, count: int = 10) -> void:
	var cards: Array[CardInstance] = []
	for i in count:
		var d          := CardDefinition.new()
		d.card_id      = StringName("card_%d_%d" % [player.player_id, i])
		d.card_name    = "Card %d" % i
		d.card_type    = CardDefinition.CardType.MONSTER
		d.attribute    = CardDefinition.Attribute.DARK
		d.monster_type = "Warrior"
		d.monster_kind = CardDefinition.MonsterKind.NORMAL
		d.level        = 4
		d.atk          = 1000
		d.def          = 1000
		cards.append(CardFactory.create(d, player))
	zm.load_deck(cards, player)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		assert(false, msg)

# ─── Tests ────────────────────────────────────────────────────────────────────

func _test_phase_sequence() -> void:
	print("[TEST] Phase sequence")
	_setup()
	_seed_deck(p1, 20)
	_seed_deck(p2, 20)

	var phases_seen: Array[TurnContext.Phase] = []
	tm.phase_changed.connect(func(_old, new_phase, _ctx):
		phases_seen.append(new_phase)
	)

	tm.start_game()
	# Should be in DRAW after start_game
	_assert(tm.current_phase() == TurnContext.Phase.DRAW, "Starts in DRAW")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.STANDBY, "DRAW → STANDBY")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.MAIN_1, "STANDBY → MAIN_1")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.BATTLE_START, "MAIN_1 → BATTLE_START")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.BATTLE_STEP, "BATTLE_START → BATTLE_STEP")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.BATTLE_END, "BATTLE_STEP → BATTLE_END")

	# BATTLE_END immediately goes to MAIN_2 — TurnManager handles it internally
	_assert(tm.current_phase() == TurnContext.Phase.MAIN_2, "BATTLE_END → MAIN_2 auto")

	tm.advance_phase()
	_assert(tm.current_phase() == TurnContext.Phase.END, "MAIN_2 → END")

	# END phase triggers _pass_turn internally → new DRAW for P2
	_assert(tm.current_phase() == TurnContext.Phase.DRAW, "END → DRAW (new turn)")
	_assert(tm.active_player() == p2, "P2 is now active after turn pass")

	await _teardown()
	print("  PASS: phase sequence")


func _test_draw_phase() -> void:
	print("[TEST] Draw phase draws a card")
	_setup()
	_seed_deck(p1, 10)
	_seed_deck(p2, 10)

	var drawn: Array[CardInstance] = []
	tm.card_drawn.connect(func(player, card):
		if player == p2:
			drawn.append(card)
	)

	tm.start_game()
	# P1 turn 1 — no draw. Advance through to END to pass to P2.
	while tm.active_player() == p1:
		tm.advance_phase()

	# Now P2's turn — DRAW phase should auto-draw
	_assert(tm.current_phase() == TurnContext.Phase.DRAW, "P2 in DRAW phase")
	_assert(drawn.size() == 1, "P2 drew exactly 1 card")
	_assert(zm.hand_of(p2).count() == 1, "P2 hand has 1 card")

	await _teardown()
	print("  PASS: draw phase")


func _test_first_turn_no_draw() -> void:
	print("[TEST] First player does not draw on turn 1")
	_setup()
	_seed_deck(p1, 10)
	_seed_deck(p2, 10)

	var p1_drew := false
	tm.card_drawn.connect(func(player, _card):
		if player == p1:
			p1_drew = true
	)

	tm.start_game()
	_assert(tm.current_phase() == TurnContext.Phase.DRAW, "P1 starts in DRAW")
	_assert(not p1_drew, "P1 did not draw on turn 1")
	_assert(zm.hand_of(p1).count() == 0, "P1 hand still empty after draw phase entry")

	await _teardown()
	print("  PASS: first turn no draw")


func _test_end_phase_resets() -> void:
	print("[TEST] End phase resets turn state")
	_setup()
	_seed_deck(p1, 20)
	_seed_deck(p2, 20)

	tm.start_game()
	# Advance to MAIN_1
	tm.advance_phase()  # DRAW → STANDBY
	tm.advance_phase()  # STANDBY → MAIN_1

	# Place a monster on field and mark it as having attacked / changed position
	var d          := CardDefinition.new()
	d.card_id      = &"test_reset"
	d.card_name    = "Reset Test"
	d.card_type    = CardDefinition.CardType.MONSTER
	d.monster_kind = CardDefinition.MonsterKind.NORMAL
	d.level = 4; d.atk = 1000; d.def = 1000
	var card := CardFactory.create(d, p1)
	zm.load_deck([card], p1)
	zm.move_to_first_slot(card, zm.monster_zone_of(p1), ZoneManager.MoveReason.NORMAL_SUMMON)
	card.has_attacked = true
	card.set_flag(&"position_changed_this_turn")

	# Advance through to END
	tm.advance_phase()  # MAIN_1 → BATTLE_START
	tm.advance_phase()  # BATTLE_START → BATTLE_STEP
	tm.advance_phase()  # BATTLE_STEP → BATTLE_END (auto MAIN_2)
	tm.advance_phase()  # MAIN_2 → END  (_pass_turn fires)

	# On P2's turn now — card should have been reset
	_assert(not card.has_attacked, "has_attacked cleared by end phase")
	_assert(not card.has_flag(&"position_changed_this_turn"), "position flag cleared")
	_assert(p1.normal_summons_remaining == 1, "normal summons reset")

	await _teardown()
	print("  PASS: end phase resets")


func _test_turn_passing() -> void:
	print("[TEST] Turn passing alternates active player")
	_setup()
	_seed_deck(p1, 20)
	_seed_deck(p2, 20)

	var active_players: Array[Player] = []
	tm.active_player_changed.connect(func(p): active_players.append(p))

	tm.start_game()
	_assert(tm.active_player() == p1, "P1 starts")
	_assert(tm.current_turn() == 1, "Turn 1")

	# Run P1 through full turn
	while tm.active_player() == p1:
		tm.advance_phase()

	_assert(tm.active_player() == p2, "P2 after P1 end phase")
	# Turn number increments when index wraps back to 0
	_assert(tm.current_turn() == 1, "Still turn 1 (P2 side)")

	# Run P2 through full turn
	while tm.active_player() == p2:
		tm.advance_phase()

	_assert(tm.active_player() == p1, "P1 again")
	_assert(tm.current_turn() == 2, "Turn 2")

	await _teardown()
	print("  PASS: turn passing")


func _test_hand_limit() -> void:
	print("[TEST] Hand size limit enforced at end phase")
	_setup()
	_seed_deck(p1, 20)
	_seed_deck(p2, 20)

	tm.start_game()
	# Give P1 7 cards in hand (over the default limit of 6)
	for i in 7:
		var top := zm.deck_of(p1).peek_top()
		zm.move(top, zm.hand_of(p1), ZoneManager.MoveReason.DRAW)

	_assert(zm.hand_of(p1).count() == 7, "P1 has 7 cards before end phase")

	# Advance to END phase
	tm.advance_phase()  # DRAW → STANDBY (already in DRAW from start_game)
	tm.advance_phase()  # STANDBY → MAIN_1
	tm.advance_phase()  # MAIN_1 → BATTLE_START
	tm.advance_phase()  # BATTLE_START → BATTLE_STEP
	tm.advance_phase()  # BATTLE_STEP → BATTLE_END/MAIN_2
	tm.advance_phase()  # MAIN_2 → END (_pass_turn)

	_assert(zm.hand_of(p1).count() <= 6,
		"P1 hand trimmed to limit (got %d)" % zm.hand_of(p1).count())

	await _teardown()
	print("  PASS: hand size limit")


func _test_lp_loss() -> void:
	print("[TEST] LP reaching 0 fires game_over")
	_setup()
	_seed_deck(p1, 10)
	_seed_deck(p2, 10)
	tm.start_game()

	var winner_seen: Player = null
	var loser_seen:  Player = null
	tm.game_over.connect(func(w, l):
		winner_seen = w
		loser_seen  = l
	)

	p2.take_damage(8000)  ## Should trigger game_over

	_assert(loser_seen  == p2, "P2 lost")
	_assert(winner_seen == p1, "P1 won")
	_assert(tm._game_over, "game_over flag set")

	# advance_phase should be blocked
	var result := tm.advance_phase()
	_assert(not result, "advance_phase blocked after game over")

	await _teardown()
	print("  PASS: LP loss and game over")


func _test_skip_to_phase() -> void:
	print("[TEST] skip_to_phase")
	_setup()
	_seed_deck(p1, 10)
	_seed_deck(p2, 10)
	tm.start_game()

	tm.skip_to_phase(TurnContext.Phase.MAIN_1)
	_assert(tm.current_phase() == TurnContext.Phase.MAIN_1, "Skipped to MAIN_1")

	tm.skip_to_phase(TurnContext.Phase.END)
	_assert(tm.current_phase() == TurnContext.Phase.DRAW, "END → DRAW via _pass_turn")
	_assert(tm.active_player() == p2, "P2 active after skip to END")

	await _teardown()
	print("  PASS: skip_to_phase")
