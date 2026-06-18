## EffectPickerMenu.gd
## Popup shown when a card has more than one currently activatable effect.
## Lists each effect by name as a vertical stack of buttons above the card,
## visually similar to CardTooltip but listing effects instead of action types.
##
## Usage:
##   picker.show_for(card, [0, 2], view.global_position, view.size)
##   picker.effect_selected.connect(func(card, eff_idx): ...)
##   picker.dismissed.connect(func(): ...)
class_name EffectPickerMenu
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Player picked a specific effect. `effect_index` matches card.definition.effects.
signal effect_selected(card: CardInstance, effect_index: int)

## Player dismissed the menu without choosing (clicked outside, or pressed Escape).
signal dismissed()

# ─── Layout ───────────────────────────────────────────────────────────────────

const ROW_W      := 220.0
const ROW_H       := 30.0
const ROW_GAP    := 4.0
const MARGIN     := 8.0
const ARROW_H    := 10.0
const ANIM_DUR   := 0.12

# ─── State ────────────────────────────────────────────────────────────────────

var _card:    CardInstance = null
var _rows:    Array[Button] = []

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _panel:     Panel         = $Panel
@onready var _container: VBoxContainer = $Container
@onready var _arrow:     Control       = $Arrow

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	hide()
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index      = 100
	_arrow.draw.connect(_draw_arrow.bind(_arrow))

## Show the menu above `card_global_pos`, one row per effect index in `effect_indices`.
## `card` must have a non-empty definition.effects array.
func show_for(
	card:             CardInstance,
	effect_indices:   Array,
	card_global_pos:  Vector2,
	card_size:        Vector2 = Vector2(100, 145)
) -> void:
	_card = card
	_clear_rows()

	for eff_idx in effect_indices:
		var eff: EffectDefinition = card.definition.effects[eff_idx]
		var row := _make_row(eff_idx, eff)
		_container.add_child(row)
		_rows.append(row)

	var row_count := effect_indices.size()
	var total_w   := ROW_W + MARGIN * 2
	var total_h   :float = row_count * ROW_H + max(0, row_count - 1) * ROW_GAP + MARGIN * 2

	_panel.size     = Vector2(total_w, total_h)
	_container.size = Vector2(ROW_W, total_h - MARGIN * 2)
	_arrow.size     = Vector2(total_w, ARROW_H)

	var menu_x := card_global_pos.x + card_size.x / 2.0 - total_w / 2.0
	var menu_y :float = card_global_pos.y - total_h - ARROW_H - 4.0
	global_position = Vector2(menu_x, menu_y)

	var vp_size := get_viewport_rect().size
	global_position.x = clamp(global_position.x, 4, vp_size.x - total_w - 4)
	global_position.y = clamp(global_position.y, 4, vp_size.y - total_h - 4)

	modulate.a = 0.0
	show()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, ANIM_DUR)
	tw.parallel().tween_property(self, "position:y", global_position.y, ANIM_DUR) \
		.from(global_position.y + 6)

func dismiss() -> void:
	if not visible:
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, ANIM_DUR)
	tw.tween_callback(func():
		hide()
		_clear_rows()
		_card = null
	)
	dismissed.emit()

# ─── Row Construction ─────────────────────────────────────────────────────────

func _make_row(effect_index: int, eff: EffectDefinition) -> Button:
	var btn        := Button.new()
	btn.text       = eff.effect_name if eff.effect_name != "" else "Effect %d" % effect_index
	btn.custom_minimum_size = Vector2(ROW_W, ROW_H)
	btn.alignment  = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text  = true

	var normal := StyleBoxFlat.new()
	normal.bg_color            = Color(0.18, 0.16, 0.10, 1.0)
	normal.border_color        = Color(0.70, 0.55, 0.15, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.24, 0.14, 1.0)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.70, 0.55, 0.15, 1.0)

	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus",   normal)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 10)

	btn.pressed.connect(func():
		effect_selected.emit(_card, effect_index)
		dismiss()
	)
	return btn

func _clear_rows() -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()

# ─── Arrow Drawing ────────────────────────────────────────────────────────────

func _draw_arrow(arrow_node: Control) -> void:
	var w  := arrow_node.size.x
	var h  := arrow_node.size.y
	var cx := w / 2.0
	var pts := PackedVector2Array([
		Vector2(cx - h, 0),
		Vector2(cx + h, 0),
		Vector2(cx,     h),
	])
	arrow_node.draw_colored_polygon(pts, Color(0.70, 0.55, 0.15, 0.92))

# ─── Auto-dismiss ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed:
		var local := get_local_mouse_position()
		if not Rect2(Vector2.ZERO, _panel.size).has_point(local):
			dismiss()
			get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			dismiss()
			get_viewport().set_input_as_handled()
