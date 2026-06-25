## CurvedArrow.gd
## Master Duel-style curved arrow for targeting, summoning, and attacking.
## Draws a bezier curve from source to target with a glowing tip.
class_name CurvedArrow
extends Node2D

# ─── Signals ──────────────────────────────────────────────────────────────────

signal animation_completed()

# ─── Constants ────────────────────────────────────────────────────────────────

const ARROW_HEAD_SIZE = 12.0
const ARROW_HEAD_ANGLE = 0.5  # Radians (about 30 degrees)
const DEFAULT_DURATION = 0.3

# ─── Properties ──────────────────────────────────────────────────────────────

var start_position: Vector2 = Vector2.ZERO
var end_position: Vector2 = Vector2.ZERO
var color: Color = Color(1.0, 0.8, 0.2)  # Gold default
var glow_color: Color = Color(1.0, 0.8, 0.2)
var line_width: float = 3.0
var arrow_duration: float = DEFAULT_DURATION
var is_animated: bool = true
var is_destroyed: bool = false

# ─── Internal State ───────────────────────────────────────────────────────────

var _progress: float = 0.0
var _control_point: Vector2 = Vector2.ZERO
var _target_control_point: Vector2 = Vector2.ZERO
var _is_animating: bool = false

# ─── Public API ──────────────────────────────────────────────────────────────

## Show arrow from start to end with optional curve offset
func show_arrow(
	start: Vector2,
	end: Vector2,
	curve_offset: Vector2 = Vector2(0, -80),
	arrow_color: Color = Color(1.0, 0.8, 0.2),
	duration: float = DEFAULT_DURATION,
	animated: bool = true
) -> void:
	start_position = start
	end_position = end
	color = arrow_color
	glow_color = color.lightened(0.3)
	arrow_duration = duration
	is_animated = animated
	_progress = 0.0
	_is_animating = true
	is_destroyed = false
	
	# Calculate control point for bezier curve
	var mid_point = (start + end) / 2.0
	var direction = (end - start).normalized()
	
	# Offset perpendicular to the line direction
	var perp = Vector2(-direction.y, direction.x)
	
	# Use the curve offset or calculate based on distance
	if curve_offset == Vector2.ZERO:
		var distance = start.distance_to(end)
		var offset_amount = min(distance * 0.3, 100.0)
		_target_control_point = mid_point + perp * offset_amount
	else:
		_target_control_point = mid_point + curve_offset
	
	# Start with control point at start for smooth animation
	_control_point = start + perp * 0.1
	
	# Start the animation
	if animated:
		var tween := create_tween()
		tween.tween_method(_update_progress, 0.0, 1.0, duration)
		tween.tween_callback(_on_animation_complete)
	else:
		_progress = 1.0
		_control_point = _target_control_point
		queue_redraw()

## Update arrow to a new end position (for tracking moving targets)
func update_end(new_end: Vector2) -> void:
	end_position = new_end
	var mid_point = (start_position + end_position) / 2.0
	var direction = (end_position - start_position).normalized()
	var perp = Vector2(-direction.y, direction.x)
	_target_control_point = mid_point + perp * 80.0
	queue_redraw()

## Destroy the arrow with a fade-out animation
func destroy_arrow(fade_duration: float = 0.15) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)

# ─── Internal Methods ─────────────────────────────────────────────────────────

func _update_progress(value: float) -> void:
	_progress = value
	# Ease in-out for smoother motion
	var eased = _ease_in_out(value)
	_control_point = start_position.lerp(_target_control_point, eased)
	queue_redraw()

func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _on_animation_complete() -> void:
	_is_animating = false
	animation_completed.emit()

func _draw() -> void:
	if is_destroyed:
		return
	
	# Don't draw if progress is 0 or start/end are invalid
	if _progress <= 0.0 or start_position.distance_to(end_position) < 1.0:
		return
	
	# Calculate current end position based on progress
	var current_end = start_position.lerp(end_position, _progress)
	
	# Draw glow trail (multiple layers)
	_draw_glow_trail(start_position, current_end)
	
	# Draw main line
	_draw_bezier_curve(start_position, current_end)
	
	# Draw arrow head
	_draw_arrow_head(current_end)

func _draw_glow_trail(start: Vector2, end: Vector2) -> void:
	# Draw multiple glow layers with decreasing opacity and increasing width
	var glow_widths = [8.0, 12.0, 16.0]
	var glow_opacities = [0.3, 0.15, 0.06]
	
	for i in glow_widths.size():
		var width = glow_widths[i]
		var opacity = glow_opacities[i]
		var glow_color_layer = glow_color
		glow_color_layer.a = opacity
		
		_draw_bezier_curve(start, end, glow_color_layer, width)

func _draw_bezier_curve(start: Vector2, end: Vector2, draw_color: Color = color, width: float = line_width) -> void:
	# Calculate current control point
	var progress = _progress
	var current_control = start.lerp(_control_point, progress)
	
	# Draw bezier curve using quadratic bezier
	var points: PackedVector2Array = []
	var segments = 20
	
	for i in range(segments + 1):
		var t = float(i) / segments
		var point = _quadratic_bezier(start, current_control, end, t)
		points.append(point)
	
	# Draw the curve
	draw_polyline(points, draw_color, width, true)
	
	# Draw glow dots along the curve for extra shine
	if width >= 3.0:
		for i in range(0, segments, 2):
			var t = float(i) / segments
			var point = _quadratic_bezier(start, current_control, end, t)
			draw_circle(point, width * 0.3, draw_color.lightened(0.5))

func _draw_arrow_head(position: Vector2) -> void:
	# Calculate direction at the end of the curve
	var current_control = start_position.lerp(_control_point, _progress)
	var end_t = 0.95
	var near_end = _quadratic_bezier(
		start_position,
		current_control,
		end_position,
		end_t
	)
	
	var direction = (position - near_end).normalized()
	if direction.length() < 0.1:
		direction = Vector2.UP
	
	# Create arrow head points
	var tip = position
	var left = tip + direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var right = tip + direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	
	# Draw filled arrow head
	var points = PackedVector2Array([tip, left, right])
	draw_colored_polygon(points, color)
	
	# Draw glow arrow head (slightly larger, transparent)
	var glow_size = ARROW_HEAD_SIZE * 1.4
	var glow_left = tip + direction.rotated(ARROW_HEAD_ANGLE) * glow_size
	var glow_right = tip + direction.rotated(-ARROW_HEAD_ANGLE) * glow_size
	var glow_points = PackedVector2Array([tip, glow_left, glow_right])
	
	var glow_color_layer = glow_color
	glow_color_layer.a = 0.3
	draw_colored_polygon(glow_points, glow_color_layer)

func _quadratic_bezier(start: Vector2, control: Vector2, end: Vector2, t: float) -> Vector2:
	var one_minus_t = 1.0 - t
	return one_minus_t * one_minus_t * start + 2.0 * one_minus_t * t * control + t * t * end
# ─── Static Factory Methods ──────────────────────────────────────────────────

## Create a targeting arrow (blue/cyan)
static func targeting(start: Vector2, end: Vector2, duration: float = DEFAULT_DURATION) -> CurvedArrow:
	var arrow = CurvedArrow.new()
	arrow.show_arrow(
		start, end,
		Vector2(0, -60),
		Color(0.2, 0.8, 1.0),  # Cyan
		duration
	)
	return arrow

## Create a summoning arrow (gold)
static func summoning(start: Vector2, end: Vector2, duration: float = DEFAULT_DURATION) -> CurvedArrow:
	var arrow = CurvedArrow.new()
	arrow.show_arrow(
		start, end,
		Vector2(0, -80),
		Color(1.0, 0.8, 0.2),  # Gold
		duration
	)
	return arrow

## Create an attack arrow (red)
static func attacking(start: Vector2, end: Vector2, duration: float = DEFAULT_DURATION) -> CurvedArrow:
	var arrow = CurvedArrow.new()
	arrow.show_arrow(
		start, end,
		Vector2(0, -40),
		Color(1.0, 0.2, 0.1),  # Red
		duration
	)
	return arrow

## Create an effect arrow (purple)
static func effect_arrow(start: Vector2, end: Vector2, duration: float = DEFAULT_DURATION) -> CurvedArrow:
	var arrow = CurvedArrow.new()
	arrow.show_arrow(
		start, end,
		Vector2(0, -60),
		Color(0.7, 0.1, 1.0),  # Purple
		duration
	)
	return arrow
