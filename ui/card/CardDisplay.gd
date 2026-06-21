# CardDisplay.gd
class_name CardDisplay
extends Panel

# ─── Signals ──────────────────────────────────────────────────────────────────
signal clicked(card: CardInstance, display: CardDisplay)

# ─── Constants ────────────────────────────────────────────────────────────────
const CARD_WIDTH = 80
const CARD_HEIGHT = 116

# ─── Node References ──────────────────────────────────────────────────────────
@onready var card_bg: ColorRect = $CardBackground
@onready var name_label: Label = $NameLabel
@onready var type_label: Label = $TypeLabel
@onready var stats_label: Label = $StatsLabel
@onready var selection_indicator: ColorRect = $SelectionIndicator
@onready var click_area: Control = $ClickArea

# ─── State ────────────────────────────────────────────────────────────────────
var _card: CardInstance = null
var is_selected: bool = false
var _initialized: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH + 12, CARD_HEIGHT + 30)
	mouse_filter = MOUSE_FILTER_STOP
	
	# Set default text wrapping for name label
	if name_label:
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	_setup_click_handling()
	
	if selection_indicator:
		selection_indicator.visible = false
	
	_initialized = true
	
	# If a card was set before _ready, update the UI now
	if _card:
		_update_ui()

func _setup_click_handling() -> void:
	if click_area:
		click_area.gui_input.connect(_on_click_area_input)
		click_area.mouse_entered.connect(_on_mouse_entered)
		click_area.mouse_exited.connect(_on_mouse_exited)

func _on_click_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _card:
			clicked.emit(_card, self)
			toggle_selection(!is_selected)

func _on_mouse_entered() -> void:
	modulate = Color(1.1, 1.1, 1.1)

func _on_mouse_exited() -> void:
	modulate = Color.WHITE

# ─── Public API ──────────────────────────────────────────────────────────────

func set_card(card: CardInstance) -> void:
	_card = card
	# If the node is ready, update the UI immediately
	if _initialized:
		_update_ui()

func get_card() -> CardInstance:
	return _card

func toggle_selection(selected: bool) -> void:
	is_selected = selected
	if selection_indicator:
		selection_indicator.visible = selected

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selection_indicator:
		selection_indicator.visible = selected

# ─── Private Methods ──────────────────────────────────────────────────────────

func _update_ui() -> void:
	if not _card:
		return
	
	print("Updating card display for: ", _card.definition.card_name)  # Debug line
	
	if card_bg:
		card_bg.color = _get_card_color(_card)
	
	if name_label:
		name_label.text = _card.definition.card_name
	
	if type_label:
		type_label.text = _get_card_type_text(_card)
	
	if stats_label:
		if _card.definition.is_monster():
			stats_label.text = "%d/%d" % [_card.get_atk(), _card.get_def()]
			stats_label.visible = true
		else:
			stats_label.visible = false

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
