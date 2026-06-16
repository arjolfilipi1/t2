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
const ZoneViewScene = preload("res://ui/board/ZoneView.tscn")
# ─── Signals ──────────────────────────────────────────────────────────────────
# ─── Scene Node References ────────────────────────────────────────────────
@onready var background: ColorRect = $Background
@onready var field_divider: Control = $FieldDivider
@onready var p1_lp_label: Label = $P1_InfoBar/P1_LP
@onready var p2_lp_label: Label = $P2_InfoBar/P2_LP
@onready var phase_label: Label = $HUD_Bar/PhaseLabel
@onready var turn_label: Label = $HUD_Bar/TurnLabel
@onready var pass_button: Button = $HUD_Bar/PassButton
@onready var end_button: Button = $HUD_Bar/EndButton
@onready var draw_button: Button = $"HUD_Bar/Draw Button"
@onready var chain_hud: Panel = $ChainDisplay
@onready var tooltip: CardTooltip = $CardTooltip

# ─── Zone Containers (to be populated dynamically) ────────────────────────
@onready var p1_monster_zone: GridContainer = $Zones/P1/P1_Monsters
@onready var p1_spell_zone: GridContainer = $Zones/P1/P1_Spells
@onready var p1_field_spell: Control = $Zones/P1/P1_FieldSpell
@onready var p1_extra_monster: Control = $Zones/P1/P1_ExtraMonster
@onready var p1_graveyard_zone: Control = $Zones/P1/P1_GraveyardPile
@onready var p1_banished: Control = $Zones/P1/P1_BanishedPile
@onready var p1_deck: Control = $Zones/P1/P1_DeckPile
@onready var p1_extra_deck: Control = $Zones/P1/P1_ExtraDeckPile

@onready var p2_monster_zone: GridContainer = $Zones/P2/P2_Monsters
@onready var p2_spell_zone: GridContainer = $Zones/P2/P2_Spells
@onready var p2_field_spell: Control = $Zones/P2/P2_FieldSpell
@onready var p2_extra_monster: Control = $Zones/P2/P2_ExtraMonster
@onready var p2_graveyard_zone: Control = $Zones/P2/P2_GraveyardPile
@onready var p2_banished: Control = $Zones/P2/P2_BanishedPile
@onready var p2_deck: Control = $Zones/P2/P2_DeckPile
@onready var p2_extra_deck: Control = $Zones/P2/P2_ExtraDeckPile
#add the info bar buttons for click handling
@onready var p1_deck_button: Button = $P1_InfoBar/P1_Deck
#@onready var p1_extra_button: Button = $P1_InfoBar/P1_Extra
@onready var p1_gy_button: Button = $P1_InfoBar/P1_Graveyard
@onready var p1_banish_button: Button = $P1_InfoBar/P1_Banished

@onready var p2_deck_button: Button = $P2_InfoBar/P2_Deck
#@onready var p2_extra_button: Button = $P2_InfoBar/P2_Extra
@onready var p2_gy_button: Button = $P2_InfoBar/P2_Graveyard
@onready var p2_banish_button: Button = $P2_InfoBar/P2_Banished

@onready var p1_graveyard: Button = $P1_InfoBar/P1_Graveyard
@onready var p2_graveyard: Button = $P2_InfoBar/P2_Graveyard
## Player clicked a card (intent determined by current game state).
signal card_clicked(card: CardInstance, view: CardView)
signal pass_priority_requested()
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
		AWAIT_ZONE_SELECTION,
}
var _pending_state:       PendingState  = PendingState.NONE
var _pending_card:        CardInstance  = null   ## Card whose action is pending
var _pending_effect_idx:  int           = -1     ## Effect index for AWAIT_EFFECT_TARGET
var _pending_targets:     Array[CardInstance] = []
var _targets_needed:      int           = 0
var _pending_action_type: String = "" # "summon", "set", "activate"
var _pending_slot_callback: Callable = Callable() # Called with selected slot index
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

# ─── Setup ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	print("p1_lp_label:",p1_lp_label)
	#_build_field_background()
	_connect_info_bar_buttons
func _enter_tree() -> void:
	print("te:p1_lp_label:",p1_lp_label)

func setup(
		zm:          ZoneManager,
		stack:       EffectStack,
		player_list: Array[Player],
		gd:          GameDirector = null
) -> void:
	
	zone_manager = zm
	effect_stack = stack
	players      = player_list
	print(players)
	game_director = gd
	local_player  = player_list[0]

	if pass_button:
		pass_button.pressed.connect(func():pass_priority_requested.emit())
	if end_button:
		end_button.pressed.connect(func():phase_advance_requested.emit())
	if draw_button:
		draw_button.pressed.connect(func():draw_requested.emit())
	if tooltip:
		tooltip.action_selected.connect(_on_tooltip_action)
	# Connect to ZoneManager
	zone_manager.card_moved.connect(_on_card_moved)
	zone_manager.zone_changed.connect(_on_zone_changed)

	# Connect to EffectStack
	effect_stack.chain_link_pushed.connect(_on_chain_link_pushed)
	effect_stack.chain_link_resolved.connect(_on_chain_link_resolved)
	effect_stack.chain_resolved.connect(_on_chain_resolved)
	effect_stack.priority_passed.connect(_on_priority_passed)
	effect_stack.triggers_pending.connect(_on_triggers_pending)
	_build_zone_views_from_scene()


func _clear_container(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is ZoneView:
			child.queue_free()
# Create a new method to use scene containers
func _build_zone_views_from_scene() -> void:
	# Clear existing views if any
	
	for player in players:
		var is_p1 := player == players[0]
		var monster_grid = p1_monster_zone if is_p1 else p2_monster_zone
		var spell_grid = p1_spell_zone if is_p1 else p2_spell_zone
		var field_spell_container = p1_field_spell if is_p1 else p2_field_spell
		var extra_monster_container = p1_extra_monster if is_p1 else p2_extra_monster
		var gy_container = p1_graveyard_zone if is_p1 else p2_graveyard_zone
		var banished_container = p1_banished if is_p1 else p2_banished
		var deck_container = p1_deck if is_p1 else p2_deck
		var extra_deck_container = p1_extra_deck if is_p1 else p2_extra_deck

		var pid := "p%d" % player.player_id
		# Clear existing children
		_clear_container(monster_grid)
		_clear_container(spell_grid)
		_clear_container(field_spell_container)
		_clear_container(extra_monster_container)
		_clear_container(gy_container)
		_clear_container(banished_container)
		_clear_container(deck_container)
		_clear_container(extra_deck_container)

		# Create 5 monster slot ZoneViews
		for i in 5:
			var zv := ZoneViewScene.instantiate()
			monster_grid.add_child(zv)
			zv.setup(zone_manager.monster_zone_of(player), i, "M%d_%s" % [i,pid])
			zv.empty_slot_clicked.connect(_on_empty_slot_clicked)
			_slot_views["%s_main_monster_%d" % [pid, i]] = zv
		
		# Create 5 spell/trap slot ZoneViews
		for i in 5:
			var zv := ZoneViewScene.instantiate()
			spell_grid.add_child(zv)
			zv.setup(zone_manager.spell_zone_of(player), i, "S%d_%s" % [i,pid])
			zv.empty_slot_clicked.connect(_on_empty_slot_clicked)
			_slot_views["%s_main_spell_%d" % [pid, i]] = zv
# ─── Zone View Construction ───────────────────────────────────────────────────
		# Field Spell Zone
		var fs_zv := ZoneViewScene.instantiate()
		field_spell_container.add_child(fs_zv)
		fs_zv.setup(zone_manager.field_spell_zone_of(player), 0, "FIELD")
		fs_zv.empty_slot_clicked.connect(_on_empty_slot_clicked)
		_slot_views["%s_field_spell_0" % pid] = fs_zv
		# Extra Deck Pile
		var extra_zv := ZoneViewScene.instantiate()
		extra_deck_container.add_child(extra_zv)
		extra_zv.setup(zone_manager.extra_deck_of(player), -1, "EXTRA")
		_pile_views["%s_extra_deck" % pid] = extra_zv
		# Graveyard Pile
		var gy_zv := ZoneViewScene.instantiate()
		gy_container.add_child(gy_zv)
		gy_zv.setup(zone_manager.graveyard_of(player), -1, "GY")
		_pile_views["%s_graveyard" % pid] = gy_zv
		# Banished Pile
		var ban_zv := ZoneViewScene.instantiate()
		banished_container.add_child(ban_zv)
		ban_zv.setup(zone_manager.banished_of(player), -1, "BANISH")
		_pile_views["%s_banished" % pid] = ban_zv
		# Deck Pile
		var deck_zv := ZoneViewScene.instantiate()
		deck_container.add_child(deck_zv)
		deck_zv.setup(zone_manager.deck_of(player), -1, "DECK")
		_pile_views["%s_deck" % pid] = deck_zv



# ─── HUD Construction ─────────────────────────────────────────────────────────


func _make_lp_label(text: String, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = pos
	lbl.size     = Vector2(160, 22)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.95, 0.9, 0.6)
	add_child(lbl)
	return lbl


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
func reveal_hand(player: Player,zm:ZoneManager= zone_manager) -> void:
	if not zone_manager:
		zone_manager = zm
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
		p1_lp_label.text = "P1 LP: %d" % lp
	else:
		p2_lp_label.text = "P2 LP: %d" % lp

func update_phase(phase_name: String, turn: int, active_player: int) -> void:
	phase_label.text = phase_name
	turn_label.text  = "Turn %d — Player %d" % [turn, active_player]

func update_chain_hud(links: Array) -> void:
	if not chain_hud:
		return
	for child in chain_hud.get_children():
		child.queue_free()
	
	var chain_links_container = chain_hud.get_node_or_null("ChainLinks")
	if not chain_links_container:
		return
		
	var x := 0.0
	for link in links:
		var cl: ChainLink = link
		var lbl := Label.new()
		lbl.text = "CL%d\n%s" % [cl.chain_index, cl.effect.effect_name.left(10)]
		lbl.position = Vector2(x, 0)
		lbl.size = Vector2(60, 50)
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.modulate = Color(0.8, 0.6, 1.0)
		chain_links_container.add_child(lbl)
		x += 64.0


# ─── ZoneManager Signal Handlers ─────────────────────────────────────────────

func _on_card_moved(
	card: CardInstance,
	_from: Zone,
	to_zone: Zone,
	reason: ZoneManager.MoveReason
) -> void:
	var view := get_or_create_card_view(card)
	view.kill_all_tweens()
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
			view.kill_all_tweens()
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
	pass_button.visible = false
func _on_priority_passed(to_player: Player) -> void:
	turn_label.modulate = Color(1.0, 0.9, 0.3) if to_player == players[0] else Color(0.9, 0.4, 0.4)
	# Show pass button only when local player holds priority on open chain
	pass_button.visible = (to_player == players[0] )

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

	tooltip.show_for(card, actions, view.global_position, view.size)
	card_clicked.emit(card, view)

func _on_card_inspected(view: CardView, card: CardInstance) -> void:
	_cancel_pending()
	card_inspect_requested.emit(card)

func _on_empty_slot_clicked(zone_view: ZoneView) -> void:
	# Check if we're waiting for zone selection
	print(zone_view.zone_label)
	if _pending_state == PendingState.AWAIT_ZONE_SELECTION:
		print("AWAIT_ZONE_SELECTION")
		_complete_zone_selection(zone_view)
		return
	
	# Normal empty zone click (not during pending action)
	_cancel_pending()
	empty_zone_clicked.emit(zone_view.zone, zone_view.slot_index)

func _complete_zone_selection(zone_view: ZoneView) -> void:
	var slot := zone_view.slot_index
	var zone := zone_view.zone
	
	# Validate the zone is appropriate for the action
	match _pending_action_type:
		"summon":
			if zone.zone_type != Zone.ZoneType.MAIN_MONSTER:
				_show_error("Invalid zone for summon!")
				return
			game_director.normal_summon(local_player, _pending_card, [], slot)
			refresh_hand(local_player)
		
		"set":
			var expected_type = Zone.ZoneType.MAIN_MONSTER if _pending_card.definition.is_monster() else Zone.ZoneType.MAIN_SPELL
			if zone.zone_type != expected_type:
				_show_error("Invalid zone for set!")
				return
			game_director.set_card(local_player, _pending_card, slot)
			refresh_hand(local_player)
		
		"activate":
			# For activation, you might want to place continuous spells/traps in specific slots
			game_director.activate_effect(local_player, _pending_card, 0, [])
	
	_cancel_pending()
func _show_error(message: String) -> void:
	print("Error: %s" % message)
	# Optional: Show a temporary error label
	if turn_label:
		var old_text = turn_label.text
		turn_label.text = message
		turn_label.modulate = Color(1.0, 0.3, 0.3)
		await get_tree().create_timer(1.5).timeout
		turn_label.text = old_text
		turn_label.modulate = Color(0.7, 0.7, 0.7)
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
	 # Check if zone selection is needed
	var monster_zone := zone_manager.monster_zone_of(local_player)
	var empty_slots := monster_zone.empty_slot_count()
	
	if empty_slots == 0:
		print("No empty monster zones!")
		return
	
	if empty_slots == 1:
		# Only one choice - place it automatically
		game_director.normal_summon(local_player, card, [], monster_zone.first_empty_slot())
		refresh_hand(local_player)
		return
	
	# Multiple empty zones - ask player to choose
	_pending_state = PendingState.AWAIT_ZONE_SELECTION
	_pending_card = card
	_pending_action_type = "summon"
	
	# Highlight empty monster zones
	clear_all_glows()
	clear_zone_highlights()
	highlight_empty_zones(Zone.ZoneType.MAIN_MONSTER, local_player, true)
	
	_show_cancel_hint("Click on an empty monster zone to summon %s" % card.definition.card_name)

# ─── Set ──────────────────────────────────────────────────────────────────────

func _do_set(card: CardInstance) -> void:
	if game_director == null:
		return
	
	var target_zone: Zone
	var zone_type: Zone.ZoneType
	
	if card.definition.is_monster():
		target_zone = zone_manager.monster_zone_of(local_player)
		zone_type = Zone.ZoneType.MAIN_MONSTER
	else:
		target_zone = zone_manager.spell_zone_of(local_player)
		zone_type = Zone.ZoneType.MAIN_SPELL
	
	var empty_slots := target_zone.empty_slot_count()
	
	if empty_slots == 0:
		print("No empty zones!")
		return
	
	if empty_slots == 1:
		game_director.set_card(local_player, card, target_zone.first_empty_slot())
		refresh_hand(local_player)
		return
	
	# Multiple empty zones - ask player to choose
	_pending_state = PendingState.AWAIT_ZONE_SELECTION
	_pending_card = card
	_pending_action_type = "set"
	
	clear_all_glows()
	clear_zone_highlights()
	highlight_empty_zones(zone_type, local_player, true)
	
	_show_cancel_hint("Click on an empty %s zone to set %s" % 
		["monster" if card.definition.is_monster() else "spell/trap", 
		 card.definition.card_name])

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
	# If activating a Continuous Spell/Trap from hand, need to place it first
	if card.is_in_hand() and card.definition.is_spell() and card.definition.spell_type == CardDefinition.SpellType.CONTINUOUS:
		_pending_state = PendingState.AWAIT_ZONE_SELECTION
		_pending_card = card
		_pending_action_type = "activate"
		
		clear_all_glows()
		clear_zone_highlights()
		highlight_empty_zones(Zone.ZoneType.MAIN_SPELL, local_player, true)
		_show_cancel_hint("Click on an empty spell/trap zone to place %s" % card.definition.card_name)
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
func highlight_empty_zones(zone_type: Zone.ZoneType, player: Player, highlight: bool) -> void:
	var pid := "p%d" % player.player_id
	
	match zone_type:
		Zone.ZoneType.MAIN_MONSTER:
			for i in range(5):
				var key := "%s_main_monster_%d" % [pid, i]
				var zv: ZoneView = _slot_views.get(key, null)
				if zv and zv.is_empty():
					zv.set_drop_highlight(highlight)
		
		Zone.ZoneType.MAIN_SPELL:
			for i in range(5):
				var key := "%s_main_spell_%d" % [pid, i]
				var zv: ZoneView = _slot_views.get(key, null)
				if zv and zv.is_empty():
					zv.set_drop_highlight(highlight)
		
		Zone.ZoneType.FIELD_SPELL:
			var key := "%s_field_spell_0" % pid
			var zv: ZoneView = _slot_views.get(key, null)
			if zv and zv.is_empty():
				zv.set_drop_highlight(highlight)

## Clear all zone highlights
func clear_zone_highlights() -> void:
	for zv in _slot_views.values():
		zv.set_drop_highlight(false)
func _cancel_pending() -> void:
	_pending_state      = PendingState.NONE
	_pending_card       = null
	_pending_action_type = ""
	_pending_effect_idx = -1
	_pending_targets.clear()
	_targets_needed     = 0
	deselect_all()
	clear_all_glows()
	clear_zone_highlights()
	_hide_cancel_hint()

func _show_cancel_hint(text: String) -> void:
	if turn_label != null:
		turn_label.text    = text
		turn_label.modulate = Color(1.0, 0.8, 0.3)

func _hide_cancel_hint() -> void:
	if turn_label != null:
		turn_label.modulate = Color(0.7, 0.7, 0.7)

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
func _connect_info_bar_buttons() -> void:
	await get_tree().process_frame
	# P1 buttons
	if p1_deck_button:
		print("deck")
		p1_deck_button.pressed.connect(func(): _on_pile_clicked(players[0], "deck"))
	#if p1_extra_button:
		#p1_extra_button.pressed.connect(func(): _on_pile_clicked(players[0], "extra"))
	if p1_gy_button:
		p1_gy_button.pressed.connect(func(): _on_pile_clicked(players[0], "graveyard"))
	if p1_banish_button:
		p1_banish_button.pressed.connect(func(): _on_pile_clicked(players[0], "banished"))
	
	# P2 buttons
	if p2_deck_button:
		p2_deck_button.pressed.connect(func(): _on_pile_clicked(players[1], "deck"))
	##if p2_extra_button:
		#p2_extra_button.pressed.connect(func(): _on_pile_clicked(players[1], "extra"))
	if p2_gy_button:
		p2_gy_button.pressed.connect(func(): _on_pile_clicked(players[1], "graveyard"))
	if p2_banish_button:
		p2_banish_button.pressed.connect(func(): _on_pile_clicked(players[1], "banished"))

func _on_pile_clicked(player: Player, pile_type: String) -> void:
	print("Clicked on %s's %s pile" % [player.display_name, pile_type])
	# You can implement a popup showing the pile contents here
	var zone: Zone
	match pile_type:
		"deck":
			zone = zone_manager.deck_of(player)
		"extra":
			zone = zone_manager.extra_deck_of(player)
		"graveyard":
			zone = zone_manager.graveyard_of(player)
		"banished":
			zone = zone_manager.banished_of(player)
	
	if zone:
		print("  Contains %d cards" % zone.count())
		# Emit signal to show pile viewer
		# pile_view_requested.emit(player, pile_type, zone.get_cards())


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
