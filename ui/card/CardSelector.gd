## CardSelector.gd
## Master Duel-style card selection popup.
## Shows a grid/list of cards to choose from for effects, searches, etc.
class_name CardSelector
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

signal card_selected(card: CardInstance)
signal cancelled()

# ─── Constants ────────────────────────────────────────────────────────────────

const CARD_WIDTH = 80
const CARD_HEIGHT = 116
const CARD_SPACING = 8
const CARD_DISPLAY_SCENE = preload("res://ui/card/CardDisplay.tscn")
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
var _selected_displays: Array[CardDisplay] = []
var _is_visible: bool = false

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
	_selected_displays.clear()
	_is_visible = true
	
	title_label.text = title
	subtitle_label.text = subtitle if subtitle != "" else "Choose %d card%s" % [
		min_select,
		"s" if min_select > 1 else ""
	]
	
	_build_card_grid()
	
	show()
	_animate_in()

func hide_selector() -> void:
	if not visible:
		return
	_animate_out()

# ─── Grid Building ────────────────────────────────────────────────────────────

func _build_card_grid() -> void:
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
	
	var cols = 3
	if _cards.size() <= 3:
		cols = _cards.size()
	elif _cards.size() <= 6:
		cols = 3
	else:
		cols = 4
	card_grid.columns = cols
	
	for card in _cards:
		var card_display = _create_card_display(card)
		card_grid.add_child(card_display)

func _create_card_display(card: CardInstance) -> CardDisplay:
	# Use the preloaded scene
	var card_display = CARD_DISPLAY_SCENE.instantiate() as CardDisplay
	card_display.set_card(card)
	card_display.clicked.connect(_on_card_display_clicked)
	return card_display

# ─── Input Handling ───────────────────────────────────────────────────────────

func _on_card_display_clicked(card: CardInstance, display: CardDisplay) -> void:
	_toggle_card_selection(card, display)

func _toggle_card_selection(card: CardInstance, display: CardDisplay) -> void:
	if card in _selected_cards:
		var idx = _selected_cards.find(card)
		if idx != -1:
			_selected_cards.remove_at(idx)
			_selected_displays.remove_at(idx)
		display.set_selected(false)
		return
	
	if _selected_cards.size() >= _max_select:
		print("Already selected max: %d" % _max_select)
		return
	
	_selected_cards.append(card)
	_selected_displays.append(display)
	display.set_selected(true)
	
	if _selected_cards.size() >= _min_select:
		_confirm_selection()

func _confirm_selection() -> void:
	if _selected_cards.is_empty():
		return
	
	for card in _selected_cards:
		card_selected.emit(card)
	
	_animate_out()

func _on_cancel() -> void:
	_selected_cards.clear()
	_selected_displays.clear()
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
