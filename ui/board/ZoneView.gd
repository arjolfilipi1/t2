## ZoneView.gd
## Visual representation of one logical zone (or one slot within a zone).
## Manages:
##   - Empty-slot indicator (dashed border)
##   - Zone label (MONSTER ZONE, GRAVEYARD, etc.)
##   - Card placement / removal animations
##   - Highlight when it is a legal drop target
##   - Card count badge (for GY, banished, deck, hand)
##
## BoardView creates one ZoneView per slot for slotted zones,
## and one ZoneView for the whole pile for unslotted zones.
class_name ZoneView
extends Control

# ─── Signals ──────────────────────────────────────────────────────────────────

## Player clicked an empty zone slot (summon / set destination).
signal empty_slot_clicked(zone_view: ZoneView)

## Player dropped a card onto this zone.
signal card_dropped(zone_view: ZoneView, card_view: CardView)

# ─── Zone Identity ────────────────────────────────────────────────────────────

## The domain zone this view represents.
var zone: Zone = null

## For slotted zones: which slot index (0-4). -1 for unslotted.
var slot_index: int = -1

## Friendly display label.
var zone_label: String = ""

# ─── Layout Constants ─────────────────────────────────────────────────────────

const SLOT_W := 108.0
const SLOT_H := 153.0

# ─── Colours ──────────────────────────────────────────────────────────────────

const COLOR_EMPTY_BORDER  := Color(0.5, 0.5, 0.6, 0.45)
const COLOR_DROP_TARGET   := Color(0.3, 0.9, 0.4, 0.70)
const COLOR_MONSTER_BG    := Color(0.12, 0.14, 0.22, 0.55)
const COLOR_SPELL_BG      := Color(0.10, 0.22, 0.14, 0.55)
const COLOR_GRAVE_BG      := Color(0.22, 0.10, 0.10, 0.55)
const COLOR_DECK_BG       := Color(0.10, 0.10, 0.22, 0.55)
const COLOR_EXTRA_BG      := Color(0.22, 0.20, 0.10, 0.55)
const COLOR_FIELD_BG      := Color(0.08, 0.18, 0.08, 0.55)
const COLOR_BANISH_BG     := Color(0.22, 0.18, 0.10, 0.55)

# ─── Child Nodes ──────────────────────────────────────────────────────────────

var _bg:          ColorRect
var _border:      Control       ## Custom-drawn dashed border
var _label_node:  Label
var _count_badge: Label
var _card_anchor: Control       ## CardView is parented here
var _is_drop_highlight: bool = false

# ─── State ────────────────────────────────────────────────────────────────────

var _card_view: CardView = null  ## The CardView currently displayed here (or null)

# ─── Init ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	_build_children()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func setup(target_zone: Zone, slot: int, label: String) -> void:
	zone       = target_zone
	slot_index = slot
	zone_label = label
	_label_node.text = label
	_bg.color        = _bg_color_for_zone()
	queue_redraw()

# ─── Card Management ──────────────────────────────────────────────────────────

## Place a CardView into this zone slot.
func place_card(view: CardView, animate: bool = true) -> void:
	if _card_view != null:
		remove_card(false)

	_card_view = view

	# If the card view has no parent yet, add it directly.
	# If it has a parent and is in the tree, reparent. Never reparent an orphan.
	if view.get_parent() == null:
		_card_anchor.add_child(view)
	elif view.get_parent() != _card_anchor:
		if view.is_inside_tree():
			view.reparent(_card_anchor)
		else:
			view.get_parent().remove_child(view)
			_card_anchor.add_child(view)

	view.position = Vector2.ZERO

	_label_node.visible = false
	_count_badge.visible = false

	if animate:
		view.animate_summon()

	queue_redraw()

## Remove the CardView from this slot (does not free it).
func remove_card(animate: bool = true) -> void:
	if _card_view == null:
		return

	var view := _card_view
	_card_view = null

	_label_node.visible = true

	if animate:
		view.animate_destroy(func():
			if view.get_parent() == _card_anchor:
				_card_anchor.remove_child(view)
		)
	else:
		if view.get_parent() == _card_anchor:
			_card_anchor.remove_child(view)

	queue_redraw()

## Update the count badge (GY, deck, hand pile, etc.)
func set_count(n: int) -> void:
	if n > 0:
		_count_badge.text    = str(n)
		_count_badge.visible = true
	else:
		_count_badge.visible = false

func get_card_view() -> CardView:
	return _card_view

func is_empty() -> bool:
	return _card_view == null

# ─── Drop Target Highlighting ─────────────────────────────────────────────────

func set_drop_highlight(enabled: bool) -> void:
	if _is_drop_highlight == enabled:
		return
	_is_drop_highlight = enabled
	queue_redraw()

# ─── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var W := SLOT_W
	var H := SLOT_H
	var rect := Rect2(0, 0, W, H)

	if _is_drop_highlight:
		draw_rect(rect, COLOR_DROP_TARGET, true)
		draw_rect(rect, Color.WHITE, false, 2.0)
		return

	if _card_view == null:
		# Dashed border for empty slot
		_draw_dashed_border(W, H)

func _draw_dashed_border(W: float, H: float) -> void:
	var col   := COLOR_EMPTY_BORDER
	var dash  := 6.0
	var gap   := 4.0
	var thick := 1.5

	# Top edge
	var x := 0.0
	while x < W:
		var end := min(x + dash, W)
		draw_line(Vector2(x, 0), Vector2(end, 0), col, thick)
		x += dash + gap

	# Bottom edge
	x = 0.0
	while x < W:
		var end := min(x + dash, W)
		draw_line(Vector2(x, H), Vector2(end, H), col, thick)
		x += dash + gap

	# Left edge
	var y := 0.0
	while y < H:
		var end := min(y + dash, H)
		draw_line(Vector2(0, y), Vector2(0, end), col, thick)
		y += dash + gap

	# Right edge
	y = 0.0
	while y < H:
		var end := min(y + dash, H)
		draw_line(Vector2(W, y), Vector2(W, end), col, thick)
		y += dash + gap

	# Zone icon in centre
	draw_string(
		ThemeDB.fallback_font,
		Vector2(4, H / 2.0 + 4),
		zone_label,
		HORIZONTAL_ALIGNMENT_CENTER,
		SLOT_W - 8,
		9,
		Color(0.6, 0.6, 0.7, 0.6)
	)

# ─── Input ────────────────────────────────────────────────────────────────────

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _card_view == null:
			print(zone_label,self.get_parent().name)
			empty_slot_clicked.emit(self)

func _on_mouse_entered() -> void:
	if _card_view == null and not _is_drop_highlight:
		
		modulate = Color(1.7, 1.7, 1.7)

func _on_mouse_exited() -> void:
	modulate = Color.WHITE

# ─── Child Construction ───────────────────────────────────────────────────────

func _build_children() -> void:
	_bg = ColorRect.new()
	_bg.name         = "BG"
	_bg.size         = Vector2(SLOT_W, SLOT_H)
	_bg.color        = COLOR_MONSTER_BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_card_anchor = Control.new()
	_card_anchor.name           = "CardAnchor"
	_card_anchor.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H)
	_card_anchor.position       = Vector2(
		(SLOT_W - CardView.CARD_W) / 2.0,
		(SLOT_H - CardView.CARD_H) / 2.0
	)
	_card_anchor.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_card_anchor)

	_label_node = Label.new()
	_label_node.name         = "ZoneLabel"
	_label_node.position     = Vector2(0, SLOT_H / 2.0 - 6)
	_label_node.size         = Vector2(SLOT_W, 12)
	_label_node.add_theme_font_size_override("font_size", 7)
	_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_node.modulate     = Color(0.7, 0.7, 0.8, 0.7)
	_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label_node)

	_count_badge = Label.new()
	_count_badge.name         = "CountBadge"
	_count_badge.position     = Vector2(SLOT_W - 22, SLOT_H - 16)
	_count_badge.size         = Vector2(20, 14)
	_count_badge.add_theme_font_size_override("font_size", 8)
	_count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_badge.modulate     = Color.WHITE
	_count_badge.visible      = false
	_count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_badge)

func _bg_color_for_zone() -> Color:
	if zone == null:
		return COLOR_MONSTER_BG
	match zone.zone_type:
		Zone.ZoneType.MAIN_MONSTER, Zone.ZoneType.EXTRA_MONSTER:
			return COLOR_MONSTER_BG
		Zone.ZoneType.MAIN_SPELL:
			return COLOR_SPELL_BG
		Zone.ZoneType.GRAVEYARD:
			return COLOR_GRAVE_BG
		Zone.ZoneType.DECK, Zone.ZoneType.EXTRA_DECK:
			return COLOR_DECK_BG
		Zone.ZoneType.FIELD_SPELL:
			return COLOR_FIELD_BG
		Zone.ZoneType.BANISHED:
			return COLOR_BANISH_BG
	return COLOR_MONSTER_BG
