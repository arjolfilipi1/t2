## CardSelector.gd
## Master Duel-style card selection popup.
## Shows a grid/list of cards to choose from for effects, searches, etc.
##
## Usage:
##   selector.show_for(cards, "Select a monster to target", 1)
##   selector.card_selected.connect(func(card): ...)
##   selector.cancelled.connect(func(): ...)
class_name CardSelector
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the player selects a card
signal card_selected(card: CardInstance)

## Emitted when the player cancels the selection
signal cancelled()

# ─── Constants ────────────────────────────────────────────────────────────────

const CARD_WIDTH = 80
const CARD_HEIGHT = 116
const CARD_SPACING = 8

# ─── Node References ──────────────────────────────────────────────────────────

@onready var background: ColorRect = $Background
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $Panel/VBoxContainer/SubtitleLabel
@onready var card_grid: GridContainer = $Panel/VBoxContainer/CardGrid
@onready var cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var scroll_container: ScrollContainer = $Panel/VBoxContainer/ScrollContainer

# ─── State ────────────────────────────────────────────────────────────────────

var _cards: Array[CardInstance] = []
var _min_select: int = 1
var _max_select: int = 1
var _selected_cards: Array[CardInstance] = []
var _is_visible: bool = false
var _selection_mode: String = "single"  # "single", "multiple"

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	hide()
	cancel_button.pressed.connect(_on_cancel)
	background.gui_input.connect(_on_background_click)
	mouse_filter = MOUSE_FILTER_STOP

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()

# ─── Public API ───────────────────────────────────────────────────────────────

## Show the selector with a list of cards
func show_for(
	cards: Array[CardInstance],
	title: String = "Select a card",
	subtitle: String = "",
	min_select: int = 1,
	max_select: int = 1
) -> void:
	_cards = cards
	_min_select = min_select
	_max_select = max_select
	_selected_cards.clear()
	_is_visible = true
	
	# Set labels
	title_label.text = title
	subtitle_label.text = subtitle if subtitle != "" else "Choose %d card%s" % [
		min_select,
		"s" if min_select > 1 else ""
	]
	
	# Build the card grid
	_build_card_grid()
	
	# Show with animation
	show()
	_animate_in()

## Hide the selector
func hide_selector() -> void:
	if not visible:
		return
	_animate_out()

# ─── Grid Building ────────────────────────────────────────────────────────────

func _build_card_grid() -> void:
	# Clear existing children
	for child in card_grid.get_children():
		child.queue_free()
	
	if _cards.is_empty():
		var label = Label.new()
		label.text = "No cards available"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.theme_override_font_sizes["font_size"] = 14
		label.modulate = Color(0.7, 0.7, 0.7)
		card_grid.add_child(label)
		return
	
	# Determine grid columns based on number of cards
	var cols = 3
	if _cards.size() <= 3:
		cols = _cards.size()
	elif _cards.size() <= 6:
		cols = 3
	else:
		cols = 4
	card_grid.columns = cols
	
	# Create card slots
	for card in _cards:
		var slot = _create_card_slot(card)
		card_grid.add_child(slot)

func _create_card_slot(card: CardInstance) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(CARD_WIDTH + 12, CARD_HEIGHT + 30)
	container.mouse_filter = MOUSE_FILTER_STOP
	
	# Card container (clickable)
	var card_container = Panel.new()
	card_container.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card_container.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card_container.mouse_filter = MOUSE_FILTER_STOP
	card_container.add_theme_stylebox_override("panel", StyleBoxFlat.new())
	
	# Card view placeholder - we'll embed a mini CardView
	# For simplicity, use a ColorRect with card name
	var bg = ColorRect.new()
	bg.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	bg.color = _get_card_color(card)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(bg)
	
	# Card name
	var name_label = Label.new()
	name_label.text = card.definition.card_name
	name_label.position = Vector2(4, 4)
	name_label.size = Vector2(CARD_WIDTH - 8, 30)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.modulate = Color.WHITE
	name_label.clip_text = true
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(name_label)
	
	# Card type indicator
	var type_label = Label.new()
	type_label.text = _get_card_type_text(card)
	type_label.position = Vector2(4, CARD_HEIGHT - 16)
	type_label.size = Vector2(CARD_WIDTH - 8, 12)
	type_label.add_theme_font_size_override("font_size", 6)
	type_label.modulate = Color(0.8, 0.8, 0.8)
	type_label.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(type_label)
	
	# Stats for monsters
	if card.definition.is_monster():
		var stats_label = Label.new()
		stats_label.text = "%d/%d" % [card.get_atk(), card.get_def()]
		stats_label.position = Vector2(4, CARD_HEIGHT - 28)
		stats_label.size = Vector2(CARD_WIDTH - 8, 10)
		stats_label.add_theme_font_size_override("font_size", 6)
		stats_label.modulate = Color(0.6, 0.8, 1.0)
		stats_label.mouse_filter = MOUSE_FILTER_IGNORE
		card_container.add_child(stats_label)
	
	# Click handler
	card_container.gui_input.connect(_on_card_slot_clicked.bind(card, card_container))
	
	# Selection indicator (initially hidden)
	var selection_indicator = ColorRect.new()
	selection_indicator.name = "SelectionIndicator"
	selection_indicator.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	selection_indicator.color = Color(1, 0.85, 0.2, 0.3)
	selection_indicator.visible = false
	selection_indicator.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(selection_indicator)
	
	# Add hover effect
	card_container.mouse_entered.connect(func(): 
		card_container.modulate = Color(1.1, 1.1, 1.1)
	)
	card_container.mouse_exited.connect(func():
		card_container.modulate = Color.WHITE
	)
	
	container.add_child(card_container)
	
	# Card name below
	var below_label = Label.new()
	below_label.text = card.definition.card_name
	below_label.position = Vector2(0, CARD_HEIGHT + 4)
	below_label.size = Vector2(CARD_WIDTH + 12, 20)
	below_label.add_theme_font_size_override("font_size", 7)
	below_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	below_label.clip_text = true
	below_label.mouse_filter = MOUSE_FILTER_IGNORE
	container.add_child(below_label)
	
	return container

func _get_card_color(card: CardInstance) -> Color:
	if card.definition.is_monster():
		match card.definition.attribute:
			CardDefinition.Attribute.DARK: return Color(0.2, 0.05, 0.25)
			CardDefinition.Attribute.LIGHT: return Color(0.85, 0.85, 0.7)
			CardDefinition.Attribute.EARTH: return Color(0.4, 0.3, 0.15)
			CardDefinition.Attribute.WATER: return Color(0.1, 0.3, 0.6)
			CardDefinition.Attribute.FIRE: return Color(0.75, 0.2, 0.05)
			CardDefinition.Attribute.WIND: return Color(0.3, 0.65, 0.3)
			CardDefinition.Attribute.DIVINE: return Color(0.8, 0.7, 0.2)
		return Color(0.3, 0.3, 0.35)
	elif card.definition.is_spell():
		return Color(0.1, 0.35, 0.1)
	else:  # Trap
		return Color(0.4, 0.1, 0.2)

func _get_card_type_text(card: CardInstance) -> String:
	if card.definition.is_monster():
		return "%s / %s" % [
			CardDefinition.Attribute.keys()[card.definition.attribute],
			card.definition.monster_type
		]
	elif card.definition.is_spell():
		return "SPELL"
	else:
		return "TRAP"

# ─── Input Handling ───────────────────────────────────────────────────────────

func _on_card_slot_clicked(event: InputEvent, card: CardInstance, container: Panel) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_card_selection(card, container)

func _toggle_card_selection(card: CardInstance, container: Panel) -> void:
	var indicator = container.get_node("SelectionIndicator") as ColorRect
	
	if card in _selected_cards:
		# Deselect
		_selected_cards.erase(card)
		indicator.visible = false
		return
	
	# Check if we can select more
	if _selected_cards.size() >= _max_select:
		print("Already selected max: %d" % _max_select)
		return
	
	# Select
	_selected_cards.append(card)
	indicator.visible = true
	
	# If we've selected enough, auto-confirm
	if _selected_cards.size() >= _min_select:
		_confirm_selection()

func _confirm_selection() -> void:
	if _selected_cards.is_empty():
		return
	
	# Emit selected signal for each card (or just the first for single select)
	for card in _selected_cards:
		card_selected.emit(card)
	
	# Close the selector
	_animate_out()

func _on_cancel() -> void:
	_selected_cards.clear()
	cancelled.emit()
	_animate_out()

func _on_background_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_cancel()

# ─── Animations ───────────────────────────────────────────────────────────────

func _animate_in() -> void:
	panel.modulate.a = 0
	panel.scale = Vector2(0.8, 0.8)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _animate_out() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.15)
	tween.tween_property(panel, "scale", Vector2(0.8, 0.8), 0.15)
	await tween.finished
	hide()
	_is_visible = false
