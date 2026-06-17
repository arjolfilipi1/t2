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
	NONE,        ## Normal card, no highlight
	ACTIVATABLE, ## Green — player can activate this card/effect
	TARGETABLE,  ## Blue — this card is a valid target for an effect
	TARGETED,    ## Gold — this card has been selected as a target
	ATTACKING,   ## Red — this monster is declaring an attack
	SELECTED,    ## White — currently selected by the player
	CHAIN_LINK,  ## Purple — this card is on the effect chain
}

# Colors per glow state — tuned to Yu-Gi-Oh MD palette
const GLOW_COLORS := {
	GlowState.NONE:        Color(0, 0, 0, 0),
	GlowState.ACTIVATABLE: Color(0.2, 1.0, 0.3, 1.0),
	GlowState.TARGETABLE:  Color(0.2, 0.6, 1.0, 1.0),
	GlowState.TARGETED:    Color(1.0, 0.85, 0.1, 1.0),
	GlowState.ATTACKING:   Color(1.0, 0.15, 0.1, 1.0),
	GlowState.SELECTED:    Color(1.0, 1.0, 1.0, 1.0),
	GlowState.CHAIN_LINK:  Color(0.7, 0.1, 1.0, 1.0),
}

# ─── Constants ────────────────────────────────────────────────────────────────

const CARD_W         := 100.0
const CARD_H         := 145.0
const FLIP_DURATION  := 0.28   ## seconds for full face flip
const MOVE_DURATION  := 0.22   ## seconds for zone-to-zone tween
const HOVER_LIFT     := -14.0  ## pixels to rise on hover
const ATK_ROT_DEG    := 0.0
const DEF_ROT_DEG    := 90.0   ## DEF position = rotated 90°

# ─── Node References (assigned in _ready) ────────────────────────────────────
# Types are kept as their base classes (Control/Node) where CardViewBuilder
# creates different concrete types than a hand-authored .tscn would.
# Access is always guarded through is_node_ready() in bind().

@onready var pivot:            Control        = $Pivot
@onready var front_face:       Control       = $Pivot/FrontFace   ## Control in builder, TextureRect in .tscn
@onready var back_face:        Control       = $Pivot/BackFace    ## ColorRect in builder
@onready var artwork:          Control       = $Pivot/FrontFace/Artwork  ## ColorRect or TextureRect
@onready var name_label:       Label         = $Pivot/FrontFace/NameLabel
@onready var type_bar:         Label         = $Pivot/FrontFace/TypeBar
@onready var level_row:        HBoxContainer = $Pivot/FrontFace/LevelRow
@onready var atk_label:        Label         = $Pivot/FrontFace/AtkLabel
@onready var def_label:        Label         = $Pivot/FrontFace/DefLabel
@onready var counter_badge:    Label         = $Pivot/FrontFace/CounterBadge
@onready var glow_rect:        ColorRect     = $GlowRect
@onready var selection_border: Control       = $SelectionBorder  ## Panel in .tscn, Control ok

# ─── State ────────────────────────────────────────────────────────────────────

var card: CardInstance = null     ## The domain object this view represents
var glow_state: GlowState = GlowState.NONE
var _is_face_up: bool = false
var _is_hovered: bool = false
var _tween: Tween = null

# ─── Initialization ───────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	size = Vector2(CARD_W, CARD_H)
	pivot_offset = Vector2(CARD_W / 2.0, CARD_H / 2.0)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	selection_border.visible = false
	counter_badge.visible    = false
	_apply_glow_shader()

	# If bind() was called before we entered the tree, finish wiring now.
	if card != null:
		if not card.stat_changed.is_connected(_on_stat_changed):
			card.stat_changed.connect(_on_stat_changed)
		if not card.counter_changed.is_connected(_on_counter_changed):
			card.counter_changed.connect(_on_counter_changed)
		_refresh_display()
	

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
			card.stat_changed.connect(_on_stat_changed)
			card.counter_changed.connect(_on_counter_changed)
			_refresh_display()

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
	elif def.is_spell():
		type_bar.text = "SPELL — %s" % CardDefinition.SpellType.keys()[def.spell_type]
	else:
		type_bar.text = "TRAP — %s" % CardDefinition.TrapType.keys()[def.trap_type]

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
func flip_to(face_up: bool, instant: bool = false) -> void:
	if is_node_ready():
		if _is_face_up == face_up:
			return
		_is_face_up = face_up
		if instant:
			front_face.visible = face_up
			back_face.visible  = not face_up
			return


		if _tween and _tween.is_valid():
			_tween.kill()

		_tween = create_tween()
		_tween.set_ease(Tween.EASE_IN_OUT)
		_tween.set_trans(Tween.TRANS_SINE)

	# Phase 1: rotate to 90° (edge-on)
		_tween.tween_property(pivot, "scale:x", 0.0, FLIP_DURATION * 0.5)

		# Swap face at the midpoint
		_tween.tween_callback(func():
			front_face.visible = face_up
			back_face.visible  = not face_up
		)

		# Phase 2: rotate from 90° back to 0°
		_tween.tween_property(pivot, "scale:x", 1.0, FLIP_DURATION * 0.5)
	else:
		_is_face_up = face_up
		return
# ─── Glow State ───────────────────────────────────────────────────────────────

func set_glow(new_state: GlowState) -> void:
	if glow_state == new_state:
		return
	glow_state = new_state
	_update_glow()

func _update_glow() -> void:
	var color: Color = GLOW_COLORS[glow_state]
	if glow_rect.material and glow_rect.material is ShaderMaterial:
		glow_rect.material.set_shader_parameter(&"glow_color", color)
		glow_rect.material.set_shader_parameter(&"glow_enabled", glow_state != GlowState.NONE)
	glow_rect.visible = glow_state != GlowState.NONE

	# Pulse animation for activatable/targetable states
	if _tween and _tween.is_valid():
		_tween.kill()
	if glow_state in [GlowState.ACTIVATABLE, GlowState.TARGETABLE, GlowState.CHAIN_LINK]:
		_start_pulse_animation()

func _start_pulse_animation() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_method(func(v: float):
		if glow_rect.material and glow_rect.material is ShaderMaterial:
			glow_rect.material.set_shader_parameter(&"glow_intensity", v)
	, 0.5, 1.0, 0.7)
	tw.tween_method(func(v: float):
		if glow_rect.material and glow_rect.material is ShaderMaterial:
			glow_rect.material.set_shader_parameter(&"glow_intensity", v)
	, 1.0, 0.5, 0.7)

func _apply_glow_shader() -> void:
	# Inline shader — no external .gdshader file needed
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4  glow_color : source_color = vec4(0.2, 1.0, 0.3, 1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform bool  glow_enabled = false;
uniform float card_w = 100.0;
uniform float card_h = 145.0;

void fragment() {
	if (!glow_enabled) {
		COLOR = vec4(0.0);
	}

	// Normalized UV: 0,0 = top-left, 1,1 = bottom-right
	vec2 uv = UV;

	// Distance from nearest edge
	float dx = min(uv.x, 1.0 - uv.x) * card_w;
	float dy = min(uv.y, 1.0 - uv.y) * card_h;
	float edge_dist = min(dx, dy);

	// Glow band: strong within 8px of edge, fading outward
	float band = 8.0;
	float alpha = clamp(1.0 - edge_dist / band, 0.0, 1.0);
	alpha = pow(alpha, 1.5) * glow_intensity;

	COLOR = vec4(glow_color.rgb, alpha * glow_color.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"card_w", CARD_W)
	mat.set_shader_parameter(&"card_h", CARD_H)
	glow_rect.material = mat
	glow_rect.size     = Vector2(CARD_W, CARD_H)
	glow_rect.position = Vector2.ZERO

# ─── Move Animation ───────────────────────────────────────────────────────────
func kill_all_tweens() ->void:
	if _tween and _tween.is_valid():
		_tween.kill()
		_tween=null
	
## Animate this card moving to a new global position.
## Called by BoardView after it repositions the card's parent container.
func animate_move_to(target_global: Vector2) -> Signal:
	var start := global_position
	var tw    := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUINT)
	tw.tween_method(func(t: float):
		global_position = start.lerp(target_global, t)
	, 0.0, 1.0, MOVE_DURATION)
	return tw.finished
## Destruction burst: scale down and fade, then call done_callback.
func animate_destroy() -> Signal:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_property(self, "scale", Vector2(1.4, 1.4), 0.2)
	tw.chain().tween_property(self, "scale", Vector2(0.0, 0.0), 0.15)
	return tw.finished
## Summon pop-in: start slightly scaled down, bounce up.
func animate_summon() -> Signal:
	kill_all_tweens()
	_is_hovered = false
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween = tw
	return tw.finished
	
# ─── Attack Animation ─────────────────────────────────────────────────────────

## Lunges toward `target_global`, holds briefly (impact frame), then springs
## back to its original position. Used for the attacking card during the
## damage step. Returns "finished" so the caller can sequence destruction
## or LP damage feedback right after impact.
func animate_attack_lunge(target_global: Vector2) -> Signal:
	var home      := global_position
	var direction := (target_global - home)
	## Lunge 60% of the way to the target, not all the way — the card
	## should look like it's striking, not swapping places.
	var lunge_pos := home + direction * 0.6

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "global_position", lunge_pos, 0.18)
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.06)
	## Brief hold at impact
	tw.tween_interval(0.08)
	tw.tween_property(self, "global_position", home, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.22)
	return tw.finished

## Quick white flash + shake — used on the card that TAKES damage in battle
## (whether or not it is destroyed afterward). Call this on the defender
## simultaneously with the attacker's lunge for simultaneous impact.
func animate_take_hit() -> Signal:
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

	return tw.finished

# ─── Effect Activation / Resolution Animation ─────────────────────────────────

## Played when this card's effect is pushed onto the chain (activation).
## A bright outward pulse distinct from the standing CHAIN_LINK glow —
## marks the *moment* of activation rather than the held state while it
## sits on the chain.
func animate_effect_activate() -> Signal:
	## Reuse the glow rect for a one-shot bright pulse on top of whatever
	## standing glow state is already set.
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

	return tw.finished

## Played when this card's chain link resolves. Distinct from activation —
## a soft outward ring rather than a scale pulse, signalling "effect has
## taken place" rather than "effect has been declared".
func animate_effect_resolve() -> Signal:
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

	return tw.finished
# ─── Selection ────────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	selection_border.visible = selected
	if selected:
		set_glow(GlowState.SELECTED)
	else:
		set_glow(GlowState.NONE)

# ─── Hover ────────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	if _is_hovered:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_is_hovered = true
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y + HOVER_LIFT, 0.12)
	# Scale slightly
	tw.parallel().tween_property(self, "scale", Vector2(1.06, 1.06), 0.12)
	_tween = tw
func _on_mouse_exited() -> void:
	if not _is_hovered:
		return
	_is_hovered = false
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y - HOVER_LIFT, 0.12)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.12)
	_tween = tw
# ─── Input ────────────────────────────────────────────────────────────────────

func _on_gui_input(event: InputEvent) -> void:

	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				card_clicked.emit(self)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				card_inspected.emit(self)

# ─── Domain Signal Handlers ───────────────────────────────────────────────────

func _on_stat_changed(_card: CardInstance, stat: StringName, _old: int, new_val: int) -> void:
	match stat:
		&"atk": atk_label.text = "ATK  %d" % new_val
		&"def": def_label.text = "DEF  %d" % new_val

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

func _to_string() -> String:
	var name := card.definition.card_name if card else "empty"
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
