## PileViewer.gd
## Master Duel-style viewer for Graveyard, Banished, and Deck piles.
## Shows cards in a scrollable grid with filtering options.
class_name PileViewer
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

signal card_inspected(card: CardInstance)
signal closed()

# ─── Constants ────────────────────────────────────────────────────────────────

const CARD_W = 80
const CARD_H = 116
const CARD_SPACING = 6

# ─── Node References ──────────────────────────────────────────────────────────

@onready var background: ColorRect = $Background
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Header/TitleLabel
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var card_grid: GridContainer = $Panel/VBoxContainer/ScrollContainer/CardGrid
@onready var count_label: Label = $Panel/VBoxContainer/FilterContainer/CountLabel

# Filter buttons
@onready var all_button: Button = $Panel/VBoxContainer/FilterContainer/AllButton
@onready var monster_button: Button = $Panel/VBoxContainer/FilterContainer/MonsterButton
@onready var spell_button: Button = $Panel/VBoxContainer/FilterContainer/SpellButton
@onready var trap_button: Button = $Panel/VBoxContainer/FilterContainer/TrapButton

# ─── State ────────────────────────────────────────────────────────────────────

var _cards: Array = []
var _filtered_cards: Array[CardInstance] = []
var _current_filter: String = "all"  # "all", "monster", "spell", "trap"
var _pile_type: String = "graveyard"
var _owner: Player = null
var _card_views: Dictionary = {}  # instance_id → Control

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	hide()
	close_button.pressed.connect(_on_close)
	background.gui_input.connect(_on_background_click)
	
	all_button.pressed.connect(func(): _set_filter("all"))
	monster_button.pressed.connect(func(): _set_filter("monster"))
	spell_button.pressed.connect(func(): _set_filter("spell"))
	trap_button.pressed.connect(func(): _set_filter("trap"))
	
	mouse_filter = MOUSE_FILTER_STOP

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()

# ─── Public API ───────────────────────────────────────────────────────────────

## Show the viewer with a list of cards
func show_for(
	cards: Array,
	pile_type: String = "graveyard",
	owner: Player = null,
	title: String = ""
) -> void:
	_cards = cards.duplicate()
	_pile_type = pile_type
	_owner = owner
	_card_views.clear()
	
	# Set title
	if title != "":
		title_label.text = title
	else:
		match pile_type:
			"graveyard":
				title_label.text = "GRAVEYARD"
			"banished":
				title_label.text = "BANISHED"
			"deck":
				title_label.text = "DECK"
			"extra":
				title_label.text = "EXTRA DECK"
			_:
				title_label.text = pile_type.to_upper()
	
	# Reset filter
	_current_filter = "all"
	_update_filter_buttons()
	
	# Show with animation
	show()
	_animate_in()
	
	# Build the grid
	_update_display()

## Hide the viewer
func close() -> void:
	if not visible:
		return
	_animate_out()

# ─── Display Update ──────────────────────────────────────────────────────────

func _update_display() -> void:
	_apply_filter()
	_build_grid()
	_update_count()

func _apply_filter() -> void:
	_filtered_cards.clear()
	
	for card:CardInstance in _cards:
		match _current_filter:
			"all":
				_filtered_cards.append(card)
			"monster":
				if card.definition.is_monster():
					_filtered_cards.append(card)
			"spell":
				if card.definition.is_spell():
					_filtered_cards.append(card)
			"trap":
				if card.definition.is_trap():
					_filtered_cards.append(card)

func _build_grid() -> void:
	# Clear existing
	for child in card_grid.get_children():
		child.queue_free()
	_card_views.clear()
	
	if _filtered_cards.is_empty():
		var label = Label.new()
		label.text = "No cards"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(200, 100)
		label.add_theme_font_size_override("font_size", 14)
		label.modulate = Color(0.5, 0.5, 0.5)
		card_grid.add_child(label)
		return
	
	# Set grid columns based on count
	var cols = 4
	if _filtered_cards.size() <= 2:
		cols = _filtered_cards.size()
	elif _filtered_cards.size() <= 4:
		cols = _filtered_cards.size()
	elif _filtered_cards.size() <= 8:
		cols = 4
	else:
		cols = 4
	card_grid.columns = cols
	
	# Create card slots
	for card in _filtered_cards:
		var slot = _create_card_slot(card)
		card_grid.add_child(slot)
		_card_views[card.instance_id] = slot

func _create_card_slot(card: CardInstance) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(CARD_W + 12, CARD_H + 30)
	container.mouse_filter = MOUSE_FILTER_STOP
	
	# Card container
	var card_container = Panel.new()
	card_container.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card_container.size = Vector2(CARD_W, CARD_H)
	card_container.mouse_filter = MOUSE_FILTER_STOP
	
	var style = StyleBoxFlat.new()
	style.bg_color = _get_card_color(card)
	style.set_corner_radius_all(4)
	card_container.add_theme_stylebox_override("panel", style)
	
	# Card type indicator
	var type_color = ColorRect.new()
	type_color.size = Vector2(CARD_W, 4)
	type_color.position = Vector2(0, 0)
	type_color.color = _get_type_color(card)
	type_color.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(type_color)
	
	# Card name
	var name_label = Label.new()
	name_label.text = card.definition.card_name
	name_label.position = Vector2(4, 6)
	name_label.size = Vector2(CARD_W - 8, 30)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.modulate = Color.WHITE
	name_label.clip_text = true
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(name_label)
	
	# Card type text
	var type_label = Label.new()
	type_label.text = _get_card_type_text(card)
	type_label.position = Vector2(4, CARD_H - 16)
	type_label.size = Vector2(CARD_W - 8, 12)
	type_label.add_theme_font_size_override("font_size", 6)
	type_label.modulate = Color(0.8, 0.8, 0.8)
	type_label.mouse_filter = MOUSE_FILTER_IGNORE
	card_container.add_child(type_label)
	
	# Stats for monsters
	if card.definition.is_monster():
		var stats_label = Label.new()
		stats_label.text = "ATK %d / DEF %d" % [card.get_atk(), card.get_def()]
		stats_label.position = Vector2(4, CARD_H - 28)
		stats_label.size = Vector2(CARD_W - 8, 10)
		stats_label.add_theme_font_size_override("font_size", 6)
		stats_label.modulate = Color(0.6, 0.8, 1.0)
		stats_label.mouse_filter = MOUSE_FILTER_IGNORE
		card_container.add_child(stats_label)
	
	# Click handler
	card_container.gui_input.connect(_on_card_slot_clicked.bind(card, card_container))
	
	# Hover effects
	card_container.mouse_entered.connect(func():
		card_container.modulate = Color(1.05, 1.05, 1.05)
	)
	card_container.mouse_exited.connect(func():
		card_container.modulate = Color.WHITE
	)
	
	container.add_child(card_container)
	
	# Card name below
	var below_label = Label.new()
	below_label.text = card.definition.card_name
	below_label.position = Vector2(0, CARD_H + 4)
	below_label.size = Vector2(CARD_W + 12, 20)
	below_label.add_theme_font_size_override("font_size", 7)
	below_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	below_label.clip_text = true
	below_label.mouse_filter = MOUSE_FILTER_IGNORE
	container.add_child(below_label)
	
	return container

func _update_count() -> void:
	count_label.text = "%d cards" % _filtered_cards.size()

func _update_filter_buttons() -> void:
	var active_color = Color(0.3, 0.6, 0.9, 1)
	var inactive_color = Color(0.2, 0.2, 0.3, 1)
	
	all_button.modulate = active_color if _current_filter == "all" else inactive_color
	monster_button.modulate = active_color if _current_filter == "monster" else inactive_color
	spell_button.modulate = active_color if _current_filter == "spell" else inactive_color
	trap_button.modulate = active_color if _current_filter == "trap" else inactive_color

func _set_filter(filter_type: String) -> void:
	_current_filter = filter_type
	_update_filter_buttons()
	_apply_filter()
	_build_grid()
	_update_count()

# ─── Color Helpers ────────────────────────────────────────────────────────────

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

func _get_type_color(card: CardInstance) -> Color:
	if card.definition.is_monster():
		return Color(1.0, 0.85, 0.2)  # Gold
	elif card.definition.is_spell():
		return Color(0.2, 0.8, 0.2)   # Green
	else:
		return Color(0.8, 0.2, 0.4)   # Pink/Purple

func _get_card_type_text(card: CardInstance) -> String:
	if card.definition.is_monster():
		var kind = CardDefinition.MonsterKind.keys()[card.definition.monster_kind]
		return "%s / %s" % [kind, card.definition.monster_type]
	elif card.definition.is_spell():
		var type = CardDefinition.SpellType.keys()[card.definition.spell_type]
		return "SPELL / %s" % type
	else:
		var type = CardDefinition.TrapType.keys()[card.definition.trap_type]
		return "TRAP / %s" % type

# ─── Input Handling ──────────────────────────────────────────────────────────

func _on_card_slot_clicked(event: InputEvent, card: CardInstance, _container: Panel) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Inspect the card
			card_inspected.emit(card)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click could do something else
			pass

func _on_background_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_close()

func _on_close() -> void:
	_animate_out()
	closed.emit()

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
