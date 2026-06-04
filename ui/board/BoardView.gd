## BoardView.gd
## The complete visual playing field.
## Owns and manages all ZoneViews and CardViews.
## Listens to ZoneManager signals and keeps UI in sync with domain state.
##
## Layout (landscape, 1280×720):
##
##   ┌──────────────────────────────────────────────────────────────────────┐
##   │  [LP P2]  [DECK P2]  [EXTRA P2]          [GY P2]  [BANISH P2]      │  ← P2 info bar
##   │                                                                      │
##   │  [FS P2]  [S0][S1][S2][S3][S4]  (EMZ)    [GY P2 pile]              │  ← P2 spell row
##   │           [M0][M1][M2][M3][M4]                                       │  ← P2 monster row
##   │  ──────────────────────── FIELD ──────────────────────────────────── │
##   │           [M0][M1][M2][M3][M4]                                       │  ← P1 monster row
##   │  [FS P1]  [S0][S1][S2][S3][S4]  (EMZ)    [GY P1 pile]              │  ← P1 spell row
##   │                                                                      │
##   │  [LP P1]  [DECK P1]  [EXTRA P1]          [GY P1]  [BANISH P1]      │  ← P1 info bar
##   │                                                                      │
##   │  ── HAND P1 ──────────────────────────────────────────────────────── │  ← P1 hand
##   │                                                                      │
##   │  [ Chain HUD ]  [ Phase Indicator ]  [ LP Display ]  [ End Turn ]   │  ← HUD bar
##   └──────────────────────────────────────────────────────────────────────┘
##
class_name BoardView
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Player clicked a card (intent determined by current game state).
signal card_clicked(card: CardInstance, view: CardView)

## Player clicked an empty monster zone slot.
signal empty_zone_clicked(zone: Zone, slot: int)

## Player clicked the end-turn / next-phase button.
signal phase_advance_requested()

## Player clicked deck (draw button).
signal draw_requested()

## Card inspected (right-click → full card text popup).
signal card_inspect_requested(card: CardInstance)

# ─── Layout Constants ─────────────────────────────────────────────────────────

const VIEWPORT_W    := 1280.0
const VIEWPORT_H    := 720.0

const SLOT_W        := ZoneView.SLOT_W
const SLOT_H        := ZoneView.SLOT_H
const SLOT_GAP      := 6.0

const FIELD_ROW_Y_P1_MONSTER := 320.0
const FIELD_ROW_Y_P1_SPELL   := 320.0 + SLOT_H + SLOT_GAP
const FIELD_ROW_Y_P2_MONSTER := 320.0 - SLOT_H - SLOT_GAP
const FIELD_ROW_Y_P2_SPELL   := 320.0 - (SLOT_H + SLOT_GAP) * 2.0

const FIELD_COLS_X := [160.0, 160.0 + (SLOT_W + SLOT_GAP),
	160.0 + (SLOT_W + SLOT_GAP) * 2.0,
	160.0 + (SLOT_W + SLOT_GAP) * 3.0,
	160.0 + (SLOT_W + SLOT_GAP) * 4.0]

const FIELD_SPELL_X  := 40.0
const GRAVEYARD_X    := 160.0 + (SLOT_W + SLOT_GAP) * 5.0 + 10.0
const EXTRA_DECK_X   := 40.0 + SLOT_W + 10.0
const DECK_X         := EXTRA_DECK_X + SLOT_W + 10.0
const HAND_Y_P1      := 540.0
const HAND_Y_P2      := 20
const HUD_Y          := VIEWPORT_H - 50.0

# ─── References ───────────────────────────────────────────────────────────────

var zone_manager:  ZoneManager  = null
var effect_stack:  EffectStack  = null
var players:       Array[Player] = []
## Set by TestBoard / GameDirector so BoardView can submit actions directly.
var game_director: GameDirector = null
## The human player — only their cards show the action tooltip.
var local_player: Player = null
# ─── Pending Action State ─────────────────────────────────────────────────────
enum PendingState {
		NONE,            ## Normal — card click shows tooltip
		AWAIT_ATTACK_TARGET,    ## Player clicked Attack; waiting for target card
		AWAIT_EFFECT_TARGET,    ## Player clicked Activate; waiting for target card(s)
}
var _pending_state:       PendingState  = PendingState.NONE
var _pending_card:        CardInstance  = null   ## Card whose action is pending
var _pending_effect_idx:  int           = -1     ## Effect index for AWAIT_EFFECT_TARGET
var _pending_targets:     Array[CardInstance] = []
var _targets_needed:      int           = 0

# ─── View Maps ────────────────────────────────────────────────────────────────

## ZoneView for each slotted zone slot: key = "p1_main_monster_0" etc.
var _slot_views: Dictionary = {}   ## String → ZoneView

## ZoneView for pile zones: key = "p1_graveyard" etc.
var _pile_views: Dictionary = {}   ## String → ZoneView

## CardView for each live card: key = instance_id
var _card_views: Dictionary = {}   ## int → CardView

## Currently selected CardView (for pending action highlight).
var _selected_view: CardView = null

# ─── HUD Nodes ────────────────────────────────────────────────────────────────

var _phase_label:   Label
var _turn_label:    Label
var _p1_lp_label:  Label
var _p2_lp_label:  Label
var _chain_hud:     Control  ## EffectChainHUD
var _end_btn:       Button
var _draw_btn:      Button

# ─── Setup ────────────────────────────────────────────────────────────────────
var _tooltip: CardTooltip
func _ready() -> void:
	custom_minimum_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	_build_field_background()


func setup(
		zm:          ZoneManager,
		stack:       EffectStack,
		player_list: Array[Player],
		gd:          GameDirector = null
) -> void:
	
	zone_manager = zm
	effect_stack = stack
	players      = player_list
	game_director = gd
	local_player  = player_list[0]
	_build_zone_views()
	_build_hud()

	# Connect to ZoneManager
	zone_manager.card_moved.connect(_on_card_moved)
	zone_manager.zone_changed.connect(_on_zone_changed)

	# Connect to EffectStack
	effect_stack.chain_link_pushed.connect(_on_chain_link_pushed)
	effect_stack.chain_link_resolved.connect(_on_chain_link_resolved)
	effect_stack.chain_resolved.connect(_on_chain_resolved)
	effect_stack.priority_passed.connect(_on_priority_passed)
	effect_stack.triggers_pending.connect(_on_triggers_pending)

# ─── Zone View Construction ───────────────────────────────────────────────────

func _build_zone_views() -> void:
	for player in players:
		var is_p1   := player == players[0]
		var monster_y := FIELD_ROW_Y_P1_MONSTER if is_p1 else FIELD_ROW_Y_P2_MONSTER
		var spell_y   := FIELD_ROW_Y_P1_SPELL   if is_p1 else FIELD_ROW_Y_P2_SPELL
		var pid       := "p%d" % player.player_id

		# 5 monster slots
		for i in 5:
			var zv := _make_zone_view(
				zone_manager.monster_zone_of(player), i,
				"M%d" % i,
				Vector2(FIELD_COLS_X[i], monster_y)
			)
			_slot_views["%s_main_monster_%d" % [pid, i]] = zv

		# 5 spell/trap slots
		for i in 5:
			var zv := _make_zone_view(
				zone_manager.spell_zone_of(player), i,
				"S%d" % i,
				Vector2(FIELD_COLS_X[i], spell_y)
			)
			_slot_views["%s_main_spell_%d" % [pid, i]] = zv

		# Field spell zone
		var fs_y := spell_y
		var fs_zv := _make_zone_view(
			zone_manager.field_spell_zone_of(player), 0,
			"FIELD",
			Vector2(FIELD_SPELL_X, fs_y)
		)
		_slot_views["%s_field_spell_0" % pid] = fs_zv

		# Graveyard pile
		var gy_zv := _make_pile_view(
			zone_manager.graveyard_of(player), "GY",
			Vector2(GRAVEYARD_X, monster_y)
		)
		_pile_views["%s_graveyard" % pid] = gy_zv

		# Deck pile
		var deck_zv := _make_pile_view(
			zone_manager.deck_of(player), "DECK",
			Vector2(DECK_X, spell_y)
		)
		_pile_views["%s_deck" % pid] = deck_zv

		# Extra deck pile
		var ex_zv := _make_pile_view(
			zone_manager.extra_deck_of(player), "EXTRA",
			Vector2(EXTRA_DECK_X, spell_y)
		)
		_pile_views["%s_extra_deck" % pid] = ex_zv

		# Banished pile (offset beside GY)
		var ban_zv := _make_pile_view(
			zone_manager.banished_of(player), "BANISH",
			Vector2(GRAVEYARD_X + SLOT_W + SLOT_GAP, monster_y)
		)
		_pile_views["%s_banished" % pid] = ban_zv

func _make_zone_view(zone: Zone, slot: int, label: String, pos: Vector2) -> ZoneView:
	var zv := ZoneView.new()
	add_child(zv)
	zv.position = pos
	zv.setup(zone, slot, label)
	zv.empty_slot_clicked.connect(_on_empty_slot_clicked)
	return zv

func _make_pile_view(zone: Zone, label: String, pos: Vector2) -> ZoneView:
	var zv := ZoneView.new()
	add_child(zv)
	zv.position = pos
	zv.setup(zone, -1, label)
	zv.empty_slot_clicked.connect(_on_empty_slot_clicked)
	return zv

# ─── HUD Construction ─────────────────────────────────────────────────────────

func _build_hud() -> void:
	# Phase / turn indicator
	_phase_label = Label.new()
	_phase_label.name     = "PhaseLabel"
	_phase_label.position = Vector2(VIEWPORT_W / 2.0 - 80, HUD_Y + 4)
	_phase_label.size     = Vector2(160, 24)
	_phase_label.add_theme_font_size_override("font_size", 13)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.modulate = Color(0.9, 0.85, 0.6)
	add_child(_phase_label)

	_turn_label = Label.new()
	_turn_label.name     = "TurnLabel"
	_turn_label.position = Vector2(VIEWPORT_W / 2.0 - 80, HUD_Y - 16)
	_turn_label.size     = Vector2(160, 18)
	_turn_label.add_theme_font_size_override("font_size", 9)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.modulate = Color(0.7, 0.7, 0.7)
	add_child(_turn_label)

	# LP displays
	_p1_lp_label = _make_lp_label("P1 LP: 8000", Vector2(20, HUD_Y))
	_p2_lp_label = _make_lp_label("P2 LP: 8000", Vector2(20, 10))

	# End turn button
	_end_btn = Button.new()
	_end_btn.name     = "EndTurnBtn"
	_end_btn.text     = "END PHASE ▶"
	_end_btn.position = Vector2(VIEWPORT_W - 130, HUD_Y)
	_end_btn.size     = Vector2(120, 30)
	_end_btn.add_theme_font_size_override("font_size", 10)
	_end_btn.pressed.connect(func(): phase_advance_requested.emit())
	add_child(_end_btn)

	# Draw button
	_draw_btn = Button.new()
	_draw_btn.name     = "DrawBtn"
	_draw_btn.text     = "DRAW"
	_draw_btn.position = Vector2(VIEWPORT_W - 260, HUD_Y)
	_draw_btn.size     = Vector2(70, 30)
	_draw_btn.add_theme_font_size_override("font_size", 10)
	_draw_btn.pressed.connect(func(): draw_requested.emit())
	add_child(_draw_btn)

	# Chain HUD (built inline)
	_chain_hud = _build_chain_hud()
	add_child(_chain_hud)
	const TooltipScene := preload("res://ui/card/CardTooltip.tscn")
	

	# inside _build_hud():
	_tooltip = TooltipScene.instantiate()
	add_child(_tooltip)
	_tooltip.action_selected.connect(_on_tooltip_action)

func _make_lp_label(text: String, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = pos
	lbl.size     = Vector2(160, 22)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.95, 0.9, 0.6)
	add_child(lbl)
	return lbl

func _build_chain_hud() -> Control:
	var hud := Control.new()
	hud.name     = "ChainHUD"
	hud.position = Vector2(10, HUD_Y - 60)
	hud.size     = Vector2(400, 55)
	return hud

# ─── Background ───────────────────────────────────────────────────────────────

func _build_field_background() -> void:
	# Deep space felt
	var bg := ColorRect.new()
	bg.name         = "Background"
	bg.size         = Vector2(VIEWPORT_W, VIEWPORT_H)
	bg.color        = Color(0.05, 0.06, 0.10)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Centred field divider line
	var divider := _FieldDivider.new()
	divider.name         = "FieldDivider"
	divider.size         = Vector2(VIEWPORT_W, VIEWPORT_H)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

# ─── Card View Lifecycle ──────────────────────────────────────────────────────

func get_or_create_card_view(card: CardInstance) -> CardView:
	
	if _card_views.has(card.instance_id):
		return _card_views[card.instance_id]
	const CardViewScene := preload("res://ui/card/CardView.tscn")
	var view := CardViewScene.instantiate() as CardView
	view.bind(card)
	view.card_clicked.connect(_on_card_clicked.bind(card))
	view.card_inspected.connect(_on_card_inspected.bind(card))
	_card_views[card.instance_id] = view
	return view

func destroy_card_view(card: CardInstance) -> void:
	if not _card_views.has(card.instance_id):
		return
	var view: CardView = _card_views[card.instance_id]
	_card_views.erase(card.instance_id)
	view.animate_destroy(func(): view.queue_free())

# ─── Zone → ZoneView Lookup ───────────────────────────────────────────────────

func get_slot_view(card: CardInstance) -> ZoneView:
	if card.current_zone == null:
		return null
	var zid    := card.current_zone.zone_id
	var slot   := card.slot_index
	var key    := "%s_%d" % [str(zid), slot]
	if _slot_views.has(key):
		return _slot_views[key]
	if _pile_views.has(str(zid)):
		return _pile_views[str(zid)]
	return null

func get_pile_view_for_zone(zone: Zone) -> ZoneView:
	return _pile_views.get(str(zone.zone_id), null)

# ─── Hand Layout ──────────────────────────────────────────────────────────────

## Re-lays out all cards in P1's hand in a fan/row.
func refresh_hand(player: Player) -> void:
	var hand_zone := zone_manager.hand_of(player)
	var cards     := hand_zone.get_cards()
	var n         := cards.size()
	if n == 0:
		return
	var hand_y = HAND_Y_P1 if player == players[0] else HAND_Y_P2
	var total_w   := n * (CardView.CARD_W + 4)
	var start_x   := (VIEWPORT_W - total_w) / 2.0

	for i in n:
		var card = cards[i]
		var view = get_or_create_card_view(card)
		if view.get_parent() != self:
			continue
		# Subtle fan: slight Y offset and rotation for hand feel
		var t      = float(i) / max(n - 1, 1)
		var arc_y  := sin(t * PI) * (-12.0 if player == players[0] else 12.0 )  ## Cards arc upward at centre
		var rot    = lerp(-4.0, 4.0, t)     ## Gentle spread rotation
		view.position = Vector2(start_x + i * (CardView.CARD_W + 4), hand_y + arc_y)
		view.rotation  = deg_to_rad(rot)

## Flip all hand cards face-down (on request).
func conceal_hand(player: Player) -> void:
	for card in zone_manager.hand_of(player).get_cards():
		var view := get_or_create_card_view(card)
		view.flip_to(false)
## Flip all hand cards face-up (for the local player).
func reveal_hand(player: Player) -> void:
	for card in zone_manager.hand_of(player).get_cards():
		var view := get_or_create_card_view(card)
		view.flip_to(true)

# ─── Glow / Highlight API ─────────────────────────────────────────────────────

## Highlight all cards that are legal targets for an effect.
func highlight_targetable(targets: Array[CardInstance]) -> void:
	clear_all_glows()
	for card in targets:
		var view = _card_views.get(card.instance_id, null)
		if view:
			view.set_glow(CardView.GlowState.TARGETABLE)

## Highlight cards the player can activate.
func highlight_activatable(cards: Array[CardInstance]) -> void:
	for card in cards:
		var view = _card_views.get(card.instance_id, null)
		if view:
			view.set_glow(CardView.GlowState.ACTIVATABLE)

## Remove all glow states.
func clear_all_glows() -> void:
	for view in _card_views.values():
		view.set_glow(CardView.GlowState.NONE)

## Highlight a specific card as selected.
func select_card(card: CardInstance) -> void:
	if _selected_view != null:
		_selected_view.set_selected(false)
	var view = _card_views.get(card.instance_id, null)
	if view:
		view.set_selected(true)
		_selected_view = view

func deselect_all() -> void:
	if _selected_view != null:
		_selected_view.set_selected(false)
		_selected_view = null

# ─── HUD Update API ───────────────────────────────────────────────────────────

func update_lp(player: Player, lp: int) -> void:
	if player == players[0]:
		_p1_lp_label.text = "P1 LP: %d" % lp
	else:
		_p2_lp_label.text = "P2 LP: %d" % lp

func update_phase(phase_name: String, turn: int, active_player: int) -> void:
	_phase_label.text = phase_name
	_turn_label.text  = "Turn %d — Player %d" % [turn, active_player]

func update_chain_hud(links: Array) -> void:
	## Rebuild the chain display
	for child in _chain_hud.get_children():
		child.queue_free()

	var x := 0.0
	for link in links:
		var cl: ChainLink = link
		var lbl := Label.new()
		lbl.text     = "CL%d\n%s" % [cl.chain_index, cl.effect.effect_name.left(10)]
		lbl.position = Vector2(x, 0)
		lbl.size     = Vector2(60, 50)
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.modulate = Color(0.8, 0.6, 1.0)
		_chain_hud.add_child(lbl)
		x += 64.0

# ─── ZoneManager Signal Handlers ─────────────────────────────────────────────

func _on_card_moved(
	card: CardInstance,
	_from: Zone,
	to_zone: Zone,
	reason: ZoneManager.MoveReason
) -> void:
	var view := get_or_create_card_view(card)
	if _from != null and _from.zone_type ==  Zone.ZoneType.HAND:
		if view.get_parent() ==self:
			remove_child(view)
		refresh_hand(_from.owner)
	# Flip logic
	match to_zone.zone_type:
		Zone.ZoneType.GRAVEYARD, Zone.ZoneType.HAND:
			if to_zone.zone_type == Zone.ZoneType.HAND and to_zone.owner != players[0]:
				view.flip_to(false)
			else:
				view.flip_to(true)
		Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK:
			view.flip_to(false)
		Zone.ZoneType.MAIN_MONSTER, Zone.ZoneType.EXTRA_MONSTER, Zone.ZoneType.MAIN_SPELL:
			if reason == ZoneManager.MoveReason.SET:
				view.flip_to(false)
			elif reason in [ZoneManager.MoveReason.NORMAL_SUMMON,
							ZoneManager.MoveReason.SPECIAL_SUMMON,
							ZoneManager.MoveReason.FLIP_SUMMON]:
				view.flip_to(true)

	# Remove from old zone view
	for zv in _slot_views.values():
		if zv.get_card_view() == view:
			zv.remove_card(false)
			break
	for zv in _pile_views.values():
		if zv.get_card_view() == view:
			zv.remove_card(false)
			break

	# Place in new zone view
	if to_zone.zone_type in Zone.FIELD_ZONE_TYPES:
		var pid   := "p%d" % card.controller.player_id
		var slot  := card.slot_index
		var key   := "%s_%s_%d" % [pid, _zone_type_key(to_zone.zone_type), slot]
		var zv: ZoneView = _slot_views.get(key, null)
		if zv != null:
			zv.place_card(view)
	elif to_zone.zone_type in [Zone.ZoneType.GRAVEYARD, Zone.ZoneType.BANISHED,
								Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK]:
		var pv: ZoneView = _pile_views.get(str(to_zone.zone_id), null)
		if pv != null:
			pv.place_card(view, false)
			pv.set_count(to_zone.count())
	elif to_zone.zone_type == Zone.ZoneType.HAND:
		# Hand is laid out separately
		if view.get_parent() != null and view.get_parent() != self:
			view.reparent(self)
		elif view.get_parent() == null:
			add_child(view)
		refresh_hand(card.controller)

func _on_zone_changed(zone: Zone) -> void:
	# Update pile count badges
	var key := str(zone.zone_id)
	var pv: ZoneView = _pile_views.get(key, null)
	if pv != null:
		pv.set_count(zone.count())

# ─── EffectStack Signal Handlers ──────────────────────────────────────────────

func _on_chain_link_pushed(link: ChainLink) -> void:
	var view = _card_views.get(link.source_card.instance_id, null)
	if view:
		view.set_glow(CardView.GlowState.CHAIN_LINK)
	update_chain_hud(effect_stack.links)

func _on_chain_link_resolved(link: ChainLink, was_negated: bool) -> void:
	var view = _card_views.get(link.source_card.instance_id, null)
	if view:
		view.set_glow(CardView.GlowState.NONE)

func _on_chain_resolved(_links: Array) -> void:
	update_chain_hud([])
	clear_all_glows()

func _on_priority_passed(to_player: Player) -> void:
	_turn_label.modulate = Color(1.0, 0.9, 0.3) if to_player == players[0] else Color(0.9, 0.4, 0.4)

func _on_triggers_pending(triggers: Array) -> void:
	## In a full game, show a popup. For now, auto-decline all optional triggers.
	var choices := {}
	for t in triggers:
		choices[t] = false
	effect_stack.confirm_optional_triggers(choices)

# ─── Input Handlers ───────────────────────────────────────────────────────────

func _on_card_clicked(view: CardView, card: CardInstance) -> void:
	## Route the click through the pending-action state machine first.
	## If we're waiting for a target, this click IS the target selection.
	match _pending_state:
		PendingState.AWAIT_ATTACK_TARGET:
			_complete_attack(card)
			return
		PendingState.AWAIT_EFFECT_TARGET:
			_collect_effect_target(card)
			return

	## Not in a pending state — show tooltip for local player's cards only.
	if card.controller != local_player:
		
		card_inspect_requested.emit(card)
		return

	## Build the legal action list from GameDirector if available,
	## otherwise fall back to a static set for testing without a director.
	var actions: Array[CardTooltip.Action] = []
	if game_director != null:
		actions = game_director.tooltip_actions_for(card, local_player)
	else:
		## Fallback for TestBoard without a wired GameDirector
		if card.is_in_hand():
			if card.definition.is_monster():
				actions.append(CardTooltip.Action.SUMMON)
			actions.append(CardTooltip.Action.SET)
			if not card.definition.effects.is_empty():
				actions.append(CardTooltip.Action.ACTIVATE)
		elif card.is_on_field():
			if card.definition.is_monster():
				actions.append(CardTooltip.Action.ATTACK)
			if not card.definition.effects.is_empty():
				actions.append(CardTooltip.Action.ACTIVATE)
		actions.append(CardTooltip.Action.INSPECT)

	_tooltip.show_for(card, actions, view.global_position, view.size)
	card_clicked.emit(card, view)

func _on_card_inspected(view: CardView, card: CardInstance) -> void:
	_cancel_pending()
	card_inspect_requested.emit(card)

func _on_empty_slot_clicked(zone_view: ZoneView) -> void:
	_cancel_pending()
	empty_zone_clicked.emit(zone_view.zone, zone_view.slot_index)
# ─── Tooltip Action Routing ───────────────────────────────────────────────────

func _on_tooltip_action(action: int, card: CardInstance) -> void:
	match action:
		CardTooltip.Action.SUMMON:
			_do_summon(card)
		CardTooltip.Action.SET:
			_do_set(card)
		CardTooltip.Action.ACTIVATE:
			_begin_activate_flow(card)
		CardTooltip.Action.ATTACK:
			_begin_attack_flow(card)
		CardTooltip.Action.INSPECT:
			card_inspect_requested.emit(card)

# ─── Summon ───────────────────────────────────────────────────────────────────

func _do_summon(card: CardInstance) -> void:
	if game_director == null:
		return
	## Tribute selection handled by InputRequest flow in GameDirector.
	## For non-tribute monsters, fire immediately.
	if not card.definition.requires_tribute():
		game_director.normal_summon(local_player, card)
		refresh_hand(local_player)
		return

	## Tribute required — highlight valid tribute targets and wait.
	## For now submit with empty tributes; GameDirector will emit
	## an InputRequest if tributes are needed.
	game_director.normal_summon(local_player, card)
	refresh_hand(local_player)

# ─── Set ──────────────────────────────────────────────────────────────────────

func _do_set(card: CardInstance) -> void:
	if game_director == null:
		return
	game_director.set_card(local_player, card)
	refresh_hand(local_player)

# ─── Attack Flow ──────────────────────────────────────────────────────────────

func _begin_attack_flow(attacker: CardInstance) -> void:
	if game_director == null:
		return

	## Find all legal targets for this attacker
	var la      := game_director.legal_actions_for(local_player)
	var targets := la.attack_targets_for(attacker)

	if targets.is_empty():
		return

	## Direct attack — no target needed
	if targets.size() == 1 and targets[0] == null:
		game_director.declare_attack(local_player, attacker, null)
		return

	## Multiple targets — enter waiting state and highlight them
	_pending_state = PendingState.AWAIT_ATTACK_TARGET
	_pending_card  = attacker

	clear_all_glows()
	select_card(attacker)

	for target in targets:
		if target == null:
			continue
		var view := _card_views.get(target.instance_id, null)
		if view:
			view.set_glow(CardView.GlowState.TARGETABLE)

	_show_cancel_hint("Select a target to attack, or press Escape to cancel.")

func _complete_attack(target: CardInstance) -> void:
	## Verify the clicked card is actually a valid target
	var la      := game_director.legal_actions_for(local_player)
	var targets := la.attack_targets_for(_pending_card)

	if target not in targets:
		## Clicked an invalid card — cancel
		_cancel_pending()
		return

	var attacker := _pending_card
	_cancel_pending()
	game_director.declare_attack(local_player, attacker, target)

# ─── Effect Activation Flow ───────────────────────────────────────────────────

func _begin_activate_flow(card: CardInstance) -> void:
	if game_director == null:
		return

	## Find the first activatable effect on this card
	var la       := game_director.legal_actions_for(local_player)
	var eff_list := la.activatable_effects_for(card)

	if eff_list.is_empty():
		return

	## If the card has more than one activatable effect, pick the first for now.
	## A future improvement would show a sub-menu to choose which effect.
	var eff_idx: int           = eff_list[0]
	var eff: EffectDefinition  = card.definition.effects[eff_idx]

	## No targeting required — activate immediately
	if eff.targets_required == 0:
		game_director.activate_effect(local_player, card, eff_idx, [])
		return

	## Targeting required — highlight candidates and wait for clicks
	var candidates := RuleEngine.get_legal_targets(eff, local_player, zone_manager)
	if candidates.size() < eff.targets_required:
		## Not enough targets — shouldn't happen if LegalActions is correct,
		## but guard anyway
		return

	_pending_state      = PendingState.AWAIT_EFFECT_TARGET
	_pending_card       = card
	_pending_effect_idx = eff_idx
	_pending_targets.clear()
	_targets_needed     = eff.targets_required

	clear_all_glows()
	select_card(card)

	for candidate in candidates:
		var view := _card_views.get(candidate.instance_id, null)
		if view:
			view.set_glow(CardView.GlowState.TARGETABLE)

	_show_cancel_hint("Select %d target%s, or press Escape to cancel." % [
		eff.targets_required,
		"s" if eff.targets_required > 1 else ""
	])

func _collect_effect_target(card: CardInstance) -> void:
	## Check this card is actually a highlighted target
	var view := _card_views.get(card.instance_id, null)
	if view == null or view.glow_state != CardView.GlowState.TARGETABLE:
		## Clicked a non-target — cancel
		_cancel_pending()
		return

	_pending_targets.append(card)
	view.set_glow(CardView.GlowState.TARGETED)

	if _pending_targets.size() >= _targets_needed:
		## All targets selected — fire the effect
		var source  := _pending_card
		var eff_idx := _pending_effect_idx
		var targets := _pending_targets.duplicate()
		_cancel_pending()
		game_director.activate_effect(local_player, source, eff_idx, targets)

# ─── Pending State Helpers ────────────────────────────────────────────────────

func _cancel_pending() -> void:
	_pending_state      = PendingState.NONE
	_pending_card       = null
	_pending_effect_idx = -1
	_pending_targets.clear()
	_targets_needed     = 0
	deselect_all()
	clear_all_glows()
	_hide_cancel_hint()

func _show_cancel_hint(text: String) -> void:
	if _turn_label != null:
		_turn_label.text    = text
		_turn_label.modulate = Color(1.0, 0.8, 0.3)

func _hide_cancel_hint() -> void:
	if _turn_label != null:
		_turn_label.modulate = Color(0.7, 0.7, 0.7)

# ─── Keyboard Cancel ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and _pending_state != PendingState.NONE:
			_cancel_pending()
			get_viewport().set_input_as_handled()
# ─── Helpers ──────────────────────────────────────────────────────────────────

func _zone_type_key(type: Zone.ZoneType) -> String:
	match type:
		Zone.ZoneType.MAIN_MONSTER:  return "main_monster"
		Zone.ZoneType.MAIN_SPELL:    return "main_spell"
		Zone.ZoneType.EXTRA_MONSTER: return "extra_monster"
		Zone.ZoneType.FIELD_SPELL:   return "field_spell"
	return "unknown"


# ──────────────────────────────────────────────────────────────────────────────
# Inner class: field divider / centre line drawing
# ──────────────────────────────────────────────────────────────────────────────

class _FieldDivider extends Control:
	func _draw() -> void:
		var W := size.x
		var mid := size.y / 2.0

		# Centre divider glow
		draw_line(Vector2(0, mid), Vector2(W, mid), Color(0.3, 0.5, 0.8, 0.15), 40.0)
		draw_line(Vector2(0, mid), Vector2(W, mid), Color(0.4, 0.6, 1.0, 0.35), 2.0)

		# Faint corner triangles (field feel)
		draw_line(Vector2(0, 0), Vector2(W, 0), Color(0.15, 0.20, 0.35, 0.3), 1.0)
		draw_line(Vector2(0, size.y), Vector2(W, size.y), Color(0.15, 0.20, 0.35, 0.3), 1.0)
