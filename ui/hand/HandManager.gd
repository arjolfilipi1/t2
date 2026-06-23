## HandManager.gd
## Handles fan layout, hover expansion, and card positioning for a player's hand
class_name HandManager
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal hand_visibility_changed(visible: bool)
signal card_selected(card: CardInstance)

# ─── Constants ──────────────────────────────────────────────────────────────────
const CARD_WIDTH := 100.0
const CARD_HEIGHT := 145.0
const CARD_SPACING := 8.0  # Normal spacing between cards
const EXPANDED_SPACING := 20.0  # Spacing when hovered
const HOVER_OFFSET_Y := -30.0  # How much hovered card rises
const EXPAND_SCALE := 1.2  # Scale when hovered
const FAN_ANGLE_DEG := 4.0  # Max rotation for fan
const FAN_ARC_Y := 12.0  # Y offset for fan arc
const ANIMATION_DURATION := 0.25

# ─── State ──────────────────────────────────────────────────────────────────
var _player: Player = null
var _cards: Array = []
var _card_views: Dictionary = {}  # instance_id → CardView
var _card_positions: Dictionary = {}  # instance_id → target_position
var _is_expanded: bool = false  # True when hand is fanned out (viewing board)
var _is_hovering: bool = false
var _hovered_card: CardInstance = null
var _hovered_index: int = -1

# ─── Node Refs ──────────────────────────────────────────────────────────────────
@onready var hand_container: Control = $HandContainer
@onready var background: ColorRect = $Background
@onready var expand_button: Button = $ExpandButton
var _is_setup := false
# ─── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:

	
	if expand_button:
		expand_button.pressed.connect(toggle_expanded)
		expand_button.text = "▼ Hand"
	_is_setup = true
	if _player != null and not _cards.is_empty():
		_refresh_hand()
func setup(player: Player, hand_zone: Zone) -> void:
	_player = player
	_cards = hand_zone.get_cards()
	if _is_setup:
		_refresh_hand()

# ─── Public API ──────────────────────────────────────────────────────────────────
func refresh_hand(hand_zone: Zone) -> void:
	if not _is_setup:
		_cards = hand_zone.get_cards()
		return
	_cards = hand_zone.get_cards()
	_refresh_hand()

func get_card_views() -> Dictionary:
	return _card_views

func toggle_expanded() -> void:
	if not _is_setup:
		return
	_is_expanded = not _is_expanded
	_update_hand_layout()
	hand_visibility_changed.emit(_is_expanded)
	expand_button.text = "▲ Hand" if _is_expanded else "▼ Hand"

func set_expanded(expanded: bool) -> void:
	if _is_expanded == expanded:
		return
	_is_expanded = expanded
	_update_hand_layout()
	hand_visibility_changed.emit(_is_expanded)

func get_card_at_position(pos: Vector2) -> CardInstance:
	for card in _cards:
		var view = _card_views.get(card.instance_id, null)
		if view and view.get_global_rect().has_point(pos):
			return card
	return null

# ─── Hand Layout ──────────────────────────────────────────────────────────────────
func _refresh_hand() -> void:
	# Clean up old views
	if not hand_container:
		return
	if hand_container and not hand_container.is_node_ready():
		return
	for child in hand_container.get_children():
		child.queue_free()
	_card_views.clear()
	
	# Create new views
	for card in _cards:
		var view = _create_card_view(card)
		hand_container.add_child(view)
		_card_views[card.instance_id] = view
	
	_update_hand_layout()

func _create_card_view(card: CardInstance) -> CardView:
	const CardViewScene := preload("res://ui/card/CardView.tscn")
	var view := CardViewScene.instantiate() as CardView
	view.bind(card)
	view.card_clicked.connect(_on_card_clicked.bind(card))
	view.card_inspected.connect(_on_card_inspected.bind(card))
	
	# Connect hover signals for expansion
	view.mouse_entered.connect(_on_card_hover_entered.bind(card))
	view.mouse_exited.connect(_on_card_hover_exited.bind(card))
	
	return view

func _update_hand_layout() -> void:
	var count := _cards.size()
	if count == 0:
		return
	
	var container_width := hand_container.size.x
	var spacing := CARD_SPACING
	var total_width := count * CARD_WIDTH + (count - 1) * spacing
	
	# Adjust spacing if cards would overflow
	if total_width > container_width and not _is_expanded:
		spacing = (container_width - count * CARD_WIDTH) / (count - 1)
		spacing = max(spacing, 2.0)  # Minimum spacing
	
	# Fan calculation
	var start_x := (container_width - total_width) / 2.0
	
	for i in count:
		var card = _cards[i]
		var view = _card_views.get(card.instance_id, null)
		if not view:
			continue
		
		# Calculate base position
		var target_x := start_x + i * (CARD_WIDTH + spacing)
		var t :float = float(i) / max(count - 1, 1)
		
		# Fan arc (cards curve upward)
		var arc_y : float= sin(t * PI) * (-FAN_ARC_Y if not _is_expanded else 0)
		
		# Fan rotation
		var rotation := lerp(-FAN_ANGLE_DEG, FAN_ANGLE_DEG, t)
		if _is_expanded:
			rotation *= 0.3  # Less rotation when expanded
		
		# Y position - cards lower when expanded
		var y_offset := 0.0
		if _is_expanded:
			# Push cards down to reveal board
			y_offset = CARD_HEIGHT * 0.7
		elif _hovered_card == card:
			# Hovered card rises
			y_offset = HOVER_OFFSET_Y
		
		# Target position
		var target_pos := Vector2(target_x, y_offset + arc_y)
		_card_positions[card.instance_id] = target_pos
		
		# Animate to position
		_animate_card_to(view, target_pos, rotation)

func _animate_card_to(view: CardView, target_pos: Vector2, rotation: float) -> void:
	# Create a tween for smooth animation
	var tw := view.create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_parallel(true)
	
	tw.tween_property(view, "position", target_pos, ANIMATION_DURATION)
	tw.tween_property(view, "rotation", deg_to_rad(rotation), ANIMATION_DURATION)
	
	# Z-index: hovered card on top
	if view == _get_hovered_view():
		view.z_index = 10
	else:
		view.z_index = 5

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
			view.z_index = 5
		
		var target_pos := Vector2(target_x, y_offset + arc_y)
		_animate_card_to_with_scale(view, target_pos, rotation, scale)

func _animate_card_to_with_scale(view: CardView, target_pos: Vector2, rotation: float, scale: float) -> void:
	var tw := view.create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_parallel(true)
	
	tw.tween_property(view, "position", target_pos, ANIMATION_DURATION)
	tw.tween_property(view, "rotation", deg_to_rad(rotation), ANIMATION_DURATION)
	tw.tween_property(view, "scale", Vector2(scale, scale), ANIMATION_DURATION)

# ─── Hand Visibility ──────────────────────────────────────────────────────────
func show_hand() -> void:
	if _is_expanded:
		return
	_is_expanded = true
	_update_hand_layout()
	hand_visibility_changed.emit(true)

func hide_hand() -> void:
	if not _is_expanded:
		return
	_is_expanded = false
	_update_hand_layout()
	hand_visibility_changed.emit(false)

# ─── Input Handling ──────────────────────────────────────────────────────────
func _on_card_clicked(card: CardInstance) -> void:
	card_selected.emit(card)

func _on_card_inspected(card: CardInstance) -> void:
	# Show card detail popup
	pass

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _get_hovered_view() -> CardView:
	if _hovered_card == null:
		return null
	return _card_views.get(_hovered_card.instance_id, null)

func _to_string() -> String:
	return "HandManager(%s, cards=%d)" % [_player.display_name if _player else "null", _cards.size()]
