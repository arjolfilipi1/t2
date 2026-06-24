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
const _CardSelectorScene := preload("res://ui/card/CardSelector.tscn")
var _card_selector: CardSelector = null
const _PileViewerScene = preload("res://ui/card/PileViewer.tscn")
var _pile_viewer: PileViewer = null

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
@onready var hands_container: Control = $Hands
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
		AWAIT_TRIBUTE_SELECTION, ## Player clicked Summon on a tribute monster; waiting for tribute card(s)
		AWAIT_DISCARD_SELECTION, ## Hand limit exceeded at End Phase; waiting for discard choice(s)
}
var _pending_state:       PendingState  = PendingState.NONE
var _pending_card:        CardInstance  = null   ## Card whose action is pending
var _pending_effect_idx:  int           = -1     ## Effect index for AWAIT_EFFECT_TARGET
var _pending_targets:     Array[CardInstance] = []
var _targets_needed:      int           = 0
var _pending_action_type: String = "" # "summon", "set", "activate"
var _pending_tributes:    Array[CardInstance] = []   ## Accumulated tribute choices
var _tributes_needed:     int           = 0
var _pending_discards:    Array[CardInstance] = []   ## Accumulated discard choices
var _discards_needed:     int           = 0
var _pending_discard_request: InputRequest = null    ## Held so we can resolve it once enough are picked
var _pending_slot_callback: Callable = Callable() # Called with selected slot index
var _pending_battle_attacker: CardInstance = null
var _pending_battle_target: CardInstance = null
var _is_waiting_for_battle_resolution: bool = false
# ─── Effect Picker ────────────────────────────────────────────────────────────
var _active_arrows: Array[CurvedArrow] = []
var _arrow_layer: Node2D = null

# ─── Effect Picker ────────────────────────────────────────────────────────────
## Shown instead of jumping straight to targeting whenever a card has more
## than one currently activatable effect — lets the player choose which one.
const _EffectPickerScene := preload("res://ui/card/EffectPickerMenu.tscn")
var _effect_picker: EffectPickerMenu = null

# ─── Animation Queue ──────────────────────────────────────────────────────────
## All card animations — moves, destruction, summon, attack, effect activation
## and resolution — are routed through this queue so they always play in
## strict sequence and never visually overlap, regardless of how quickly the
## underlying domain signals fire.
var anim_queue: AnimationQueue = null


# ─── View Maps ────────────────────────────────────────────────────────────────

## ZoneView for each slotted zone slot: key = "p1_main_monster_0" etc.
var _slot_views: Dictionary = {}   ## String → ZoneView

## ZoneView for pile zones: key = "p1_graveyard" etc.
var _pile_views: Dictionary = {}   ## String → ZoneView

## CardView for each live card: key = instance_id
var _card_views: Dictionary = {}   ## int → CardView

## Currently selected CardView (for pending action highlight).
var _selected_view: CardView = null

# ─── Auto Pass ───────────────────────────────────────────────────────────────
## Auto-pass timer for when the player has no legal actions
var _auto_pass_timer: Timer = null
var _auto_pass_enabled: bool = true
var _auto_pass_delay: float = 1.0 # 1 second delay

## Tracks if we're waiting for an auto-pass
var _is_waiting_for_auto_pass: bool = false

#hand containers 
var _hand_manager_p1: HandManager = null
var _hand_manager_p2: HandManager = null
const HandManagerScene = preload("res://ui/hand/HandManager.tscn")


func _ready() -> void:
	custom_minimum_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	#_build_field_background()
	_connect_info_bar_buttons()
	_build_pile_viewer()
	_connect_pile_buttons()
	var board_area := Control.new()
	board_area.name = "BoardArea"
	board_area.layout_mode = 1
	board_area.anchors_preset = 15
	board_area.anchor_right = 1.0
	board_area.anchor_bottom = 1.0
	board_area.mouse_filter = Control.MOUSE_FILTER_STOP
	board_area.mouse_entered.connect(_on_board_area_entered)
	board_area.mouse_exited.connect(_on_board_area_exited)
	add_child(board_area)
	
	
func _on_board_area_entered() -> void:
	# Only hide P1's hand when mouse enters board
	if _hand_manager_p1 and not _hand_manager_p1._is_expanded:
		_hand_manager_p1.hide_hand()

func _on_board_area_exited() -> void:
	# Show P1's hand again when mouse leaves
	if _hand_manager_p1:
		_hand_manager_p1.show_hand()

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
	_setup_hands()
	_build_animation_queue()
	if pass_button:
		pass_button.pressed.connect(func():pass_priority_requested.emit())
	if end_button:
		end_button.pressed.connect(func():phase_advance_requested.emit())
	if draw_button:
		draw_button.pressed.connect(func():draw_requested.emit())
	if tooltip:
		tooltip.action_selected.connect(_on_tooltip_action)
	_build_effect_picker()
	
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
	# Connect to GameDirector for battle animation timing
	 # Setup auto-pass timer
	_build_card_selector()
	_setup_auto_pass_timer()
	if game_director != null:
			game_director.attack_declared.connect(_on_attack_declared)
			game_director.battle_resolved.connect(_on_battle_resolved)
			game_director.awaiting_input.connect(_on_awaiting_input)
			if game_director.undo_manager != null:
				game_director.undo_manager.snapshot_restored.connect(_on_snapshot_restored)

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
	if card.is_in_hand():
		var hand_manager = _hand_manager_p1 if card.controller == players[0] else _hand_manager_p2
		if hand_manager:
			var views = hand_manager.get_card_views()
			if views.has(card.instance_id):
				return views[card.instance_id]

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
	
	anim_queue.enqueue(func() -> Signal: return view.animate_destroy(), "destroy_view")
	anim_queue.enqueue_callback(func(): view.queue_free(), "free_view")
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
	var hand_zone = zone_manager.hand_of(player)
	if player == players[0]:
		_hand_manager_p1.refresh_hand(hand_zone)
		await get_tree().process_frame
		for child in _hand_manager_p1.hand_container.get_children():
				if child is CardView:
					child.flip_to(true, true)
	else:
		_hand_manager_p2.refresh_hand(hand_zone)
		await get_tree().process_frame
		for child in _hand_manager_p2.hand_container.get_children():
				if child is CardView:
					child.flip_to(false, true)
## Flip all hand cards face-down (on request).
func conceal_hand(player: Player) -> void:
	var hand_manager = _hand_manager_p1 if player == players[0] else _hand_manager_p2
	if hand_manager:
		for view in hand_manager.get_card_views().values():
			if view is CardView:
				view.flip_to(false)

func reveal_hand(player: Player) -> void:
	var hand_manager = _hand_manager_p1 if player == players[0] else _hand_manager_p2
	if hand_manager:
		for view in hand_manager.get_card_views().values():
			if view is CardView:
				view.flip_to(true)
# ─── Full Refresh (used after UndoManager restores a snapshot) ────────────────

## Re-derives every CardView's parent/position/face-state from the CURRENT
## ZoneManager state, with no animation. Required after UndoManager.undo()/
## redo() because restoring a snapshot writes data directly — it does NOT
## go through ZoneManager.move() and therefore never fires card_moved, so
## none of BoardView's normal incremental signal handlers run. This is the
## one place that's allowed to assume "the data is already correct, just
## make the screen match it."
func full_refresh() -> void:
		## 1) Empty every slot/pile view instantly — whatever they're currently
		##    showing may be stale or simply wrong after a restore.
		for zv in _slot_views.values():
				zv.remove_card(false)
		for zv in _pile_views.values():
				zv.remove_card(false)
		## 2) Walk every zone in the live ZoneManager and re-place each card.
		for zone in zone_manager._zones.values():
				for card in zone.get_cards():
						var view := get_or_create_card_view(card)
						_place_card_view_for_current_zone(view, card, zone)
		## 3) Hands are laid out separately from slot/pile views.
		for player in players:
				refresh_hand(player)
		## 4) HUD reads LP/phase directly off the domain objects too — restore
		##    wrote those fields without going through the normal signals that
		##    would have kept these labels in sync.
		for player in players:
				update_lp(player, player.life_points)
		if game_director != null and game_director.tm != null and game_director.tm.context != null:
				update_phase(
						game_director.tm.current_phase_name(),
						game_director.tm.current_turn(),
						game_director.tm.active_player().player_id
				)
		## 5) Glow/selection state from before the restore is meaningless now.
		clear_all_glows()
		deselect_all()
		clear_zone_highlights()
## Puts `view` into whichever ZoneView/parent matches `card`'s CURRENT zone,
## reparenting from wherever it previously lived if necessary. Mirrors the
## placement logic in _on_card_moved, but driven by current state rather
## than a from/to transition, and always instant (no animation, no queue).
func _place_card_view_for_current_zone(view: CardView, card: CardInstance, zone: Zone) -> void:
		view.flip_to(card.is_face_up(), true)   ## true = instant, no flip animation
		if zone.zone_type in Zone.FIELD_ZONE_TYPES:
				var pid  := "p%d" % card.controller.player_id
				var slot := card.slot_index
				var key  := "%s_%s_%d" % [pid, _zone_type_key(zone.zone_type), slot]
				var zv: ZoneView = _slot_views.get(key, null)
				if zv != null:
						zv.place_card(view, false)
				return
		if zone.zone_type in [Zone.ZoneType.GRAVEYARD, Zone.ZoneType.BANISHED,
												   Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK]:
				var pv: ZoneView = _pile_views.get(str(zone.zone_id), null)
				if pv != null:
						pv.place_card(view, false)
						pv.set_count(zone.count())
				return
		if zone.zone_type == Zone.ZoneType.HAND:
			if _card_views.has(card.instance_id):
				var view_t_d = _card_views[card.instance_id]
				_card_views.erase(card.instance_id)
				if view_t_d.get_parent() == self:
					view_t_d.queue_free()
			refresh_hand(card.controller)
				## refresh_hand() (called once per player after this loop) positions it.
# ─── Glow / Highlight API ─────────────────────────────────────────────────────
func highlight_summonable(cards: Array[CardInstance]) -> void:
	clear_all_glows()
	for card in cards:
		var view:CardView = _get_card_view(card)
		if view:
			view.set_glow(CardView.GlowState.SUMMONABLE)



## Highlight cards that are legal targets (Cyan)
func highlight_targetable(targets: Array[CardInstance]) -> void:
	clear_all_glows()
	for card in targets:
		var view = _get_card_view(card)
		if view:
			view.set_glow(CardView.GlowState.TARGETABLE)

## Highlight cards that can activate effects (Yellow/Orange)
func highlight_activatable(cards: Array) -> void:
	for card in cards:
		var view = _get_card_view(card)
		if view:
			view.set_glow(CardView.GlowState.ACTIVATABLE)

## Remove all glow states.
func clear_all_glows() -> void:
	for view in _card_views.values():
		view.set_glow(CardView.GlowState.NONE)
		 # Clear HandManager glows
	if _hand_manager_p1:
		for view in _hand_manager_p1.get_card_views().values():
			if view is CardView:
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
	update_legal_glows()
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

var delay_card: CardInstance
var delay_from: Zone
var delay_to_zone: Zone
var delay_reason: ZoneManager.MoveReason
# ─── ZoneManager Signal Handlers ─────────────────────────────────────────────
func delay_move()->Signal:
	print("delay fired")
	_on_card_moved(delay_card,delay_from,delay_to_zone,delay_reason)
	return anim_queue.attack_animation_complete
func _on_card_moved(
	card: CardInstance,
	_from: Zone,
	to_zone: Zone,
	reason: ZoneManager.MoveReason
) -> void:


	if reason == 8 and not _is_waiting_for_battle_resolution:
		
		delay_card    = card
		delay_from    = _from
		delay_to_zone = to_zone
		delay_reason  = reason
		print("move to grave delayed ",_is_waiting_for_battle_resolution)
		return
	var view := get_or_create_card_view(card)

	if to_zone.zone_type in Zone.FIELD_ZONE_TYPES or to_zone.zone_type == Zone.ZoneType.GRAVEYARD:
		view.reset_for_field()  
	# Flip logic — enqueued so it never overlaps a still-playing prior animation
	anim_queue.enqueue_callback(func():
		match to_zone.zone_type:
			Zone.ZoneType.GRAVEYARD, Zone.ZoneType.HAND:
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
	, "flip")

	# Remove from old zone view
	for zv in _slot_views.values():
		if zv.get_card_view() == view:
			zv.remove_card(false)
			break
	for zv in _pile_views.values():
		if zv.get_card_view() == view:
			zv.remove_card(false)
			break

	# Place in new zone view — placement itself is instant (re-parenting),
	# but the resulting summon/move animation is queued below.
	if to_zone.zone_type in Zone.FIELD_ZONE_TYPES:
		var pid   := "p%d" % card.controller.player_id
		var slot  := card.slot_index
		var key   := "%s_%s_%d" % [pid, _zone_type_key(to_zone.zone_type), slot]
		var zv: ZoneView = _slot_views.get(key, null)
		if zv != null:
			zv.place_card(view, false)   ## false = skip the built-in instant pop
			var is_summon := reason in [
				ZoneManager.MoveReason.NORMAL_SUMMON,
				ZoneManager.MoveReason.SPECIAL_SUMMON,
				ZoneManager.MoveReason.FLIP_SUMMON,
				ZoneManager.MoveReason.SET,
			]
			if is_summon:
				anim_queue.enqueue(func() -> Signal: return view.animate_summon(), "summon")
	elif to_zone.zone_type in [Zone.ZoneType.GRAVEYARD, Zone.ZoneType.BANISHED,
								Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK]:
		
		var pv: ZoneView = _pile_views.get(str(to_zone.zone_id), null)
		if pv != null:
			pv.place_card(view, false)
			pv.set_count(to_zone.count())
	elif to_zone.zone_type == Zone.ZoneType.HAND:
		# Hand is laid out separately - HandManager handles this
		# Don't reparent or add cards here!
		refresh_hand(card.controller)
		# Remove the view from any previous parent if needed
		if _card_views.has(card.instance_id):
			var stale_view = _card_views[card.instance_id]
			_card_views.erase(card.instance_id)
			if stale_view.get_parent() == self:
				stale_view.get_parent().remove_child(stale_view)


	if _from.zone_type == Zone.ZoneType.HAND:
		refresh_hand(card.controller)
func _on_zone_changed(zone: Zone) -> void:
	# Update pile count badges
	var key := str(zone.zone_id)
	var pv: ZoneView = _pile_views.get(key, null)
	if pv != null:
		pv.set_count(zone.count())

# ─── EffectStack Signal Handlers ──────────────────────────────────────────────

func _on_chain_link_pushed(link: ChainLink) -> void:
	var view := _card_views.get(link.source_card.instance_id, null)
	_cancel_auto_pass()
	if view:
		anim_queue.enqueue(func() -> Signal: return view.animate_effect_activate(), "activate")
	update_chain_hud(effect_stack.links)

func _on_chain_link_resolved(link: ChainLink, was_negated: bool) -> void:
	var view := _card_views.get(link.source_card.instance_id, null)
	_cancel_auto_pass()
	if view:
		if not was_negated:
			anim_queue.enqueue(func() -> Signal: return view.animate_effect_resolve(), "resolve")
		anim_queue.enqueue_callback(func(): view.set_glow(CardView.GlowState.NONE), "clear_glow")

func _on_chain_resolved(_links: Array) -> void:
	update_chain_hud([])
	clear_all_glows()
	pass_button.visible = false
func _on_priority_passed(to_player: Player) -> void:
	turn_label.modulate = Color(0.3, 0.9, 1.0) if to_player == players[0] else Color(0.9, 0.4, 0.4)
	# Show pass button only when local player holds priority on open chain
	pass_button.visible = (to_player != local_player )
	if to_player != local_player and _auto_pass_enabled:
		update_legal_glows()
		# Check if the player has ANY legal actions
		var has_actions = _check_player_has_actions()
		
		if not has_actions:
			# No actions - start auto-pass timer
			_start_auto_pass()
		else:
			# Has actions - cancel any pending auto-pass
			_cancel_auto_pass()
	else:
		# Priority is not ours - cancel auto-pass
		clear_all_glows()
		_cancel_auto_pass()
func _on_triggers_pending(triggers: Array) -> void:
	## In a full game, show a popup. For now, auto-decline all optional triggers.
	var choices := {}
	for t in triggers:
		choices[t] = false
	effect_stack.confirm_optional_triggers(choices)
# ─── GameDirector Battle Signal Handlers ──────────────────────────────────────

## Fires the instant the attack is validated, BEFORE damage is calculated.
## Plays the attacker's lunge and the defender's hit-flash in parallel, and
## ONLY THEN lets the queue continue to whatever destruction/LP feedback
## _on_battle_resolved enqueues — guaranteeing the player sees the strike
## before seeing its outcome.
func _on_attack_declared(attacker: CardInstance, target: CardInstance) -> void:
	_pending_battle_attacker = attacker
	_pending_battle_target = target
	_is_waiting_for_battle_resolution = true
	
	var attacker_view := _card_views.get(attacker.instance_id, null)
	if attacker_view == null:
		_resolve_pending_battle()  # Fallback
		return
	
	if target == null:
		# Direct attack
		var lp_anchor := p2_lp_label if attacker.controller == players[0] else p1_lp_label
		anim_queue.enqueue(
			func() -> Signal: return attacker_view.animate_attack_lunge(lp_anchor.global_position),
			"attack_lunge_direct"
		)
		anim_queue.enqueue(func() -> Signal: return delay_move(),"attack_complete")
	else:
		var target_view := _card_views.get(target.instance_id, null)
		if target_view == null:
			_resolve_pending_battle()  # Fallback
			return
		
		var target_center :Vector2= target_view.global_position + target_view.size / 2.0
		anim_queue.enqueue_parallel([
			func() -> Signal: return attacker_view.animate_attack_lunge(target_center),
			func() -> Signal: return target_view.animate_take_hit(),
		], "attack_clash")
		anim_queue.enqueue(func() -> Signal: return delay_move(),"attack_complete")
	# After the attack animations, resolve the battle
	# This ensures the queue processes the animations BEFORE resolving
	anim_queue.enqueue_callback(func(): 
		_resolve_pending_battle()
	, "resolve_battle_after_animation")
func _resolve_pending_battle() -> void:
	if _pending_battle_attacker == null or not _is_waiting_for_battle_resolution:
		return
	
	print("Resolving battle after animation: ", _pending_battle_attacker.definition.card_name)
	_is_waiting_for_battle_resolution = false
	
	var attacker = _pending_battle_attacker
	var target = _pending_battle_target
	
	_pending_battle_attacker = null
	_pending_battle_target = null
	
	if game_director == null:
		return
	
	# Create and submit the damage action
	var resolve_action := GameAction.ResolveBattleDamageAction.make(
		attacker.controller,
		attacker,
		target
	)
	game_director.submit_action(resolve_action)
func _on_attack_animation_complete()->void:
	_is_waiting_for_battle_resolution = false
func _build_animation_queue() -> void:
		anim_queue = AnimationQueue.new()
		anim_queue.attack_animation_complete.connect(_on_attack_animation_complete)
		add_child(anim_queue)
## Fires once LP damage and destruction have actually been applied to the
## domain. The destroyed-card visuals are NOT animated here — ZoneManager's
## move to the Graveyard (triggered inside ResolveBattleDamageAction.execute)
## already fires card_moved → _on_card_moved before this signal arrives,
## which enqueues that card's flip/placement animation. Animating destruction
## a second time here would duplicate it. This handler only needs to push
## the LP bar refresh into the queue so it lands after the clash visually.
func _on_battle_resolved(_result: RuleEngine.BattleResult) -> void:
	anim_queue.enqueue_callback(func():
		update_lp(players[0], players[0].life_points)
		update_lp(players[1], players[1].life_points)
	, "lp_refresh")
# ─── Input Handlers ───────────────────────────────────────────────────────────
	
func _build_effect_picker() -> void:
		_effect_picker = _EffectPickerScene.instantiate()
		add_child(_effect_picker)
		_effect_picker.effect_selected.connect(_on_effect_picked)
func _on_card_clicked(view: CardView, card: CardInstance) -> void:
	## Route the click through the pending-action state machine first.
	## If we're waiting for a target, this click IS the target selection.
	_cancel_auto_pass()
	match _pending_state:
		PendingState.AWAIT_ATTACK_TARGET:
			_complete_attack(card)
			return
		PendingState.AWAIT_EFFECT_TARGET:
			_collect_effect_target(card)
			return
		PendingState.AWAIT_TRIBUTE_SELECTION:
			_collect_tribute(card)
			return
		PendingState.AWAIT_DISCARD_SELECTION:
			_collect_discard(card)
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
	_cancel_auto_pass()
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
	
	match _pending_action_type:
		"summon":
			if zone.zone_type != Zone.ZoneType.MAIN_MONSTER:
				_show_error("Invalid zone for summon!")
				return
			game_director.normal_summon(local_player, _pending_card, [], slot)
			refresh_hand(local_player)
			_cancel_pending()
		
		"summon_from_hand":
			# Old flow - direct selection without card selector (single monster)
			if zone.zone_type != Zone.ZoneType.MAIN_MONSTER:
				_show_error("Invalid zone for summon!")
				return
			
			var card = _pending_targets[0] if not _pending_targets.is_empty() else null
			if card:
				_complete_summon_from_hand(card, slot)
			else:
				_show_error("No card selected to summon!")
				_cancel_pending()
		
		"summon_from_hand_selector_zone":  # ← NEW: Handle zone selection after selector
			if zone.zone_type != Zone.ZoneType.MAIN_MONSTER:
				_show_error("Invalid zone for summon!")
				return
			
			var card = _pending_targets[0] if not _pending_targets.is_empty() else null
			if card:
				_complete_summon_from_hand(card, slot)
			else:
				_show_error("No card selected to summon!")
				_cancel_pending()
		
		"set":
			var expected_type = Zone.ZoneType.MAIN_MONSTER if _pending_card.definition.is_monster() else Zone.ZoneType.MAIN_SPELL
			if zone.zone_type != expected_type:
				_show_error("Invalid zone for set!")
				return
			game_director.set_card(local_player, _pending_card, slot)
			refresh_hand(local_player)
			_cancel_pending()
		
		"activate":
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
	_cancel_auto_pass()
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

	## Tribute monsters need tributes chosen BEFORE we can even validate
	## which zone to place them in — RuleEngine.can_normal_summon requires
	## the tribute list up front.
	if card.definition.requires_tribute():
		_begin_tribute_selection(card)
		return

	_continue_summon_after_tributes(card, [])

## Shared by both the no-tribute fast path and the tribute-selection
## completion handler. Picks (or asks for) a zone once tributes are settled.
func _continue_summon_after_tributes(card: CardInstance, tributes: Array[CardInstance]) -> void:
	var monster_zone := zone_manager.monster_zone_of(local_player)

	## Tributes free up slots too, but RuleEngine validates that — here we
	## only care about how many slots are open right now for placement.
	var empty_slots := monster_zone.empty_slot_count()

	if empty_slots == 0:
		_show_error("No empty monster zones!")
		return

	if empty_slots == 1:
		game_director.normal_summon(local_player, card, tributes, monster_zone.first_empty_slot())
		refresh_hand(local_player)
		return

	## Multiple empty zones — ask player to choose
	_pending_state       = PendingState.AWAIT_ZONE_SELECTION
	_pending_card        = card
	_pending_action_type = "summon"
	_pending_tributes    = tributes

	clear_all_glows()
	clear_zone_highlights()
	highlight_empty_zones(Zone.ZoneType.MAIN_MONSTER, local_player, true)

	_show_cancel_hint("Click on an empty monster zone to summon %s" % card.definition.card_name)
# ─── Awaiting Input (GameDirector) ────────────────────────────────────────────
func _on_snapshot_restored(_label: String) -> void:
		## An undo/redo just snapped the board data directly to a prior state.
		## Any in-progress targeting/tribute/discard selection is now describing
		## a moment that no longer exists, so it must be abandoned rather than
		## completed against the restored state.
		_cancel_pending()
		## Anything mid-flight in the animation queue was animating a transition
		## that the restore just bypassed entirely — let it finish naturally if
		## near-instant, but don't try to reconcile it against the new state.
		## A full_refresh() afterward corrects any visual drift this leaves.
		full_refresh()
func _on_awaiting_input(request: InputRequest) -> void:
		## Only the human's own decisions get a visual presentation here.
		## AIController handles its own requests independently via the same
		## signal — both listeners coexist safely since GameDirector.request_input
		## doesn't filter by player itself.
		if request.player != local_player:
				return
		match request.type:
				InputRequest.RequestType.DISCARD_SELECTION:
						_begin_discard_selection(request)
				_:
						## Other request types (target/tribute/search/position) aren't
						## routed through GameDirector's InputRequest for the human yet —
						## those use BoardView's own click-based flows instead. Nothing
						## to do here for them.
						pass
func _begin_discard_selection(request: InputRequest) -> void:
		_pending_state           = PendingState.AWAIT_DISCARD_SELECTION
		_pending_discard_request = request
		_discards_needed         = request.min_choices
		_pending_discards.clear()
		clear_all_glows()
		for card in request.candidates:
				var view := _card_views.get((card as CardInstance).instance_id, null)
				if view:
						view.set_glow(CardView.GlowState.TARGETABLE)
		_show_cancel_hint("Hand limit exceeded — select %d card%s to discard." % [
				_discards_needed, "s" if _discards_needed != 1 else ""
		])
		## Deliberately no Escape-to-cancel here — this isn't optional, the hand
		## limit must be resolved before the turn can pass. _cancel_pending()
		## still clears the visual state if called, but nothing re-triggers this
		## request, so cancelling would strand the turn. Escape is effectively
		## a no-op for this state in practice since the player has no legal
		## alternative action available while it's active.
func _collect_discard(card: CardInstance) -> void:
		var view :CardView= _card_views.get(card.instance_id, null)
		if view == null or view.glow_state != CardView.GlowState.TARGETABLE:
				## Not a valid discard candidate — ignore the click, stay in this state
				return
		_pending_discards.append(card)
		view.set_glow(CardView.GlowState.TARGETED)
		if _pending_discards.size() >= _discards_needed:
				var chosen := _pending_discards.duplicate()
				_pending_state           = PendingState.NONE
				_pending_discard_request = null
				_pending_discards.clear()
				_discards_needed         = 0
				deselect_all()
				clear_all_glows()
				_hide_cancel_hint()
				## GameDirector.resolve_input() calls request.resolve(chosen) for us —
				## calling request.resolve() directly here too would double-fire it.
				game_director.resolve_input(chosen)
				refresh_hand(local_player)
func _begin_tribute_selection(card: CardInstance) -> void:
		var needed := card.definition.tribute_count()
		var field  := zone_manager.monster_zone_of(local_player).get_cards()
		if field.size() < needed:
				_show_error("Need %d tribute%s — you only control %d monster%s." % [
						needed, "s" if needed > 1 else "",
						field.size(), "s" if field.size() != 1 else ""
				])
				return
		_pending_state    = PendingState.AWAIT_TRIBUTE_SELECTION
		_pending_card     = card
		_tributes_needed  = needed
		_pending_tributes.clear()
		clear_all_glows()
		for tribute_candidate in field:
				var view :CardView= _card_views.get(tribute_candidate.instance_id, null)
				if view:
						view.set_glow(CardView.GlowState.TARGETABLE)
		_show_cancel_hint("Select %d monster%s to tribute for %s, or press Escape to cancel." % [
				needed, "s" if needed > 1 else "", card.definition.card_name
		])
func _collect_tribute(card: CardInstance) -> void:
		var view :CardView= _card_views.get(card.instance_id, null)
		if view == null or view.glow_state != CardView.GlowState.TARGETABLE:
				## Clicked a card that isn't a valid tribute candidate — cancel
				_cancel_pending()
				return
		_pending_tributes.append(card)
		view.set_glow(CardView.GlowState.TARGETED)
		if _pending_tributes.size() >= _tributes_needed:
				var summon_card := _pending_card
				var tributes     := _pending_tributes.duplicate()
				_cancel_pending()
				_continue_summon_after_tributes(summon_card, tributes)
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
		var view :CardView= _card_views.get(target.instance_id, null)
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
		_pending_state       = PendingState.AWAIT_ZONE_SELECTION
		_pending_card        = card
		_pending_action_type = "activate"
		
		clear_all_glows()
		clear_zone_highlights()
		highlight_empty_zones(Zone.ZoneType.MAIN_SPELL, local_player, true)
		_show_cancel_hint("Click on an empty spell/trap zone to place %s" % card.definition.card_name)
		return	
	## If the card has more than one activatable effect, pick the first for now.
	## A future improvement would show a sub-menu to choose which effect.
	if eff_list.size() > 1:
		# Get the actual CardView for positioning
		var view :CardView= _card_views.get(card.instance_id, null)
		if view:
			_effect_picker.show_for(card, eff_list, view.global_position, view.size)
		else:
			# Fallback: use the first effect if we can't find the view
			_start_effect_targeting(card, eff_list[0])
		return
	
	# Single effect - go directly to targeting
	_start_effect_targeting(card, eff_list[0])


func _on_effect_picked(card: CardInstance, effect_index: int) -> void:
	_start_effect_targeting(card, effect_index)
## Shared by both the single-effect fast path and the picker's selection
## callback. Fires immediately if no targeting is needed, otherwise enters
## AWAIT_EFFECT_TARGET and highlights legal candidates.
func _start_effect_targeting(card: CardInstance, eff_idx: int) -> void:
	var eff: EffectDefinition = card.definition.effects[eff_idx]

	# ─── NEW: Check if this is the "Special Summon from Hand" effect ────────
	# If so, we need to select a monster from hand first, then a zone
	if eff.effect_name == "Special Summon from Hand":
		_start_summon_from_hand_flow(card, eff_idx)
		return
	# Check if this is a search effect (like Sangan)
	if eff.effect_name == "GY Search" or eff.effect_name.contains("Search"):
		_start_search_flow(card, eff_idx)
		return

	## No targeting required — activate immediately
	if eff.targets_required == 0:
		game_director.activate_effect(local_player, card, eff_idx, [])
		return

	## Targeting required — highlight candidates and wait for clicks
	var candidates := RuleEngine.get_legal_targets(eff, local_player, zone_manager)
	if candidates.size() < eff.targets_required:
		return
# If multiple targets and the player needs to select from a list
	# rather than clicking on the board, use the selector
	if eff.targets_required == 1:
		# Show selector for single target
		_card_selector.show_for(
			candidates,
			"Select a target for %s" % eff.effect_name,
			"",
			1, 1
		)
		_pending_state = PendingState.AWAIT_EFFECT_TARGET
		_pending_card = card
		_pending_effect_idx = eff_idx
		_pending_action_type = "target_effect"
		_targets_needed = 1
		return
	
	# Fallback to click-based targeting for multiple targets
	_pending_state = PendingState.AWAIT_EFFECT_TARGET
	_pending_card = card
	_pending_effect_idx = eff_idx
	_pending_targets.clear()
	_targets_needed = eff.targets_required

	clear_all_glows()
	select_card(card)

	for candidate in candidates:
		var view :CardView= _card_views.get(candidate.instance_id, null)
		if view:
			view.set_glow(CardView.GlowState.TARGETABLE)

	_show_cancel_hint("Select %d target%s, or press Escape to cancel." % [
		eff.targets_required,
		"s" if eff.targets_required > 1 else ""
	])


# ─── NEW: Special Summon from Hand flow ──────────────────────────────────────
func _start_summon_from_hand_flow(card: CardInstance, eff_idx: int) -> void:
	# Step 1: Get all monsters in hand
	var hand := zone_manager.hand_of(local_player)
	var monsters: Array[CardInstance] = []
	for hand_card in hand.get_cards():
		if hand_card.definition.is_monster() and hand_card != card: # Can't summon itself
			monsters.append(hand_card)
	
	if monsters.is_empty():
		_show_error("No monsters in hand to summon!")
		return
	
	 # Step 2: If only one monster, skip selector
	if monsters.size() == 1:
		var to_summon := monsters[0]
		
		# Check if there's room on the field
		if zone_manager.monster_zone_of(local_player).is_full():
			_show_error("Monster zone is full!")
			return
		
		# Check how many empty zones
		var empty_slots := zone_manager.monster_zone_of(local_player).empty_slot_count()
		
		if empty_slots == 1:
			var slot := zone_manager.monster_zone_of(local_player).first_empty_slot()
			_complete_summon_from_hand(to_summon, slot)
			return
		
		# Multiple zones - ask player to choose
		_pending_state = PendingState.AWAIT_ZONE_SELECTION
		_pending_card = card
		_pending_effect_idx = eff_idx
		_pending_action_type = "summon_from_hand"
		_pending_targets = [to_summon]
		
		clear_all_glows()
		clear_zone_highlights()
		highlight_empty_zones(Zone.ZoneType.MAIN_MONSTER, local_player, true)
		_show_cancel_hint("Click on an empty monster zone to summon %s" % to_summon.definition.card_name)
		return
	
	# Step 3: Multiple monsters - show CardSelector
	_pending_state = PendingState.AWAIT_EFFECT_TARGET
	_pending_card = card
	_pending_effect_idx = eff_idx
	_pending_action_type = "summon_from_hand_selector"
	_targets_needed = 1
	
	_card_selector.show_for(
		monsters,
		"Select a monster to summon",
		"Choose one monster from your hand",
		1, 1
	)

func _collect_effect_target(card: CardInstance) -> void:
	## Check this card is actually a highlighted target
	var view :CardView= _card_views.get(card.instance_id, null)
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
	_pending_tributes.clear()
	if _card_selector and _card_selector.visible:
		_tributes_needed     = 0
		_pending_discards.clear()
		_card_selector.hide()
		_discards_needed         = 0
		_pending_discard_request = null
	if _card_selector and _card_selector.visible:
		_card_selector.hide()

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
		if event.keycode == KEY_ESCAPE \
		and _pending_state != PendingState.NONE \
		and _pending_state != PendingState.AWAIT_DISCARD_SELECTION:
			## Discard-to-hand-limit is mandatory — there is no legal way to
			## decline it, so Escape must not be able to strand TurnManager
			## in its blocked _awaiting_discard state with no way to resume.
			_cancel_pending()
			get_viewport().set_input_as_handled()
# ─── Helpers ──────────────────────────────────────────────────────────────────
func _get_summon_step(card: CardInstance, eff_idx: int) -> CardLibrary._SummonFromHandStep:
	var eff: EffectDefinition = card.definition.effects[eff_idx]
	for step in eff.resolution_steps:
		if step is CardLibrary._SummonFromHandStep:
			return step
	return null
func _get_card_view(card: CardInstance) -> CardView:
	# Check if in hand
	if card.is_in_hand():
		var hand_manager = _hand_manager_p1 if card.controller == players[0] else _hand_manager_p2
		if hand_manager:
			var views = hand_manager.get_card_views()
			if views.has(card.instance_id):
				return views[card.instance_id]
	
	# Check BoardView's cache
	return _card_views.get(card.instance_id, null)


func _setup_auto_pass_timer() -> void:
	_auto_pass_timer = Timer.new()
	_auto_pass_timer.wait_time = _auto_pass_delay
	_auto_pass_timer.one_shot = true
	_auto_pass_timer.timeout.connect(_on_auto_pass_timeout)
	add_child(_auto_pass_timer)
func _check_player_has_actions() -> bool:
	if game_director == null:
		return true # Don't auto-pass if no game director
	
	var la := game_director.legal_actions_for(local_player)
	
	# Check if there are ANY legal actions
	# This includes: effects, summons, sets, attacks, position changes
	var has_actions := false
	
	# Check activatable effects
	if not la.can_activate.is_empty():
		has_actions = true
	
	# Check normal summons
	if not la.can_normal_summon.is_empty():
		has_actions = true
	
	# Check sets
	if not la.can_set.is_empty():
		has_actions = true
	
	# Check attacks (only in battle phase)
	if not la.can_attack.is_empty():
		has_actions = true
	
	# Check position changes
	if not la.can_change_position.is_empty():
		has_actions = true
	
	return has_actions

## Start the auto-pass timer
func _start_auto_pass() -> void:
	print("started auto pass")
	if _auto_pass_timer == null:
		return
	
	if _is_waiting_for_auto_pass:
		return # Already waiting
	
	_is_waiting_for_auto_pass = true
	_auto_pass_timer.start()
	turn_label.text = "Auto-passing in %.1fs..." % _auto_pass_delay
	turn_label.modulate = Color(0.5, 0.8, 0.5)

## Cancel the auto-pass timer
func _cancel_auto_pass() -> void:
	if _auto_pass_timer == null:
		return
	
	_is_waiting_for_auto_pass = false
	_auto_pass_timer.stop()
	
	# Reset turn label if it was showing auto-pass message
	if turn_label and turn_label.text.begins_with("Auto-passing"):
		turn_label.text = "Turn %d — Player %d" % [effect_stack._current_turn() if effect_stack else 1, local_player.player_id]
		turn_label.modulate = Color(0.7, 0.7, 0.7)

## Called when the auto-pass timer expires
func _on_auto_pass_timeout() -> void:
	_is_waiting_for_auto_pass = false
	
	# Double-check we still have no actions (something might have changed)
	if _check_player_has_actions():
		return
	
	# Auto-pass priority
	if game_director != null:
		print("Auto-pass: No legal actions, passing priority")
		game_director.pass_priority(local_player)
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
	
	var zone: Zone
	var title: String = pile_type.to_upper()
	
	match pile_type:
		"deck":
			zone = zone_manager.deck_of(player)
			title = "%s's Deck" % player.display_name
		"extra":
			zone = zone_manager.extra_deck_of(player)
			title = "%s's Extra Deck" % player.display_name
		"graveyard":
			zone = zone_manager.graveyard_of(player)
			title = "%s's Graveyard" % player.display_name
		"banished":
			zone = zone_manager.banished_of(player)
			title = "%s's Banished" % player.display_name
	
	if zone:
		var cards: Array = zone.get_cards()
		print("  Contains %d cards" % cards.size())
		
		# Show the pile viewer
		_pile_viewer.show_for(cards, pile_type, player, title)

func _build_card_selector() -> void:
	_card_selector = _CardSelectorScene.instantiate()
	add_child(_card_selector)
	_card_selector.card_selected.connect(_on_card_selector_selected)
	_card_selector.cancelled.connect(_on_card_selector_cancelled)
	_card_selector.hide()

func _on_card_selector_selected(card: CardInstance) -> void:
	print("Card selected: %s" % card.definition.card_name)
	
	match _pending_action_type:
		"search":
			# Move the selected card to hand
			zone_manager.move(card, zone_manager.hand_of(local_player), ZoneManager.MoveReason.EFFECT_RETURN)
			refresh_hand(local_player)
			_cancel_pending()
		
		"target_effect":
			# Add to pending targets
			_pending_targets.append(card)
			var view:CardView = _card_views.get(card.instance_id, null)
			if view:
				view.set_glow(CardView.GlowState.TARGETED)
			
			# Check if we have enough targets
			if _pending_targets.size() >= _targets_needed:
				_complete_effect_activation()
			else:
				_show_cancel_hint("Select %d more target%s" % [
					_targets_needed - _pending_targets.size(),
					"s" if _targets_needed - _pending_targets.size() > 1 else ""
				])
		
		"summon_from_hand_selector":
			# ─── FIX: Store the selected card and transition to zone selection ───
			# Store the card to summon
			_pending_targets = [card]
			
			# Check if there's room on the field
			if zone_manager.monster_zone_of(local_player).is_full():
				_show_error("Monster zone is full!")
				_cancel_pending()
				return
			
			# Check how many empty zones
			var empty_slots := zone_manager.monster_zone_of(local_player).empty_slot_count()
			
			if empty_slots == 1:
				# Only one choice - place it automatically
				var slot := zone_manager.monster_zone_of(local_player).first_empty_slot()
				_complete_summon_from_hand(card, slot)
				return
			
			# ─── TRANSITION TO ZONE SELECTION ──────────────────────────────────
			# Change state to zone selection
			_pending_state = PendingState.AWAIT_ZONE_SELECTION
			_pending_action_type = "summon_from_hand_selector_zone"  # New type for clarity
			
			# Highlight empty monster zones
			clear_all_glows()
			clear_zone_highlights()
			highlight_empty_zones(Zone.ZoneType.MAIN_MONSTER, local_player, true)
			_show_cancel_hint("Click on an empty monster zone to summon %s" % card.definition.card_name)


func _complete_effect_activation() -> void:
	## Called when all targets have been selected for an effect
	if _pending_card == null:
		return
	
	var source := _pending_card
	var eff_idx := _pending_effect_idx
	var targets := _pending_targets.duplicate()
	
	# Clear pending state before activating
	_cancel_pending()
	
	# Fire the effect
	game_director.activate_effect(local_player, source, eff_idx, targets)

func _on_card_selector_cancelled() -> void:
	print("Card selection cancelled")
	_cancel_pending()
func _start_search_flow(card: CardInstance, eff_idx: int) -> void:
	# Get the search candidates from the effect step
	#var eff: EffectDefinition = card.definition.effects[eff_idx]
	
	# For Sangan, we need to search the deck for monsters with ATK <= 1500
	var deck := zone_manager.deck_of(local_player)
	var candidates: Array[CardInstance] = []
	
	for deck_card in deck.get_cards():
		# Apply the search condition (ATK <= 1500 for Sangan)
		if deck_card.get_atk() <= 1500 and deck_card.definition.is_monster():
			candidates.append(deck_card)
	
	if candidates.is_empty():
		_show_error("No valid cards to search!")
		return
	
	# Show the selector
	_card_selector.show_for(
		candidates,
		"Select a card to add to your hand",
		"Search your deck",
		1, 1
	)
	
	_pending_state = PendingState.AWAIT_EFFECT_TARGET
	_pending_card = card
	_pending_effect_idx = eff_idx
	_pending_action_type = "search"
	_targets_needed = 1

func _complete_summon_from_hand(card: CardInstance, slot: int) -> void:
	## Complete the summon from hand flow with the selected card and slot
	if _pending_card == null:
		return
	
	# Get the effect and set the chosen card and slot
	var eff: EffectDefinition = _pending_card.definition.effects[_pending_effect_idx]
	var step := _get_summon_step(_pending_card, _pending_effect_idx)
	if step:
		step.chosen_card = card
		step.target_slot = slot
	else:
		_show_error("Could not find summon step!")
		_cancel_pending()
		return
	
	# Activate the effect
	game_director.activate_effect(local_player, _pending_card, _pending_effect_idx, [])
	refresh_hand(local_player)
	_cancel_pending()
func update_legal_glows() -> void:
	if game_director == null:
		return
	
	var la := game_director.legal_actions_for(local_player)
	
	# Clear all glows first
	clear_all_glows()
	
	# Show Blue glow for summonable cards
	highlight_summonable(la.can_normal_summon)
	
	# Show Yellow/Orange glow for activatable cards
	var activatable :Array = la.can_activate.keys()
	if activatable:
		highlight_activatable(activatable)
	
	# Note: Targetable glows are shown separately during targeting
func _build_pile_viewer() -> void:
	_pile_viewer = _PileViewerScene.instantiate()
	add_child(_pile_viewer)
	_pile_viewer.card_inspected.connect(_on_pile_card_inspected)
	_pile_viewer.closed.connect(_on_pile_viewer_closed)
	_pile_viewer.hide()

func _connect_pile_buttons() -> void:
	# P1 buttons
	if p1_gy_button:
		p1_gy_button.pressed.connect(func(): _on_pile_clicked(players[0], "graveyard"))
	if p1_banish_button:
		p1_banish_button.pressed.connect(func(): _on_pile_clicked(players[0], "banished"))
	if p1_deck_button:
		p1_deck_button.pressed.connect(func(): _on_pile_clicked(players[0], "deck"))
	
	# P2 buttons
	if p2_gy_button:
		p2_gy_button.pressed.connect(func(): _on_pile_clicked(players[1], "graveyard"))
	if p2_banish_button:
		p2_banish_button.pressed.connect(func(): _on_pile_clicked(players[1], "banished"))
	if p2_deck_button:
		p2_deck_button.pressed.connect(func(): _on_pile_clicked(players[1], "deck"))

func _on_pile_card_inspected(card: CardInstance) -> void:
	print("Inspecting card from pile: %s" % card.definition.card_name)
	# This could open a full card inspection popup
	card_inspect_requested.emit(card)

func _on_pile_viewer_closed() -> void:
	print("Pile viewer closed")

func _setup_hands() -> void:
	# Create hand managers
	
	_hand_manager_p1 = HandManagerScene.instantiate()
	_hand_manager_p2 = HandManagerScene.instantiate()
	_hand_manager_p1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_manager_p2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_manager_p1.name = "player name"
	_hand_manager_p2.name = "enemy name"
	# Add to scene
	hands_container.add_child(_hand_manager_p1)
	hands_container.add_child(_hand_manager_p2)
	
	# Position them - DIFFERENT POSITIONS!
	_hand_manager_p1.position = Vector2(0, 540)  # Bottom of screen
	_hand_manager_p1.size = Vector2(size.x, 1)
	
	_hand_manager_p2.position = Vector2(0, 0)    # Top of screen
	_hand_manager_p2.size = Vector2(size.x, 1)
	
	# Setup with players
	_hand_manager_p1.setup(players[0], zone_manager.hand_of(players[0]))
	_hand_manager_p2.setup(players[1], zone_manager.hand_of(players[1]))
	
	# Connect signals
	_hand_manager_p1.card_selected.connect(_on_hand_card_selected.bind(players[0]))
	_hand_manager_p2.card_selected.connect(_on_hand_card_selected.bind(players[1]))
	
	# Hide P2 hand (face down - opponent's cards)
	await get_tree().process_frame  # Wait for views to be created
	for child in _hand_manager_p2.hand_container.get_children():
		if child is CardView:
			child.flip_to(false, true)
	
	# P1 hand face up
	for child in _hand_manager_p1.hand_container.get_children():
		if child is CardView:
			child.flip_to(true, true)

func _on_hand_card_selected(card: CardInstance, player: Player) -> void:
	if player != local_player:
		return
	
	var view = _hand_manager_p1.get_card_views().get(card.instance_id, null)
	if view and game_director:
		var actions = game_director.tooltip_actions_for(card, local_player)
		tooltip.show_for(card, actions, view.global_position, view.size)
# Keyboard shortcut to toggle hand expansion
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H:
			_hand_manager_p1.toggle_expanded()
		elif event.keycode == KEY_CTRL:
			# Hold Ctrl to temporarily hide hand
			_hand_manager_p1.hide_hand()
		elif event.keycode == KEY_ALT:
			# Hold Alt to view board (hide hand automatically)
			_hand_manager_p1.hide_hand()
