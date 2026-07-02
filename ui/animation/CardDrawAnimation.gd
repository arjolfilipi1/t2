## CardDrawAnimation.gd
## Master Duel-style card draw animation.
## Card slides from deck to hand with a trail effect.
class_name CardDrawAnimation
extends Node2D

# ─── Signals ──────────────────────────────────────────────────────────────────

signal animation_completed()

# ─── Properties ──────────────────────────────────────────────────────────────

var card: CardInstance = null
var start_position: Vector2 = Vector2.ZERO
var end_position: Vector2 = Vector2.ZERO
var duration: float = 0.4
var is_face_down: bool = true

# ─── Internal State ──────────────────────────────────────────────────────────

var _progress: float = 0.0
var _card_view: CardView = null
var _trail_particles: Array[Node2D] = []
var _is_animating: bool = false

# ─── Public API ──────────────────────────────────────────────────────────────

## Play the draw animation
func play_draw_animation(
	card_instance: CardInstance,
	start: Vector2,
	end: Vector2,
	draw_duration: float = 0.4,
	face_down: bool = true
) -> void:
	card = card_instance
	start_position = start
	end_position = end
	duration = draw_duration
	is_face_down = face_down
	
	# Get or create card view
	_card_view = _get_or_create_card_view(card)
	if _card_view == null:
		animation_completed.emit()
		return
	
	# Setup card view
	_card_view.global_position = start - Vector2(CardView.CARD_W / 2, CardView.CARD_H / 2)
	_card_view.flip_to(not face_down, true)
	_card_view.kill_all_tweens()
	_card_view.scale = Vector2(1.0, 1.0)
	_card_view.rotation = 0.0
	_card_view.modulate = Color.WHITE
	_card_view.z_index = 10  # Above everything during animation
	
	if _card_view.get_parent() != self:
		if _card_view.get_parent():
			_card_view.reparent(self)
		else:
			add_child(_card_view)
	
	# Start animation
	_is_animating = true
	_progress = 0.0
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_method(_update_draw_progress, 0.0, 1.0, duration)
	tween.tween_callback(_on_draw_complete)

# ─── Internal Methods ─────────────────────────────────────────────────────────

func _update_draw_progress(value: float) -> void:
	_progress = value
	_update_card_position(value)
	_update_trail(value)

func _update_card_position(value: float) -> void:
	if _card_view == null:
		return
	
	# Ease curve for smooth motion
	var eased = _ease_in_out(value)
	
	# Move from start to end with slight arc
	var pos = start_position.lerp(end_position, eased)
	var arc_offset = sin(eased * PI) * -40.0  # Arc upward
	pos.y += arc_offset
	
	_card_view.global_position = pos - Vector2(CardView.CARD_W / 2, CardView.CARD_H / 2)
	
	# Slight rotation during draw
	var rot = sin(value * PI) * 0.1
	_card_view.rotation = rot

func _update_trail(value: float) -> void:
	# Create trail particles as the card moves
	if value > 0.1 and value < 0.9:
		if int(value * 10) % 2 == 0:
			_create_trail_particle()

func _create_trail_particle() -> void:
	if _card_view == null:
		return
	
	var particle = ColorRect.new()
	particle.size = Vector2(8, 12)
	particle.color = Color(0.8, 0.7, 0.4, 0.4)
	particle.position = _card_view.global_position + Vector2(
		randf_range(-5, 5),
		randf_range(-5, 5)
	)
	particle.z_index = 9
	add_child(particle)
	_trail_particles.append(particle)
	
	# Animate particle fading out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "modulate:a", 0.0, 0.3)
	tween.tween_property(particle, "scale", Vector2(0.5, 0.5), 0.3)
	tween.tween_callback(particle.queue_free)

func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _on_draw_complete() -> void:
	_is_animating = false
	
	# Clean up trail particles
	for particle in _trail_particles:
		if is_instance_valid(particle):
			particle.queue_free()
	_trail_particles.clear()
	
	# Finalize card position
	if _card_view:
		_card_view.global_position = end_position - Vector2(CardView.CARD_W / 2, CardView.CARD_H / 2)
		_card_view.z_index = 5  # Hand level
		_card_view.rotation = 0.0
		_card_view.flip_to(not is_face_down, true)
		
		# Reparent to board view
		var board = get_parent()  # Should be BoardView
		if board and board is BoardView:
			_card_view.reparent(board)
			board.refresh_hand(card.controller)
	
	animation_completed.emit()
	queue_free()

func _get_or_create_card_view(card_instance: CardInstance) -> CardView:
	# Find the board view
	var board = get_parent()
	if board and board is BoardView:
		return board.get_or_create_card_view(card_instance)
	return null

# ─── Static Factory Method ──────────────────────────────────────────────────

static func create_draw_animation(
	card: CardInstance,
	start: Vector2,
	end: Vector2,
	duration: float = 0.4
) -> CardDrawAnimation:
	var anim = CardDrawAnimation.new()
	anim.play_draw_animation(card, start, end, duration)
	return anim
