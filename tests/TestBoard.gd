## TestBoard.gd
## Self-contained test scene. Attach to a Node2D in a new scene,
## set the scene's window size to 1280×720, and press Play.
##
## What this tests:
##   ✓ CardView renders with artwork placeholder, stats, type bar, level stars
##   ✓ BoardView lays out all zones for both players
##   ✓ ZoneManager moves drive CardView placement (hand → field → GY)
##   ✓ Flip animation (set → flip summon)
##   ✓ Glow states (activatable, targetable, chain link)
##   ✓ Summon / destroy animations
##   ✓ EffectStack chain build and LIFO resolution
##   ✓ Hand fan layout
##   ✓ LP display and phase label
##
## Controls:
##   D          — P1 draws a card
##   S          — P1 Normal Summons the first hand card
##   A          — Toggle activatable highlights on all P1 field cards
##   T          — Toggle targetable highlights on all P2 field cards
##   C          — Build a 2-link chain then resolve it
##   F          — P1 sets a spell/trap
##   X          — Destroy P1's first monster (battle destroy → GY)
##   TAB        — Advance phase label
##   SPACE      — Run full automated demo sequence
extends Node2D

# ─── Domain Objects ───────────────────────────────────────────────────────────
var results_screen: Control
var p1: Player
var p2: Player
var gd: GameDirector   ## owns zm, stack, tm internally
var ai: AIController   ## controls p2
# ─── Convenience accessors ────────────────────────────────────────────────────
var zm: ZoneManager:
	get: return gd.zm
var stack: EffectStack:  
	get: return gd.stack
var tm:    TurnManager:  
	get: return gd.tm

# ─── UI Objects ───────────────────────────────────────────────────────────────

var board: BoardView

# ─── stats          ───────────────────────────────────────────────────────────
var _cards_drawn: int = 0
var _monsters_summoned: int = 0
var _spells_activated: int = 0
var _traps_activated: int = 0
var _damage_dealt: int = 0
# ─── Internal State ───────────────────────────────────────────────────────────
var _demo_running := false

# ──────────────────────────────────────────────────────────────────────────────
# Startup
# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_boot_domain()
	_boot_ui()
	await get_tree().process_frame
	print("r",board.players)
	_populate_decks()
	_initial_hand_deal()
	gd.start_game()
	board.tree_entered.connect(_update_hud,ConnectFlags.CONNECT_ONE_SHOT)
	#_update_hud()
	#_print_controls()

func _boot_domain() -> void:
	CardFactory.reset_counter()
	p1 = Player.make(1, "You")
	p1.is_human = true
	p2 = Player.make(2, "Opponent")
	gd = GameDirector.new()
	add_child(gd)
	gd.setup([p1, p2])

	## Create AI for p2 with a natural thinking delay
	ai = AIController.new()
	ai.think_delay_ms = 500
	ai.verbose        = true
	add_child(ai)
	ai.setup(p2, gd)
	print("AI priority_passed connections:", gd.stack.priority_passed.get_connections())
func _boot_ui() -> void:
	const BoardScene = preload("res://ui/board/BoardView.tscn")
	board = BoardScene.instantiate()
	add_child(board)
	await get_tree().process_frame
	board.setup(gd.zm, gd.stack, [p1, p2],gd)
	board.card_clicked.connect(_on_card_clicked)
	board.empty_zone_clicked.connect(_on_empty_zone_clicked)
	board.phase_advance_requested.connect(_on_phase_advance)
	board.draw_requested.connect(_on_draw_pressed)
	board.pass_priority_requested.connect(func(): gd.pass_priority(p1))
	board.card_inspect_requested.connect(_on_card_inspect_requested)
	# Wire GameDirector signals to HUD
	gd.phase_changed.connect(func(_name, _turn, _player): _update_hud())
	gd.active_player_changed.connect(func(_p): _update_hud())
	
	const ResultsScene = preload("res://ui/results/ResultsScreen.tscn")
	results_screen = ResultsScene.instantiate()
	add_child(results_screen)
	results_screen.hide()
	results_screen.rematch_requested.connect(_on_rematch)
	results_screen.menu_requested.connect(_on_menu)
	gd.game_over.connect(_on_game_over)
	gd.tm.card_drawn.connect(_track_card_drawn)
	gd.card_summoned.connect(_track_summon)
	gd.damage_dealt.connect(_track_damage)
	gd.action_rejected.connect(func(action, result):
		print("TestBoard: Action rejected — %s: %s" % [action.describe(), result.message])
	)
	gd.tm.card_drawn.connect(func(player, _card):
		if player == p1:
			board.reveal_hand(p1)
	)
	gd.tm.card_drawn.connect(func(player,_card):
		board.refresh_hand(player)
		if player == p1:
			board.reveal_hand(p1)
		
	)
	p1.life_points_changed.connect(func(_p, _o, lp): board.update_lp(p1, lp))
	p2.life_points_changed.connect(func(_p, _o, lp): board.update_lp(p2, lp))

# ──────────────────────────────────────────────────────────────────────────────
# Deck Seeding
# ──────────────────────────────────────────────────────────────────────────────

func _populate_decks() -> void:
	## Build two 10-card test decks (no real CardDatabase needed)
	var p2_defs := [CardLibrary._make_ash_blossom(),CardLibrary._make_ash_blossom(),_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),]
	# P1 deck
	var p1_defs := [
		_def(&"dark_magician",     "Dark Magician",     CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.DARK, "Spellcaster", CardDefinition.MonsterKind.NORMAL,
			4, 2500, 2100),

		_def(&"celtic_guardian",   "Celtic Guardian",   CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.EARTH, "Warrior", CardDefinition.MonsterKind.NORMAL,
			4, 1400, 1200),
		_def(&"mystical_elf",      "Mystical Elf",      CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.LIGHT, "Spellcaster", CardDefinition.MonsterKind.NORMAL,
			4, 800, 2000),
		_def(&"feral_imp",         "Feral Imp",         CardDefinition.CardType.MONSTER,
			CardDefinition.Attribute.DARK, "Fiend", CardDefinition.MonsterKind.NORMAL,
			4, 1300, 1400),
		_spell_def(&"dark_hole",   "Dark Hole",         CardDefinition.SpellType.NORMAL),
		CardLibrary._make_pot_of_greed(),
		CardLibrary._make_ash_blossom(),
		CardLibrary._make_ash_blossom(),
		CardLibrary._make_pot_of_greed(),
		#_spell_def(&"pot_greed",   "Pot of Greed",      CardDefinition.SpellType.NORMAL),
		_spell_def(&"change_heart","Change of Heart",   CardDefinition.SpellType.NORMAL),
		CardLibrary._make_test_magician(),
		CardLibrary._make_test_magician(),
	]

	var p1_cards: Array[CardInstance] = []
	for def in p1_defs:
		p1_cards.append(CardFactory.create(def, p1))
	zm.load_deck(p1_cards, p1)
	zm.shuffle_deck(p1)

	# P2 deck (same set, different owner)
	var p2_cards: Array[CardInstance] = []
	for def in p2_defs:
		p2_cards.append(CardFactory.create(def, p2))
	zm.load_deck(p2_cards, p2)
	zm.shuffle_deck(p2)

# ──────────────────────────────────────────────────────────────────────────────
# CardDefinition helpers (no .tres files needed)
# ──────────────────────────────────────────────────────────────────────────────

func _def(
	id: StringName, card_name: String,
	ctype: CardDefinition.CardType,
	attr: CardDefinition.Attribute,
	mtype: String,
	mkind: CardDefinition.MonsterKind,
	lvl: int, atk: int, def_val: int
) -> CardDefinition:
	var d              := CardDefinition.new()
	d.card_id          = id
	d.card_name        = card_name
	d.card_type        = ctype
	d.attribute        = attr
	d.monster_type     = mtype
	d.monster_kind     = mkind
	d.level            = lvl
	d.atk              = atk
	d.def              = def_val
	return d

func _spell_def(id: StringName, card_name: String, stype: CardDefinition.SpellType) -> CardDefinition:
	var d          := CardDefinition.new()
	d.card_id      = id
	d.card_name    = card_name
	d.card_type    = CardDefinition.CardType.SPELL
	d.spell_type   = stype
	return d

func _trap_def(id: StringName, card_name: String, ttype: CardDefinition.TrapType) -> CardDefinition:
	var d          := CardDefinition.new()
	d.card_id      = id
	d.card_name    = card_name
	d.card_type    = CardDefinition.CardType.TRAP
	d.trap_type    = ttype
	return d

# ──────────────────────────────────────────────────────────────────────────────
# Initial Hand Deal
# ──────────────────────────────────────────────────────────────────────────────

func _initial_hand_deal() -> void:
	_draw_n(p1, 5)
	_draw_n(p2, 5)
	print(board.players)
	board.refresh_hand(p1)
	board.refresh_hand(p2)
	board.reveal_hand(p1)   ## P1 cards are face-up (local player)
	## P2 hand stays face-down (opponent)

func _draw_n(player: Player, count: int) -> void:
	for _i in count:
		_draw_one(player)

func _draw_one(player: Player) -> void:
	var deck := zm.deck_of(player)
	if deck.is_empty():
		print("TestBoard: %s has no cards left in deck!" % player.display_name)
		return
	var top := deck.peek_top()
	zm.move(top, zm.hand_of(player), ZoneManager.MoveReason.DRAW)
	
	if player == p1:
		board.reveal_hand(p1)

# ──────────────────────────────────────────────────────────────────────────────
# Keyboard Input
# ──────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _demo_running:
		return

	if not event is InputEventKey or not event.pressed:
		return


	match event.keycode:
		KEY_C:
			print("c:",stack.priority_holder.display_name)
		KEY_P:
			print("p",stack.priority_holder.display_name)
			if stack.priority_holder == p1:
				#board.pass_priority_requested.emit()
				gd.pass_priority(p1)
				print("you pass")
			else:
				print("not your prio")

		KEY_B:
			gd.tm.skip_to_phase(TurnContext.Phase.BATTLE_STEP)
			print("TestBoard:skipped to battle step")
		KEY_E:
			_summon_p2_monster()
		KEY_D:
			_on_draw_pressed()
		KEY_S:
			_summon_from_hand()
		KEY_A:
			_toggle_activatable()
		KEY_T:
			_toggle_targetable()

		KEY_F:
			_set_spell_from_hand()
		KEY_X:
			_destroy_first_p1_monster()
		KEY_TAB:
			_on_phase_advance()
		KEY_Z:
			if gd.undo():
				print("TestBoard: Undo → %s" % gd.undo_manager.redo_label())
			else:
				print("TestBoard: Nothing to undo")
		KEY_Y:
			if gd.redo():
				print("TestBoard: Redo → %s" % gd.undo_manager.undo_label())
			else:
				print("TestBoard: Nothing to redo")


# ──────────────────────────────────────────────────────────────────────────────
# Game Actions
# ──────────────────────────────────────────────────────────────────────────────

func _on_draw_pressed() -> void:
	_draw_one(p1)
	print("TestBoard: P1 drew a card (hand=%d)" % zm.hand_of(p1).count())

func _summon_from_hand() -> void:
	var hand := zm.hand_of(p1)
	if hand.is_empty():
		print("TestBoard: P1 hand is empty")
		return

	var target: CardInstance = null
	for card in hand.get_cards():
		if card.definition.is_monster() and card.definition.can_be_normal_summoned():
			target = card
			break

	if target == null:
		print("TestBoard: No normal-summonable monster in P1 hand")
		return

	if not gd.normal_summon(p1, target):
		return   ## rejection already printed via action_rejected signal
	target.summoned_on_turn = 0
	board.refresh_hand(p1)
	print("TestBoard: Summoned %s" % target.definition.card_name)

func _set_spell_from_hand() -> void:
	var hand := zm.hand_of(p1)
	var target: CardInstance = null
	for card in hand.get_cards():
		if not card.definition.is_monster():
			target = card
			break

	if target == null:
		print("TestBoard: No spell/trap in P1 hand")
		return

	if not gd.set_card(p1, target):
		return

	board.refresh_hand(p1)
	print("TestBoard: Set %s" % target.definition.card_name)

func _destroy_first_p1_monster() -> void:
	var monsters := zm.monsters_on_field(p1)
	if monsters.is_empty():
		print("TestBoard: No P1 monsters on field")
		return
	var target := monsters[0]
	zm.move(target, zm.graveyard_of(p1), ZoneManager.MoveReason.BATTLE_DESTROY)
	print("TestBoard: Destroyed %s → GY" % target.definition.card_name)

# ──────────────────────────────────────────────────────────────────────────────
# Highlight Toggles
# ──────────────────────────────────────────────────────────────────────────────

var _activatable_on := false
var _targetable_on  := false

func _toggle_activatable() -> void:
	_activatable_on = not _activatable_on
	if _activatable_on:
		var cards := zm.all_cards_on_field(p1)
		board.highlight_activatable(cards)
		print("TestBoard: Activatable highlights ON (%d cards)" % cards.size())
	else:
		board.clear_all_glows()
		print("TestBoard: Highlights cleared")

func _toggle_targetable() -> void:
	_targetable_on = not _targetable_on
	if _targetable_on:
		var cards := zm.all_cards_on_field(p2)
		board.highlight_targetable(cards)
		print("TestBoard: Targetable highlights ON (%d P2 cards)" % cards.size())
	else:
		board.clear_all_glows()
		print("TestBoard: Highlights cleared")


# ──────────────────────────────────────────────────────────────────────────────
# Phase Advance
# ──────────────────────────────────────────────────────────────────────────────

func _on_phase_advance() -> void:
	gd.advance_phase(tm.active_player())
	print("TestBoard: Phase → %s (Turn %d)" % [tm.current_phase_name(), tm.current_turn()])

# ──────────────────────────────────────────────────────────────────────────────
# Board Click Handlers
# ──────────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Use global_position for accurate click detection
		var target_node = get_ui_node_at_position(self, event.global_position)
		#
		#if target_node:
			#while target_node:
				#print("Click went to: ",target_node.get_parent().name if target_node.get_parent() else "" ,";", target_node.name)
				#target_node = target_node.get_parent()
		#else:
			#print("Click went to: None (Empty Space)")

func get_ui_node_at_position(current_node: Node, click_pos: Vector2) -> Control:
	# Check children backwards to prioritize front-most UI elements first
	var children = current_node.get_children()
	for i in range(children.size() - 1, -1, -1):
		var found_node = get_ui_node_at_position(children[i], click_pos)
		if found_node:
			return found_node # Return immediately if a child was clicked
			
	# Check the current node after checking its children
	if current_node is Control and current_node.visible:
		# Important: MOUSE_FILTER_IGNORE lets clicks pass through to elements behind it
		if current_node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if current_node.get_global_rect().has_point(click_pos):
				return current_node
				
	return null
func _on_card_clicked(card: CardInstance, _view: CardView) -> void:
	print("TestBoard: Clicked → %s (zone=%s, atk=%d, def=%d)" % [
		card.definition.card_name,
		str(card.current_zone.zone_id) if card.current_zone else "none",
		card.get_atk(),
		card.get_def(),
	])
	board.select_card(card)

func _on_empty_zone_clicked(zone: Zone, slot: int) -> void:
	print("TestBoard: Clicked empty zone %s slot %d" % [zone.zone_id, slot])


func _summon_p2_monster() -> void:
	## Force a P2 monster directly from deck to field for demo purposes
	var deck := zm.deck_of(p2)
	if deck.is_empty():
		return
	## Find a monster
	var target: CardInstance = null
	for card in deck.get_cards():
		if card.definition.is_monster():
			target = card
			break
	if target == null:
		return
	## Move deck → hand first (triggers face-up animation)
	zm.move(target, zm.hand_of(p2), ZoneManager.MoveReason.DRAW)
	## Then field
	if not zm.monster_zone_of(p2).is_full():
		zm.move_to_first_slot(
			target, zm.monster_zone_of(p2), ZoneManager.MoveReason.SPECIAL_SUMMON
		)
		#target.record_special_summon(_turn, &"effect")

func _apply_test_modifier() -> void:
	var monsters := zm.monsters_on_field(p1)
	if monsters.is_empty():
		return
	var card    := monsters[0]
	var old_atk := card.get_atk()
	var mod     := StatModifier.additive(&"atk", 800, 9999, -1, -1, "Test Boost")
	card.add_modifier(mod)
	print("TestBoard:   ATK %d → %d" % [old_atk, card.get_atk()])

# ──────────────────────────────────────────────────────────────────────────────
# HUD
# ──────────────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	board.update_lp(p1, p1.life_points)
	board.update_lp(p2, p2.life_points)
	if gd != null and gd.tm != null and gd.tm.context != null:
		board.update_phase(
			gd.tm.current_phase_name(),
			gd.tm.current_turn(),
			gd.tm.active_player().player_id
		)

# ──────────────────────────────────────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────────────────────────────────────
func _get_cards_drawn_count() -> int:
	return _cards_drawn

func _get_monsters_summoned_count() -> int:
	return _monsters_summoned

func _get_spells_activated_count() -> int:
	return _spells_activated

func _get_traps_activated_count() -> int:
	return _traps_activated

func _get_damage_dealt() -> int:
	return _damage_dealt

# Increment these when actions happen (connect to GameDirector signals)
func _track_card_drawn(player: Player, _card: CardInstance) -> void:
	if player == p1:
		_cards_drawn += 1

func _track_summon(card: CardInstance, was_normal: bool) -> void:
	if card.controller == p1:
		_monsters_summoned += 1

func _track_damage(amount: int, to_player: Player, from_battle: bool) -> void:
	if to_player != p1:  # Damage dealt TO opponent
		_damage_dealt += amount

func _on_rematch() -> void:
	# Reset the game
	get_tree().reload_current_scene()

func _on_menu() -> void:
	# Go back to main menu (or just reload)
	get_tree().reload_current_scene()


# Add game over handler
func _on_game_over(winner: Player, loser: Player) -> void:
	print("Game Over! Winner: ", winner.display_name)
	
	# Collect stats (you can track more stats during gameplay)
	var stats = {
		"turn_count": tm.current_turn(),
		"cards_drawn": _get_cards_drawn_count(),
		"monsters_summoned": _get_monsters_summoned_count(),
		"spells_activated": _get_spells_activated_count(),
		"traps_activated": _get_traps_activated_count(),
		"damage_dealt": _get_damage_dealt(),
	}
	
	results_screen.show_results(winner, loser, stats)
func _first_on_field(player: Player) -> CardInstance:
	var monsters := zm.monsters_on_field(player)
	return monsters[0] if not monsters.is_empty() else null

func _print_controls() -> void:
	print("""
TestBoard Controls
──────────────────
  D      Draw a card
  S      Normal Summon first monster from hand
  F      Set first spell/trap from hand face-down
  A      Toggle activatable glow on P1 field
  T      Toggle targetable glow on P2 field
  C      Run 2-link chain demo (needs monsters on both sides first)
  X      Destroy P1's first monster (→ GY)
  TAB    Advance phase
  SPACE  Run full automated demo sequence
  Click  Select a card and print its info
""")
func _on_card_inspect_requested(card: CardInstance) -> void:
	print("Card inspection requested: %s" % card.definition.card_name)
	# You can implement a full card inspection popup here
	# For now, just print the card details
	print("  Type: %s" % card.definition.card_type)
	if card.definition.is_monster():
		print("  ATK: %d, DEF: %d" % [card.get_atk(), card.get_def()])
	print("  Text: %s" % card.definition.card_text)
