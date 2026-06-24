## CardTooltip.gd
## Master Duel-style contextual action popup that appears above a hovered/selected card.
## Shows only the buttons relevant to the card's current state.
##
## Available actions:
##   SUMMON    — Normal summon a monster from hand
##   SET       — Set a monster or spell/trap face-down
##   ACTIVATE  — Activate a spell, trap, or monster effect
##   ATTACK    — Declare an attack (only in battle phase)
##   INSPECT   — View full card text
##
## Usage:
##   tooltip.show_for(card_instance, allowed_actions, global_card_position)
##   tooltip.action_selected.connect(_on_tooltip_action)
class_name CardTooltip
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the player picks an action.
## `action` is one of the Action enum values.
## `card` is the CardInstance the action applies to.
signal action_selected(action: int, card: CardInstance)

## Emitted when the tooltip is dismissed without a selection.
signal dismissed()

# ─── Actions ──────────────────────────────────────────────────────────────────

enum Action {
	SUMMON,
	SET,
	ACTIVATE,
	ATTACK,
	INSPECT,
}

const ACTION_LABEL := {
	Action.SUMMON:   "Summon",
	Action.SET:      "Set",
	Action.ACTIVATE: "Activate",
	Action.ATTACK:   "Attack",
	Action.INSPECT:  "Inspect",
}

const ACTION_COLOR := {
	Action.SUMMON:   Color(0.20, 0.75, 0.30),
	Action.SET:      Color(0.25, 0.50, 0.80),
	Action.ACTIVATE: Color(0.70, 0.45, 0.10),
	Action.ATTACK:   Color(0.80, 0.15, 0.10),
	Action.INSPECT:  Color(0.45, 0.45, 0.55),
}

# ─── Layout ───────────────────────────────────────────────────────────────────

const BTN_W      := 72.0
const BTN_H      := 26.0
const BTN_GAP    := 5.0
const MARGIN     := 8.0
const ARROW_H    := 10.0   ## Height of the downward-pointing arrow
const ANIM_DUR   := 0.12

# ─── State ────────────────────────────────────────────────────────────────────

var _card:    CardInstance = null
var _buttons: Array[Button] = []

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _container: HBoxContainer = $Panel/Container
@onready var _panel:     Panel         = $Panel
@onready var _arrow:     Control       = $Panel/Arrow

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	hide()
	mouse_filter = MOUSE_FILTER_IGNORE

	# Draw the downward arrow on the Arrow child
	_arrow.draw.connect(_draw_arrow.bind(_arrow))

	# Close if player clicks anywhere outside
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

func _draw_arrow(arrow_node: Control) -> void:
	var w  := arrow_node.size.x
	var h  := arrow_node.size.y
	var cx := w / 2.0
	var pts := PackedVector2Array([
		Vector2(cx - h, 0),
		Vector2(cx + h, 0),
		Vector2(cx,     h),
	])
	arrow_node.draw_colored_polygon(pts, Color(0.35, 0.35, 0.55, 0.92))

## Show the tooltip above `card_global_pos` with only the given actions.
## `card_global_pos` should be the top-left global position of the CardView.
func show_for(
	card: CardInstance,
	actions: Array[Action],
	card_global_pos: Vector2,
	card_size: Vector2 = Vector2(100, 145)
) -> void:
	_card = card
	_clear_buttons()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	
	for action in actions:
		var btn := _make_button(action)
		_container.add_child(btn)
		_buttons.append(btn)

	# 1. Enforce explicit sizing for container elements cleanly
	var total_w := actions.size() * BTN_W + (actions.size() - 1) * BTN_GAP + MARGIN * 2
	var total_h := BTN_H + MARGIN * 2
	
	_panel.size = Vector2(total_w, total_h)
	_container.size = _panel.size
	_arrow.size = Vector2(total_w, ARROW_H)
	
	# Explicitly match parent layout boundary to content size
	size = Vector2(total_w, total_h + ARROW_H)

	# 2. Reset internal offsets to guarantee absolute alignment starting anchors
	_panel.position = Vector2.ZERO
	_container.position = Vector2.ZERO
	_arrow.position = Vector2(0, total_h)

	# 3. Position root coordinate centered above the card targets
	var tooltip_x := card_global_pos.x + (card_size.x / 2.0) - (total_w / 2.0)
	var tooltip_y := card_global_pos.y - total_h - ARROW_H - 4.0
	global_position = Vector2(tooltip_x, tooltip_y)

	# Clamp to safety bounds within viewport layout constraints
	var vp_size := get_viewport_rect().size
	global_position.x = clamp(global_position.x, 4, vp_size.x - total_w - 4)
	global_position.y = clamp(global_position.y, 4, vp_size.y - (total_h + ARROW_H) - 4)

	# Animate using relative tracking vectors rather than global mutation traps
	modulate.a = 0.0
	show()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, ANIM_DUR)
	tw.parallel().tween_property(self, "global_position:y", global_position.y, ANIM_DUR) \
		.from(global_position.y + 6)

func dismiss() -> void:
	if not visible:
		return
	var tw := create_tween()
	#tw.tween_property(self, "modulate:a", 0.0, ANIM_DUR)
	tw.tween_callback(func():
		hide()
		_clear_buttons()
		_card = null
	)
	dismissed.emit()

# ─── Button factory ───────────────────────────────────────────────────────────

func _make_button(action: Action) -> Button:
	var btn        := Button.new()
	btn.text       = ACTION_LABEL[action]
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)

	# Style
	var normal := StyleBoxFlat.new()
	normal.bg_color             = ACTION_COLOR[action].darkened(0.3)
	normal.border_color         = ACTION_COLOR[action]
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left  = 4
	normal.content_margin_right = 4

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = ACTION_COLOR[action].darkened(0.1)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = ACTION_COLOR[action]

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed_style)
	btn.add_theme_stylebox_override("focus",    normal)
	btn.add_theme_color_override("font_color",  Color.WHITE)
	btn.add_theme_font_size_override("font_size", 10)

	btn.pressed.connect(func():
		action_selected.emit(action, _card)
		dismiss()
	)
	return btn

func _clear_buttons() -> void:
	for btn in _buttons:
		_container.remove_child(btn)
		btn.queue_free()
	_buttons.clear()

# ─── Auto-dismiss ─────────────────────────────────────────────────────────────

func _on_focus_changed(_control: Control) -> void:
	# Dismiss if focus moved outside the tooltip
	if visible and not _is_ancestor_of_focused():
		dismiss()

func _is_ancestor_of_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	var node: Node = focused
	while node != null:
		if node == self:
			return true
		node = node.get_parent()
	return false

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed:
		# Convert the mouse position relative to the panel node
		var local :Vector2= get_viewport().get_mouse_position() - _panel.global_position
		
		# Check if the click is outside the panel's boundaries
		if not Rect2(Vector2.ZERO, _panel.size).has_point(local):
			dismiss()
			get_viewport().set_input_as_handled()
