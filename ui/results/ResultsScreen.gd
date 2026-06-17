extends Control

signal rematch_requested()
signal menu_requested()

var _winner: Player = null
var _loser: Player = null
var _stats: Dictionary = {}

@onready var overlay: ColorRect = $Overlay
@onready var panel: Panel = $Panel
@onready var victory_label: Label = $Panel/VBoxContainer/VictoryLabel
@onready var defeat_label: Label = $Panel/VBoxContainer/DefeatLabel
@onready var winner_name: Label = $Panel/VBoxContainer/WinnerName
@onready var rematch_button: Button = $Panel/VBoxContainer/ButtonContainer/RematchButton
@onready var menu_button: Button = $Panel/VBoxContainer/ButtonContainer/MenuButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var particles: GPUParticles2D = $Particles

func _ready() -> void:
    hide()
    panel.modulate.a = 0
    panel.scale = Vector2(0.8, 0.8)
    
    rematch_button.pressed.connect(_on_rematch)
    menu_button.pressed.connect(_on_menu)

func show_results(winner: Player, loser: Player, stats: Dictionary = {}) -> void:
    _winner = winner
    _loser = loser
    _stats = stats
    
    show()
    
    # Determine if local player won
    var is_victory = (winner.player_id == 1)  # Assuming player 1 is local
    
    # Show correct labels
    victory_label.visible = is_victory
    defeat_label.visible = not is_victory
    
    # Set winner name text
    if is_victory:
        winner_name.text = "You Win!"
        winner_name.modulate = Color(1.0, 0.85, 0.2)
    else:
        winner_name.text = "%s Wins!" % winner.display_name
        winner_name.modulate = Color(0.7, 0.7, 0.9)
    
    # Populate stats
    _populate_stats()
    
    # Play entrance animation
    _animate_entrance(is_victory)
    
    # Play victory/defeat effects
    if is_victory:
        _play_victory_effects()
    else:
        _play_defeat_effects()

func _populate_stats() -> void:
    # Clear existing stats
    for child in $Panel/VBoxContainer/StatsContainer/StatsLeft.get_children():
        child.queue_free()
    for child in $Panel/VBoxContainer/StatsContainer/StatsRight.get_children():
        child.queue_free()
    
    # Add stats from the game
    var stats_left = [
        {"name": "Turn Count", "value": _stats.get("turn_count", 0)},
        {"name": "Cards Drawn", "value": _stats.get("cards_drawn", 0)},
        {"name": "Monsters Summoned", "value": _stats.get("monsters_summoned", 0)},
    ]
    
    var stats_right = [
        {"name": "Spells Activated", "value": _stats.get("spells_activated", 0)},
        {"name": "Traps Activated", "value": _stats.get("traps_activated", 0)},
        {"name": "Damage Dealt", "value": _stats.get("damage_dealt", 0)},
    ]
    
    for stat in stats_left:
        var container = HBoxContainer.new()
        var name_label = Label.new()
        name_label.text = stat["name"] + ":"
        name_label.size_flags_horizontal = Control.SIZE_EXPAND
        var value_label = Label.new()
        value_label.text = str(stat["value"])
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        value_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        container.add_child(name_label)
        container.add_child(value_label)
        $Panel/VBoxContainer/StatsContainer/StatsLeft.add_child(container)
    
    for stat in stats_right:
        var container = HBoxContainer.new()
        var name_label = Label.new()
        name_label.text = stat["name"] + ":"
        name_label.size_flags_horizontal = Control.SIZE_EXPAND
        var value_label = Label.new()
        value_label.text = str(stat["value"])
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        value_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        container.add_child(name_label)
        container.add_child(value_label)
        $Panel/VBoxContainer/StatsContainer/StatsRight.add_child(container)

func _animate_entrance(is_victory: bool) -> void:
    # Fade in overlay
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(overlay, "color:a", 0.85, 0.3)
    
    # Panel pop-in animation
    tween.tween_property(panel, "modulate:a", 1.0, 0.2)
    tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
    
    await tween.finished
    
    # Flash effect for victory
    if is_victory:
        var flash = create_tween()
        flash.tween_property(victory_label, "modulate", Color(1, 1, 1, 1), 0.1)
        flash.tween_property(victory_label, "modulate", Color(1, 0.85, 0.2, 1), 0.2)

func _play_victory_effects() -> void:
    # Create a particle system for confetti
    var confetti = _create_confetti()
    add_child(confetti)
    
    # Scale and fade the victory label
    var tween = create_tween()
    tween.set_loops(3)
    tween.tween_property(victory_label, "scale", Vector2(1.1, 1.1), 0.2)
    tween.tween_property(victory_label, "scale", Vector2(1.0, 1.0), 0.2)
    
    # Play sound (if you have sound effects)
    # $VictorySound.play()

func _play_defeat_effects() -> void:
    # Shake the panel slightly
    var original_pos = panel.position
    var tween = create_tween()
    for i in 3:
        tween.tween_property(panel, "position", original_pos + Vector2(5, 0), 0.05)
        tween.tween_property(panel, "position", original_pos - Vector2(5, 0), 0.05)
    tween.tween_property(panel, "position", original_pos, 0.05)
    
    # Dim the defeat label
    tween = create_tween()
    tween.tween_property(defeat_label, "modulate:a", 0.5, 1.0)

func _create_confetti() -> GPUParticles2D:
    var particles = GPUParticles2D.new()
    particles.amount = 200
    particles.lifetime = 2.0
    particles.speed_scale = 0.8
    particles.explosiveness = 0.9
    particles.one_shot = true
    particles.emitting = true
    
    # Create colorful particle material
    var material = ParticleProcessMaterial.new()
    material.direction = Vector3(0, -1, 0)
    material.spread = 180.0
    material.gravity = Vector3(0, 200, 0)
    material.initial_velocity_min = 100.0
    material.initial_velocity_max = 300.0
    material.scale_min = 0.5
    material.scale_max = 1.0
    
    # Random colors
    material.color_ramp = _create_color_ramp()
    
    particles.process_material = material
    particles.position = get_viewport().get_camera_2d().global_position if get_viewport().get_camera_2d() else Vector2(640, 360)
    
    return particles

func _create_color_ramp() -> GradientTexture1D:
    var gradient = Gradient.new()
    gradient.colors = [
        Color(1, 0.2, 0.2),  # Red
        Color(1, 0.8, 0.2),  # Gold
        Color(0.2, 0.8, 0.2),  # Green
        Color(0.2, 0.4, 1),   # Blue
        Color(1, 0.2, 0.8),   # Pink
    ]
    gradient.offsets = [0.0, 0.25, 0.5, 0.75, 1.0]
    
    var texture = GradientTexture1D.new()
    texture.gradient = gradient
    return texture

func _on_rematch() -> void:
    var tween = create_tween()
    tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.1)
    tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1)
    await tween.finished
    
    _hide_results()
    rematch_requested.emit()

func _on_menu() -> void:
    var tween = create_tween()
    tween.tween_property(panel, "scale", Vector2(0.8, 0.8), 0.15)
    tween.parallel().tween_property(panel, "modulate:a", 0, 0.15)
    await tween.finished
    
    _hide_results()
    menu_requested.emit()

func _hide_results() -> void:
    var tween = create_tween()
    tween.tween_property(overlay, "color:a", 0, 0.2)
    await tween.finished
    hide()