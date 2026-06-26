## HandManager.gd
## Handles fan layout, hover expansion, and card positioning for a player's hand
class_name HandManager
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────
signal hand_visibility_changed(visible: bool)
signal card_selected(card: CardInstance)

# ─── Constants ──────────────────────────────────────────────────────────────────
const CARD_WIDTH := 100.0
const CARD_HEIGHT := 145.0
const CARD_SPACING := 8.0 
const EXPANDED_SPACING := 20.0 
const HOVER_OFFSET_Y := -40.0 
const EXPAND_SCALE := 1.2 
const FAN_ANGLE_DEG := 10.0 
const FAN_ARC_Y := 12.0 
const ANIMATION_DURATION := 0.25

# ─── State ──────────────────────────────────────────────────────────────────
var _player: Player = null
var _cards: Array = []
var _card_views: Dictionary = {} 
var _card_positions: Dictionary = {} 
var _is_expanded: bool = false 
var _is_hovering: bool = false
var _hovered_card: CardInstance = null
var _hovered_index: int = -1
var _is_setup := false
# ─── Node Refs ──────────────────────────────────────────────────────────────────
@onready var hand_container: Control = $HandContainer
@onready var background: ColorRect = $Background
@onready var expand_button: Button = $ExpandButton

# ─── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	if expand_button:
		expand_button.pressed.connect(toggle_expanded)
		expand_button.text = "▼ Hand"
	
	_is_setup = true
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_STOP
	if hand_container:
		hand_container.MOUSE_FILTER_IGNORE
	if _player != null and not _cards.is_empty():
		_refresh_hand()
	on_node_ready()
func setup(player: Player, hand_zone: Zone) -> void:
	_player = player
	_cards = hand_zone.get_cards()
	#if _is_setup:
		#_refresh_hand()

# ─── Public API ──────────────────────────────────────────────────────────────────
func refresh_hand(hand_zone: Zone) -> void:
	if not _is_setup:
		_cards = hand_zone.get_cards()
		return
	_cards = hand_zone.get_cards()
	_refresh_hand()

func get_card_views() -> Dictionary:
	return _card_views
	
func get_card_count() -> int:
	return _cards.size()
	
func toggle_expanded() -> void:
	if not _is_setup:
		return
	_is_expanded = not _is_expanded
	_update_hand_layout()
	hand_visibility_changed.emit(_is_expanded)
	if expand_button:
		expand_button.text = "▲ Hand" if _is_expanded else "▼ Hand"

func set_expanded(expanded: bool) -> void:
	if _is_expanded == expanded:
		return
	_is_expanded = expanded
	_update_hand_layout()
	hand_visibility_changed.emit(_is_expanded)
	
func show_hand() -> void:
	if _is_expanded:
		return
	_is_expanded = true
	_update_hand_layout()
	hand_visibility_changed.emit(true)
var i :=0
func hide_hand() -> void:
	i +=1
	if not _is_expanded:
		return
	_is_expanded = false
	expand_button.text = "▲ Hand" if _is_expanded else "▼ Hand"
	_update_hand_layout()
	hand_visibility_changed.emit(false)
func get_card_at_position(pos: Vector2) -> CardInstance:
	for card in _cards:
		var view = _card_views.get(card.instance_id, null)
		if view and view.get_global_rect().has_point(pos):
			return card
	return null
func on_node_ready():
	size = Vector2(size.x,1)

# ─── Hand Layout ──────────────────────────────────────────────────────────────────
func _refresh_hand() -> void:
	if not _is_setup or not hand_container:
		return
	var existing := {}
	for card:CardInstance in _cards:
		var view:CardView = _card_views.get(card.instance_id)
		if view == null:
			view = _create_card_view(card)
			hand_container.add_child(view)
			_card_views[card.instance_id] = view
		existing[card.instance_id] = true
	for id in _card_views.keys():
		if not existing.has(id):
			var view:CardView = _card_views[id]
			hand_container.remove_child(view)
			view.queue_free()
			_card_views.erase(id)
	_update_hand_layout()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		print("hand click ",name,"filter",_is_expanded)
func _create_card_view(card: CardInstance) -> CardView:
	const CardViewScene := preload("res://ui/card/CardView.tscn")
	var view := CardViewScene.instantiate() as CardView
	view.bind(card)
	view.card_clicked.connect(_on_card_clicked)
	view.card_inspected.connect(_on_card_inspected)
	
	# Connect hover signals for expansion
	view.mouse_entered.connect(_on_card_hover_entered.bind(card))
	view.mouse_exited.connect(_on_card_hover_exited.bind(card))
	
	return view

func _update_hand_layout() -> void:
	if not _is_setup or not hand_container:
		return
	
	var count := _cards.size()
	if count == 0:
		return
	
	var container_width := hand_container.size.x
	if container_width == 0:
		container_width = size.x
		if container_width == 0:
			container_width = 1280
	
	var spacing := CARD_SPACING
	var total_width := count * CARD_WIDTH + (count - 1) * spacing
	
	if total_width > container_width and not _is_expanded:
		spacing = (container_width - count * CARD_WIDTH) / (count - 1)
		spacing = max(spacing, 2.0)
	
	var start_x := (container_width - total_width) / 2.0
	
	for i in count:
		var card = _cards[i]
		var view = _card_views.get(card.instance_id, null)
		if not view:
			continue
		
		var target_x := start_x + i * (CARD_WIDTH + spacing)
		var t :float= float(i) / max(count - 1, 1)
		var arc_y :float= sin(t * PI) * (-FAN_ARC_Y if not _is_expanded else-FAN_ARC_Y *0.5) if _player.is_human else sin(t * PI) * (+FAN_ARC_Y if not _is_expanded else +FAN_ARC_Y*0.5)
		var rotation := lerp(-FAN_ANGLE_DEG, FAN_ANGLE_DEG, t)
		
		if _is_expanded:
			rotation *= 0.3
		
		var y_offset := 0.0
		if _is_expanded:
			y_offset =  - CARD_HEIGHT * 0.7 if _player.is_human else  CARD_HEIGHT * 0.7 
		elif _hovered_card == card:
			y_offset = HOVER_OFFSET_Y
		
		var target_pos := Vector2(target_x, y_offset + arc_y)
		_card_positions[card.instance_id] = target_pos
		
		view.animate_move_to(target_pos, deg_to_rad(rotation))



# ─── Hover Expansion (Card Pushes Others) ──────────────────────────────────────
func _on_card_hover_entered(card: CardInstance) -> void:
	if _is_expanded:
		return  # No hover effects when expanded
	
	_hovered_card = card
	_is_hovering = true
	
	# Find index
	_hovered_index = _cards.find(card)
	if _hovered_index == -1:
		return
	
	# Update layout with expanded spacing
	_update_hand_with_expanded(_hovered_index)

func _on_card_hover_exited(card: CardInstance) -> void:
	if not _is_hovering:
		return
	
	_hovered_card = null
	_hovered_index = -1
	_is_hovering = false
	
	# Return to normal layout
	_update_hand_layout()

func _update_hand_with_expanded(hovered_index: int) -> void:
	var count := _cards.size()
	if count == 0:
		return
	
	var container_width := hand_container.size.x
	var spacing := EXPANDED_SPACING
	var total_width := count * CARD_WIDTH + (count - 1) * spacing
	
	# Adjust if overflow
	if total_width > container_width:
		spacing = (container_width - count * CARD_WIDTH) / (count - 1)
		spacing = max(spacing, 2.0)
	
	var start_x := (container_width - total_width) / 2.0
	
	for i in count:
		var card = _cards[i]
		var view = _card_views.get(card.instance_id, null)
		if not view:
			continue
		
		var target_x := start_x + i * (CARD_WIDTH + spacing)
		var t :float = float(i) / max(count - 1, 1)
		var arc_y := sin(t * PI) * (-FAN_ARC_Y)
		var rotation := lerp(-FAN_ANGLE_DEG, FAN_ANGLE_DEG, t)
		
		var y_offset := 0.0
		var scale := 1.0
		
		if i == hovered_index:
			# Hovered card: rise up and scale
			y_offset = HOVER_OFFSET_Y
			scale = EXPAND_SCALE
			view.z_index = 10
			
		elif abs(i - hovered_index) == 1:
			# Adjacent cards: slight push
			y_offset = HOVER_OFFSET_Y * 0.3
			scale = 1.0
		else:
			y_offset = 0
			scale = 1.0
		
		var target_pos := Vector2(target_x, y_offset + arc_y)
		view.animate_move_to(target_pos, deg_to_rad(rotation))





# ─── Input Handling ──────────────────────────────────────────────────────────
func _on_card_clicked(view: CardView) -> void:
	if view and view.card:
		card_selected.emit(view.card)

func _on_card_inspected(view: CardView) -> void:
	# Show card detail popup
	pass

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _get_hovered_view() -> CardView:
	if _hovered_card == null:
		return null
	return _card_views.get(_hovered_card.instance_id, null)

func _to_string() -> String:
	return "HandManager(%s, cards=%d)" % [_player.display_name if _player else "null", _cards.size()]
