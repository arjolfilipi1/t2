## CardView.gd
## Visual representation of a single CardInstance.
## Handles:
##   - Face-up / face-down display with flip animation
##   - ATK/DEF/Level stat labels
##   - Glow shader states (idle, targetable, targeted, activatable, attacking)
##   - ATK/DEF position rotation
##   - Counter badge display
##   - Drag-and-drop signalling (actual drag logic lives in BoardView)
##   - Click → signal for BoardView to decide what to do
##
## Scene tree expected layout:
##   CardView (Control, this script)
##   ├─ Pivot (Node2D)          ← flips around Y axis for card-flip animation
##   │   ├─ FrontFace (TextureRect)
##   │   │   ├─ Artwork (TextureRect)
##   │   │   ├─ NameLabel (Label)
##   │   │   ├─ TypeBar (Label)         ← "DARK / Dragon / Effect"
##   │   │   ├─ LevelRow (HBoxContainer)
##   │   │   │   └─ StarTemplate (TextureRect)   [hidden, duplicated at runtime]
##   │   │   ├─ AtkLabel (Label)
##   │   │   ├─ DefLabel (Label)
##   │   │   └─ CounterBadge (Label)
##   │   └─ BackFace (TextureRect)
##   ├─ GlowRect (ColorRect)    ← ShaderMaterial with glow.gdshader
##   ├─ SelectionBorder (Panel) ← visible when selected
##   └─ TooltipTrigger (Area2D) ← hover for full card text popup
##
## NOTE: This file ships as pure GDScript. The matching .tscn is generated
## by BoardTestScene.gd at runtime so no external .tscn asset is required
## for testing. In production, replace with a proper .tscn in res://ui/card/.
class_name CardView
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Player clicked this card. BoardView decides context (select, target, etc.)
signal card_clicked(view: CardView)

## Player right-clicked — request inspection popup.
signal card_inspected(view: CardView)

## Drag started from this card.
signal drag_started(view: CardView, offset: Vector2)

# ─── Visual State ─────────────────────────────────────────────────────────────

enum GlowState {
	NONE,           ## No glow
	SUMMONABLE,     ## Blue - can be Normal Summoned/Set
	ACTIVATABLE,    ## Yellow/Orange - can activate effect
	TARGETABLE,     ## Cyan - valid target for effect
	TARGETED,       ## Gold - selected as target
	ATTACKING,      ## Red - declaring attack
	SELECTED,       ## White - currently selected
	CHAIN_LINK,     ## Purple - on the effect chain
	NEGATED,        ## Red - effect was negated
}

# Colors per glow state - Master Duel style
const GLOW_COLORS := {
	GlowState.NONE:        Color(0, 0, 0, 0),
	GlowState.SUMMONABLE:  Color(0.2, 0.6, 1.0, 1.0),    # Blue
	GlowState.ACTIVATABLE: Color(1.0, 0.7, 0.1, 1.0),    # Yellow/Orange
	GlowState.TARGETABLE:  Color(0.2, 0.8, 1.0, 1.0),    # Light Blue/Cyan
	GlowState.TARGETED:    Color(1.0, 0.85, 0.1, 1.0),   # Gold
	GlowState.ATTACKING:   Color(1.0, 0.2, 0.1, 1.0),    # Red
	GlowState.SELECTED:    Color(1.0, 1.0, 1.0, 1.0),    # White
	GlowState.CHAIN_LINK:  Color(0.7, 0.1, 1.0, 1.0),    # Purple
	GlowState.NEGATED:     Color(0.8, 0.2, 0.2, 1.0),    # Dark Red
}

# Pulse speed for different glow types
const GLOW_PULSE_SPEED := {
	GlowState.SUMMONABLE:  1.2,  # Fast pulse
	GlowState.ACTIVATABLE: 1.5,  # Fast pulse
	GlowState.TARGETABLE:  0.8,  # Medium pulse
	GlowState.TARGETED:    0.0,  # No pulse (solid)
	GlowState.CHAIN_LINK:  2.0,  # Fast pulse
}

# ─── Constants ────────────────────────────────────────────────────────────────

const CARD_W         := 100.0
const CARD_H         := 145.0
const FLIP_DURATION  := 0.28   ## seconds for full face flip
const MOVE_DURATION  := 0.22   ## seconds for zone-to-zone tween
const HOVER_LIFT     := -14.0  ## pixels to rise on hover
const ATK_ROT_DEG    := 0.0
const DEF_ROT_DEG    := 90.0   ## DEF position = rotated 90°

#─── Index numbers ────────────────────────────────────────────────────────────
const Z_INDEX_HAND = 5      # Hand cards are above most things
const Z_INDEX_FIELD = 3     # Field cards (monsters, spells)
const Z_INDEX_HOVER = 10    # Hovered cards (above everything)
const Z_INDEX_ATTACKING = 8 # Attacking cards

# ─── Node References (assigned in _ready) ────────────────────────────────────
# Types are kept as their base classes (Control/Node) where CardViewBuilder
# creates different concrete types than a hand-authored .tscn would.
# Access is always guarded through is_node_ready() in bind().

@onready var pivot:            Control       = $VisualRoot/Pivot
@onready var visual_root:      Control       = $VisualRoot
@onready var front_face:       Control       = $VisualRoot/Pivot/FrontFace   ## Control in builder, TextureRect in .tscn
@onready var back_face:        Control       = $VisualRoot/Pivot/BackFace    ## ColorRect in builder
@onready var artwork:          Control       = $VisualRoot/Pivot/FrontFace/Artwork  ## ColorRect or TextureRect
@onready var name_label:       Label         = $VisualRoot/Pivot/FrontFace/NameLabel
@onready var bg:               ColorRect         = $VisualRoot/Pivot/FrontFace/Background
@onready var type_bar:         Label         = $VisualRoot/Pivot/FrontFace/TypeBar
@onready var level_row:        HBoxContainer = $VisualRoot/Pivot/FrontFace/LevelRow
@onready var atk_label:        Label         = $VisualRoot/Pivot/FrontFace/AtkLabel
@onready var def_label:        Label         = $VisualRoot/Pivot/FrontFace/DefLabel
@onready var counter_badge:    Label         = $VisualRoot/Pivot/FrontFace/CounterBadge
@onready var glow_rect:        ColorRect     = $VisualRoot/GlowRect
@onready var hover_rect:       ColorRect     = $VisualRoot/hoverRect
@onready var selection_border: Control       = $VisualRoot/SelectionBorder  ## Panel in .tscn, Control ok

# ─── State ────────────────────────────────────────────────────────────────────

var card: CardInstance = null     ## The domain object this view represents
var glow_state: GlowState = GlowState.NONE
var _is_face_up: bool = false
var _is_hovered: bool = false
var original_pos:Vector2
# ─── Animation Priority System ──────────────────────────────────────────────────
enum AnimPriority {
	IDLE = 0,
	HOVER = 1,
	MOVE = 2,
	EFFECT = 3,
	ATTACK = 4,
	DESTROY = 5,  # Highest - can't be interrupted
}

# ─── Animation State ──────────────────────────────────────────────────────────
var _current_priority: AnimPriority = AnimPriority.IDLE
var _is_performing_action: bool = false

# Separate tweens for different animation types
var _hover_tween: Tween = null
var _move_tween: Tween = null
var _action_tween: Tween = null
var _flip_tween: Tween = null
var _glow_tween: Tween = null
var _selection_tween: Tween = null

# ─── Initialization ───────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	#size = Vector2(CARD_W, CARD_H)
	pivot_offset = Vector2(CARD_W / 2.0, CARD_H / 2.0)

	visual_root.mouse_entered.connect(_on_mouse_entered)
	visual_root.mouse_exited.connect(_on_mouse_exited)
	visual_root.gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	print("created node for ",card.definition.card_name)
	selection_border.visible = false
	counter_badge.visible    = false
	#_apply_glow_shader()

	# If bind() was called before we entered the tree, finish wiring now.
	if card != null:
		_connect_card_signals()
		_refresh_display()
	

func _connect_card_signals() -> void:
	if card == null:
		return
	if not card.stat_changed.is_connected(_on_stat_changed):
		card.stat_changed.connect(_on_stat_changed)
	if not card.counter_changed.is_connected(_on_counter_changed):
		card.counter_changed.connect(_on_counter_changed)

## Bind this view to a CardInstance.
## Safe to call before or after the node enters the scene tree.
func bind(card_instance: CardInstance) -> void:
	# Disconnect previous card signals
	if card != null:
		if card.stat_changed.is_connected(_on_stat_changed):
			card.stat_changed.disconnect(_on_stat_changed)
		if card.counter_changed.is_connected(_on_counter_changed):
			card.counter_changed.disconnect(_on_counter_changed)

	card = card_instance

	# Only refresh display if _ready() has already run (nodes exist).
	# If the node hasn't entered the tree yet, _ready() will call
	# _refresh_display() itself once it fires.
	if is_node_ready():
		if card == null:
			_show_empty()
		else:
			_connect_card_signals()
			_refresh_display()
	else:
		ready.connect(_refresh_display,CONNECT_ONE_SHOT)
# ─── Display Refresh ──────────────────────────────────────────────────────────

func _refresh_display() -> void:
	if card == null:
		_show_empty()
		return

	var def := card.definition
	_is_face_up = card.is_face_up()

	front_face.visible = _is_face_up
	back_face.visible  = not _is_face_up

	if not _is_face_up:
		return

	# Name
	name_label.text = def.card_name

	# Artwork (placeholder colour rect if no texture)
	if artwork is TextureRect:
		var tr := artwork as TextureRect
		if def.artwork != null:
			tr.texture  = def.artwork
			tr.modulate = Color.WHITE
		else:
			tr.texture  = null
			tr.modulate = _attribute_color(def.attribute)
	elif artwork is ColorRect:
		# Builder path: tint the ColorRect to reflect the attribute
		var cr := artwork as ColorRect
		cr.color = _attribute_color(def.attribute)

	# Type bar
	if def.is_monster():
		var attr_str :String = CardDefinition.Attribute.keys()[def.attribute]
		type_bar.text = "%s / %s / %s" % [attr_str, def.monster_type, CardDefinition.MonsterKind.keys()[def.monster_kind]]
		match def.attribute:
			CardDefinition.Attribute.DARK: type_bar.modulate = Color(0.5, 0.1, 0.6)
			CardDefinition.Attribute.LIGHT: type_bar.modulate = Color(0.9, 0.9, 0.5)
			CardDefinition.Attribute.FIRE: type_bar.modulate = Color(0.9, 0.3, 0.1)
			CardDefinition.Attribute.WATER: type_bar.modulate = Color(0.2, 0.5, 0.9)
			CardDefinition.Attribute.EARTH: type_bar.modulate = Color(0.5, 0.4, 0.2)
			CardDefinition.Attribute.WIND: type_bar.modulate = Color(0.3, 0.8, 0.3)
	elif def.is_spell():
		type_bar.text = "SPELL — %s" % CardDefinition.SpellType.keys()[def.spell_type]
		bg.modulate = Color(0.3, 0.8, 0.3)
	else:
		type_bar.text = "TRAP — %s" % CardDefinition.TrapType.keys()[def.trap_type]
		bg.modulate = Color(0.9, 0.3, 0.1)

	# Stars / rank / link
	_refresh_level_stars(def.level if def.is_monster() else 0, def.monster_kind)

	# Stats
	if def.is_monster():
		atk_label.text = "ATK  %d" % card.get_atk()
		def_label.text = "DEF  %d" % card.get_def()
		atk_label.visible = true
		def_label.visible = def.monster_kind != CardDefinition.MonsterKind.LINK
	else:
		atk_label.visible = false
		def_label.visible = false

	# Battle position rotation
	_apply_position_rotation()

	# Counters
	_refresh_counters()

func _refresh_level_stars(level: int, kind: CardDefinition.MonsterKind) -> void:
	for child in level_row.get_children():
		child.queue_free()
	if level == 0:
		return

	for i in level:
		var star := ColorRect.new()
		star.custom_minimum_size = Vector2(8, 8)
		var is_xyz := kind == CardDefinition.MonsterKind.XYZ
		star.color = Color(0.1, 0.1, 0.1) if is_xyz else Color(1.0, 0.82, 0.0)
		level_row.add_child(star)

func _refresh_counters() -> void:
	if card == null or card.counters.is_empty():
		counter_badge.visible = false
		return
	var parts: Array[String] = []
	for key in card.counters:
		parts.append("%s×%d" % [key, card.counters[key]])
	counter_badge.text = " | ".join(parts)
	counter_badge.visible = true

func _show_empty() -> void:
	if not is_node_ready():
		return
	front_face.visible = false
	back_face.visible  = false
	glow_rect.visible  = false

func _apply_position_rotation() -> void:
	if card == null:
		return
	var target_rot := 0.0
	if card.is_in_def_position():
		target_rot = deg_to_rad(DEF_ROT_DEG)
	if pivot.rotation != target_rot:
		var tw := create_tween()
		tw.tween_property(pivot, "rotation", target_rot, 0.18)

# ─── Flip Animation ───────────────────────────────────────────────────────────

## Animate flip from current face state to the new one.
func flip_to(face_up: bool, instant: bool = false) -> Signal:
	if _is_face_up == face_up or not is_node_ready():
		return _create_instant_signal()
	
	_is_face_up = face_up
	set_priority(AnimPriority.MOVE)

	if instant:
		front_face.visible = face_up
		back_face.visible = not face_up
		set_priority(AnimPriority.IDLE)
		return _create_instant_signal()

	_kill_all_tweens()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_SINE)

	tw.tween_property(pivot, "scale:x", 0.0, FLIP_DURATION * 0.5)
	tw.tween_callback(func():
		front_face.visible = face_up
		back_face.visible = not face_up
	)
	tw.tween_property(pivot, "scale:x", 1.0, FLIP_DURATION * 0.5)

	_flip_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_flip_tween = null
	)

	return tw.finished

func _create_instant_signal() -> Signal:
	var helper := _InstantSignalHelper.new()
	add_child(helper)
	helper.fire()
	return helper.done
class _InstantSignalHelper extends Node:
	signal done()
	func fire() -> void:
		call_deferred("_emit_and_free")
	func _emit_and_free() -> void:
		done.emit()
		queue_free()

# ─── Glow State ───────────────────────────────────────────────────────────────

func set_glow(new_state: GlowState) -> void:
	if glow_state == new_state:
		return
	glow_state = new_state
	_update_glow()

func _update_glow() -> void:
	var color: Color = GLOW_COLORS[glow_state]
	var pulse_speed: float = GLOW_PULSE_SPEED.get(glow_state, 1.0)

	if glow_rect.material and glow_rect.material is ShaderMaterial:
		glow_rect.material.set_shader_parameter(&"glow_color", color)
		glow_rect.material.set_shader_parameter(&"glow_enabled", glow_state != GlowState.NONE)
		glow_rect.material.set_shader_parameter(&"pulse_speed", pulse_speed)
		glow_rect.material.set_shader_parameter(&"card_w",CARD_W)
		glow_rect.material.set_shader_parameter(&"card_h",CARD_H)
	
	glow_rect.visible = glow_state != GlowState.NONE
	
	# Start/stop pulse animation
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	
	if glow_state in [GlowState.SUMMONABLE, GlowState.ACTIVATABLE, GlowState.TARGETABLE, GlowState.CHAIN_LINK]:
		_start_pulse_animation(pulse_speed)


func _start_pulse_animation(speed: float = 1.0) -> void:
	if not glow_rect.material or not (glow_rect.material is ShaderMaterial):
		return
	
	var tw := create_tween()
	tw.set_loops()
	tw.set_ease(Tween.EASE_IN_OUT)
	
	# Pulse between 0.5 and 1.0 intensity
	var duration = 0.7 / speed
	tw.tween_method(func(v: float):
		if glow_rect.material and glow_rect.material is ShaderMaterial:
			glow_rect.material.set_shader_parameter(&"glow_intensity", v)
	, 0.6, 1.0, duration)
	tw.tween_method(func(v: float):
		if glow_rect.material and glow_rect.material is ShaderMaterial:
			glow_rect.material.set_shader_parameter(&"glow_intensity", v)
	, 1.0, 0.6, duration)


func _apply_glow_shader() -> void:
	# Inline shader — no external .gdshader file needed
	var shader :Shader = glow_rect.material.shader
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"card_w", CARD_W)
	mat.set_shader_parameter(&"card_h", CARD_H)
	glow_rect.material = mat
	glow_rect.size     = Vector2(CARD_W, CARD_H)
	glow_rect.position = Vector2.ZERO

# ─── Move Animation ───────────────────────────────────────────────────────────
func _kill_all_tweens() -> void:
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
		_hover_tween = null
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()
		_action_tween = null
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()
		_flip_tween = null
func can_interrupt_with(priority: AnimPriority) -> bool:
	return priority > _current_priority

func set_priority(priority: AnimPriority) -> void:
	_current_priority = priority
	if priority >= AnimPriority.MOVE:
		# Kill hover when we start a high-priority animation
		_kill_hover_tween()

func _kill_hover_tween() -> void:
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
		_hover_tween = null


	
## Animate this card moving to a new global position.
## Called by BoardView after it repositions the card's parent container.
func animate_move_to(target_global: Vector2,target_rotation:=0,target_scale:=Vector2.ONE) -> Signal:
	set_priority(AnimPriority.HOVER)
	#_kill_hover_tween()
	var tw    := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_parallel(true)
	tw.tween_property(self,"position",target_global,0.15)
	tw.tween_property(self,"rotation",target_rotation,0.15)
	tw.tween_property(self,"scale",target_scale,0.15)
	_move_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_move_tween = null
	)
	return tw.finished
## Destruction burst: scale down and fade, then call done_callback.
func animate_destroy() -> Signal:
	set_priority(AnimPriority.DESTROY)
	_kill_all_tweens()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_property(self, "scale", Vector2(1.4, 1.4), 0.2)
	tw.chain().tween_property(self, "scale", Vector2(0.0, 0.0), 0.15)
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)

	return tw.finished
## Summon pop-in: start slightly scaled down, bounce up.
func animate_summon() -> Signal:
	set_priority(AnimPriority.MOVE)
	_kill_hover_tween()
	_is_hovered = false
	hover_rect.visible = false
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)

	return tw.finished
	
# ─── Attack Animation ─────────────────────────────────────────────────────────

## Lunges toward `target_global`, holds briefly (impact frame), then springs
## back to its original position. Used for the attacking card during the
## damage step. Returns "finished" so the caller can sequence destruction
## or LP damage feedback right after impact.
func animate_attack_lunge(target_global: Vector2) -> Signal:
	print("animating attack for ",card.definition.card_name)
	set_priority(AnimPriority.ATTACK)
	_kill_hover_tween()
	
	var home      := global_position
	var direction := (target_global - home)
	var lunge_pos := home + direction * 0.6

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "global_position", lunge_pos, 0.18)
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.06)
	tw.tween_interval(0.08)
	tw.tween_property(self, "global_position", home, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.22)
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)
	return tw.finished

func animate_take_hit() -> Signal:
	set_priority(AnimPriority.ATTACK)
	var particles = GPUParticles2D.new()
	particles.amount = 20
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.emitting = true
	particles.position = Vector2(CARD_W/2, CARD_H/2)
	add_child(particles)

	var home := position
	var tw   := create_tween()
	tw.set_parallel(false)

	## Flash white via modulate spike
	tw.tween_property(self, "modulate", Color(2.0, 2.0, 2.0), 0.05)
	tw.tween_property(self, "modulate", Color.WHITE, 0.10)

	## Shake — small left-right jitter
	var shake_tw := create_tween()
	shake_tw.set_parallel(false)
	for i in 4:
		var offset := Vector2((4.0 if i % 2 == 0 else -4.0), 0)
		shake_tw.tween_property(self, "position", home + offset, 0.03)
	shake_tw.tween_property(self, "position", home, 0.03)
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)
	return tw.finished

# ─── Effect Activation / Resolution Animation ─────────────────────────────────

## Played when this card's effect is pushed onto the chain (activation).
## A bright outward pulse distinct from the standing CHAIN_LINK glow —
## marks the *moment* of activation rather than the held state while it
## sits on the chain.
func animate_effect_activate() -> Signal:
	set_priority(AnimPriority.EFFECT)
	var original_state := glow_state
	set_glow(GlowState.CHAIN_LINK)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(self, "scale", Vector2.ONE, 0.15)

	## Card itself does a brief glow-flash via modulate, independent of GlowState
	var flash_tw := create_tween()
	flash_tw.tween_property(self, "modulate", Color(1.3, 1.3, 1.3), 0.08)
	flash_tw.tween_property(self, "modulate", Color.WHITE, 0.12)
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)

	return tw.finished

## Played when this card's chain link resolves. Distinct from activation —
## a soft outward ring rather than a scale pulse, signalling "effect has
## taken place" rather than "effect has been declared".
func animate_effect_resolve() -> Signal:
	set_priority(AnimPriority.EFFECT)
	var ring := _ResolveRing.new()
	ring.size     = Vector2(CARD_W, CARD_H)
	ring.position = Vector2.ZERO
	add_child(ring)

	var tw := create_tween()
	tw.tween_method(func(t: float):
		ring.progress = t
		ring.queue_redraw()
	, 0.0, 1.0, 0.4)
	tw.tween_callback(func(): ring.queue_free())
	_action_tween = tw
	tw.finished.connect(func():
		set_priority(AnimPriority.IDLE)
		_action_tween = null
	)

	return tw.finished
# ─── Selection ────────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	selection_border.visible = selected
	if selected:
		set_glow(GlowState.SELECTED)
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(selection_border, "modulate:a", 0.5, 0.5)
		tw.tween_property(selection_border, "modulate:a", 1.0, 0.5)
		_selection_tween = tw

	else:
		if _selection_tween:
			_selection_tween.kill()
		set_glow(GlowState.NONE)
func debug_glow()->void:
	print("gr pos:",glow_rect.position)
	print("gr size:",glow_rect.size)
	print("cv size:",size)
	print("cv po:",pivot_offset)
# ─── Hover ────────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	if _current_priority >= AnimPriority.MOVE:
		return
	if _is_hovered:
		return
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_is_hovered = true
	hover_rect.visible = true
	print("gr:",glow_rect.visible,"hr:",hover_rect.visible)
	z_index = Z_INDEX_HOVER
	set_priority(AnimPriority.HOVER)
	original_pos = position

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT_IN)
	tw.tween_property(visual_root, "position:y", visual_root.position.y + HOVER_LIFT, 0.08)
	tw.parallel().tween_property(visual_root, "scale", Vector2(1.06, 1.06), 0.08)
	#tw.parallel().tween_property(self, "rotation", deg_to_rad(2.0), 0.12)

	_hover_tween = tw
	print("card hover")
	
func _on_mouse_exited() -> void:
	if _current_priority >= AnimPriority.MOVE:
		return
	if not _is_hovered:
		return
	_kill_hover_tween()
	var target_y_pos: float
	if card.is_on_field() or card.is_banished() or card.is_in_graveyard():
		target_y_pos = 0.0
	else:
		target_y_pos = position.y - HOVER_LIFT
	_is_hovered = false
	hover_rect.visible = false
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT_IN)
	tw.tween_property(visual_root, "position",Vector2.ZERO , 0.12)
	tw.parallel().tween_property(visual_root, "scale", Vector2.ONE, 0.12)
	_hover_tween = tw
	z_index = Z_INDEX_FIELD if card.is_on_field() else Z_INDEX_HAND
func is_on_field() -> bool:
	if card == null:
		return false
	return card.is_on_field()
# ─── Input ────────────────────────────────────────────────────────────────────
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				print("clicked: ",card.definition.card_name , " stack: ", get_stack())
				card_clicked.emit(self)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				print("gr:",glow_rect.visible,"hr:",hover_rect.visible)
				card_inspected.emit(self)

# ─── Domain Signal Handlers ───────────────────────────────────────────────────

func _on_stat_changed(_card: CardInstance, stat: StringName, _old: int, new_val: int) -> void:
	var label = atk_label if stat == &"atk" else def_label
	label.text = "ATK  %d" % new_val if stat == &"atk" else "DEF  %d" % new_val
	# ✅ Flash stat change
	label.modulate = Color.GREEN if new_val > _old else Color.RED
	var tw = create_tween()
	tw.tween_property(label, "modulate", Color.WHITE, 0.5)


func _on_counter_changed(_card: CardInstance, _name: StringName, _old: int, _new: int) -> void:
	_refresh_counters()

# ─── Utilities ────────────────────────────────────────────────────────────────

func _attribute_color(attr: CardDefinition.Attribute) -> Color:
	match attr:
		CardDefinition.Attribute.DARK:   return Color(0.25, 0.05, 0.35)
		CardDefinition.Attribute.LIGHT:  return Color(0.95, 0.95, 0.75)
		CardDefinition.Attribute.EARTH:  return Color(0.45, 0.30, 0.15)
		CardDefinition.Attribute.WATER:  return Color(0.10, 0.35, 0.70)
		CardDefinition.Attribute.FIRE:   return Color(0.85, 0.20, 0.05)
		CardDefinition.Attribute.WIND:   return Color(0.30, 0.70, 0.30)
		CardDefinition.Attribute.DIVINE: return Color(0.90, 0.75, 0.20)
	return Color(0.3, 0.3, 0.3)
func reset_for_field() ->void:
	_kill_all_tweens()
	_is_performing_action = false
	set_priority(AnimPriority.IDLE)
	rotation =0.0
	z_index = Z_INDEX_FIELD
	_is_hovered = false
	
	if hover_rect:
		hover_rect.visible = false
	scale = Vector2.ONE
	position = Vector2.ZERO
	modulate = Color.WHITE
func _to_string() -> String:
	var name :String= card.definition.card_name if card else "empty"
	return "CardView(%s)" % name
# ──────────────────────────────────────────────────────────────────────────────
# Inner class: expanding ring drawn for animate_effect_resolve()
# ──────────────────────────────────────────────────────────────────────────────

class _ResolveRing extends Control:
	## 0.0 → 1.0 animation progress, driven by the tween in animate_effect_resolve().
	var progress: float = 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w / 2.0
		var cy := h / 2.0
		var max_radius :float = max(w, h) * 0.75

		var radius := max_radius * progress
		var alpha  := 1.0 - progress   ## fades out as it expands
		var color  := Color(0.85, 0.65, 1.0, alpha * 0.8)   ## soft violet — resolution colour

		draw_arc(Vector2(cx, cy), radius, 0, TAU, 32, color, 3.0, true)
