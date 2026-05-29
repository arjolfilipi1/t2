## CardViewBuilder.gd
## Constructs a CardView node tree entirely in code.
## Use this in tests and at runtime when you don't have a .tscn file.
## In production you'd replace this with a proper .tscn in res://ui/card/
##
## Usage:
##   var view := CardViewBuilder.build()
##   view.bind(my_card_instance)
##   add_child(view)
class_name CardViewBuilder
extends RefCounted

static func build() -> CardView:
	# ── Root ──────────────────────────────────────────────────────────────────
	var root := CardView.new()
	root.custom_minimum_size = Vector2(CardView.CARD_W,CardView.CARD_H)
	root.size = Vector2(CardView.CARD_W,CardView.CARD_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.name = "CardView"
	root.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H)
# ── Add Area2D for World Mouse Detection ──────────────────────────────────
	var detection_area := Area2D.new()
	detection_area.name = "DetectionArea"
	
	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	
	# Size the collision box to match your card size (extents are half-size)
	rectangle.size = Vector2(CardView.CARD_W, CardView.CARD_H)
	collision_shape.shape = rectangle
	
	# Center the collision shape relative to the Control node's top-left origin
	collision_shape.position = Vector2(CardView.CARD_W / 2, CardView.CARD_H / 2)
	
	detection_area.add_child(collision_shape)
	root.add_child(detection_area)

	# ── Connect Area2D Signals Instead ────────────────────────────────────────
	detection_area.mouse_entered.connect(root._on_mouse_entered)
	detection_area.mouse_exited.connect(root._on_mouse_exited) # Optional
	# ── Pivot ─────────────────────────────────────────────────────────────────
	var pivot := Control.new()
	pivot.name = "Pivot"
	pivot.mouse_filter = Control.MOUSE_FILTER_PASS # Allows input to pass through to roo
	root.add_child(pivot)

	# ── Back face ─────────────────────────────────────────────────────────────
	var back := ColorRect.new()      ## Stand-in for TextureRect in tests
	back.name = "BackFace"
	back.size = Vector2(CardView.CARD_W, CardView.CARD_H)
	back.color = Color(0.08, 0.08, 0.20)   ## Dark navy card back
	# Inner pattern lines
	var pattern := _make_back_pattern()
	back.add_child(pattern)
	pivot.add_child(back)

	# ── Front face container ───────────────────────────────────────────────────
	var front := _build_front_face()
	pivot.add_child(front)

	# ── Glow rect (behind border, above art) ──────────────────────────────────
	var glow := ColorRect.new()
	glow.name     = "GlowRect"
	glow.size     = Vector2(CardView.CARD_W, CardView.CARD_H)
	glow.position = Vector2.ZERO
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)

	# ── Selection border ──────────────────────────────────────────────────────
	var sel := _build_selection_border()
	root.add_child(sel)

	
	return root

# ─── Front Face ───────────────────────────────────────────────────────────────

static func _build_front_face() -> Control:
	var W := CardView.CARD_W
	var H := CardView.CARD_H

	var front := Control.new()
	front.name = "FrontFace"
	front.custom_minimum_size = Vector2(W, H)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	# Card frame background
	var bg := ColorRect.new()
	bg.name       = "Background"
	bg.size       = Vector2(W, H)
	bg.color      = Color(0.85, 0.72, 0.45)  ## Parchment — will be tinted by card type
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(bg)

	# Artwork area (top 55% of card)
	var art_h := H * 0.50
	var art   := ColorRect.new()
	art.name     = "Artwork"
	art.position = Vector2(4, 16)
	art.size     = Vector2(W - 8, art_h)
	art.color    = Color(0.3, 0.3, 0.3)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(art)

	# Name label
	var name_lbl := Label.new()
	name_lbl.name             = "NameLabel"
	name_lbl.position         = Vector2(3, 2)
	name_lbl.size             = Vector2(W - 6, 13)
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.clip_text        = true
	name_lbl.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	front.add_child(name_lbl)

	# Type bar
	var type_lbl := Label.new()
	type_lbl.name         = "TypeBar"
	type_lbl.position     = Vector2(3, 16 + art_h + 1)
	type_lbl.size         = Vector2(W - 6, 10)
	type_lbl.add_theme_font_size_override("font_size", 6)
	type_lbl.clip_text    = true
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(type_lbl)

	# Level star row
	var level_row := HBoxContainer.new()
	level_row.name         = "LevelRow"
	level_row.position     = Vector2(3, 16 + art_h + 12)
	level_row.custom_minimum_size = Vector2(W - 6, 9)
	level_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(level_row)

	# ATK label
	var atk_lbl := Label.new()
	atk_lbl.name         = "AtkLabel"
	atk_lbl.position     = Vector2(3, H - 26)
	atk_lbl.size         = Vector2(W - 6, 11)
	atk_lbl.add_theme_font_size_override("font_size", 7)
	atk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(atk_lbl)

	# DEF label
	var def_lbl := Label.new()
	def_lbl.name         = "DefLabel"
	def_lbl.position     = Vector2(3, H - 14)
	def_lbl.size         = Vector2(W - 6, 11)
	def_lbl.add_theme_font_size_override("font_size", 7)
	def_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(def_lbl)

	# Counter badge
	var badge := Label.new()
	badge.name         = "CounterBadge"
	badge.position     = Vector2(3, 16 + art_h + 24)
	badge.size         = Vector2(W - 6, 10)
	badge.add_theme_font_size_override("font_size", 6)
	badge.modulate     = Color(0.2, 0.9, 1.0)
	badge.visible      = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(badge)

	return front

# ─── Back Face Pattern ────────────────────────────────────────────────────────

static func _make_back_pattern() -> Control:
	## Simple diamond grid drawn as a Control with _draw override.
	## Replaces a texture for the card back in tests.
	var pat := _BackPattern.new()
	pat.name = "BackPattern"
	pat.size = Vector2(CardView.CARD_W, CardView.CARD_H)
	pat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pat

# ─── Selection Border ─────────────────────────────────────────────────────────

static func _build_selection_border() -> Panel:
	var border := Panel.new()
	border.name    = "SelectionBorder"
	border.size    = Vector2(CardView.CARD_W + 4, CardView.CARD_H + 4)
	border.position = Vector2(-2, -2)
	border.visible  = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0, 0, 0, 0)
	style.border_color    = Color.WHITE
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	border.add_theme_stylebox_override("panel", style)

	return border


# ──────────────────────────────────────────────────────────────────────────────
# Inner class: back pattern renderer
# ──────────────────────────────────────────────────────────────────────────────

class _BackPattern extends Control:
	func _draw() -> void:
		var W := size.x
		var H := size.y

		# Outer border
		draw_rect(Rect2(0, 0, W, H), Color(0.55, 0.42, 0.10), false, 2.0)

		# Inner border
		draw_rect(Rect2(3, 3, W - 6, H - 6), Color(0.45, 0.32, 0.08), false, 1.0)

		# Diagonal grid
		var spacing := 12.0
		var grid_color := Color(0.25, 0.20, 0.45, 0.6)
		var x := 0.0
		while x < W + H:
			draw_line(Vector2(x - H, 0), Vector2(x, H), grid_color, 0.5)
			draw_line(Vector2(x - H, H), Vector2(x, 0), grid_color, 0.5)
			x += spacing

		# Centre diamond logo placeholder
		var cx := W / 2.0
		var cy := H / 2.0
		var r  := 18.0
		var pts := PackedVector2Array([
			Vector2(cx,     cy - r),
			Vector2(cx + r, cy    ),
			Vector2(cx,     cy + r),
			Vector2(cx - r, cy    ),
		])
		draw_colored_polygon(pts, Color(0.60, 0.45, 0.10, 0.8))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(0.85, 0.70, 0.20), 1.5)
