extends Control
## Game HUD - Displays score, HP, and victory message

@export var player_hp_node : Node  # Reference to PlayerHP script
@export var coin_spawner : Node  # Reference to CoinSpawner
@export var bgm_sfx : AudioStreamPlayer2D # Reference to CoinSpawner
@export var max_hp := 5  # Maximum player HP
@export var win_coin_count := 9  # Coins needed to win
@export var camera : Node

# UI References (will be created in code)
@export var score_label : Label
@export var hp_label : Label
var victory_panel : Panel
var victory_label : Label
var game_over_panel : Panel
var game_over_label : Label

var current_score := 0
var current_hp := 5

signal victory_achieved()
signal game_over()

func _ready() -> void:
	_create_ui()
	
	# Connect to coin spawner signals
	if coin_spawner:
		coin_spawner.coin_collected.connect(_on_coin_collected)
		print("HUD connected to coin spawner")
	
	# Initial update
	_update_score_display()
	_update_hp_display()

func _create_ui() -> void:
	"""Creates all UI elements programmatically"""
	
	
	# === VICTORY PANEL ===
	victory_panel = Panel.new()
	victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	victory_panel.size = Vector2(400, 200)
	victory_panel.position = Vector2(-200, -100)
	victory_panel.visible = false
	
	# Style victory panel
	var victory_style = StyleBoxFlat.new()
	victory_style.bg_color = Color(0.0, 0.5, 0.0, 0.9)  # Dark green
	victory_style.border_color = Color(0.0, 1.0, 0.0)  # Bright green
	victory_style.set_border_width_all(4)
	victory_style.corner_radius_top_left = 10
	victory_style.corner_radius_top_right = 10
	victory_style.corner_radius_bottom_left = 10
	victory_style.corner_radius_bottom_right = 10
	victory_panel.add_theme_stylebox_override("panel", victory_style)
	add_child(victory_panel)
	
	# Victory text
	victory_label = Label.new()
	victory_label.text = "VICTORY!\n\nYou collected 9 coins!\n\nPress ESC to quit"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_label.add_theme_font_size_override("font_size", 36)
	victory_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))  # Yellow
	victory_label.add_theme_color_override("font_outline_color", Color.BLACK)
	victory_label.add_theme_constant_override("outline_size", 4)
	victory_panel.add_child(victory_label)
	
	# === GAME OVER PANEL ===
	game_over_panel = Panel.new()
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.size = Vector2(400, 200)
	game_over_panel.position = Vector2(-200, -100)
	game_over_panel.visible = false
	
	# Style game over panel
	var game_over_style = StyleBoxFlat.new()
	game_over_style.bg_color = Color(0.5, 0.0, 0.0, 0.9)  # Dark red
	game_over_style.border_color = Color(1.0, 0.0, 0.0)  # Bright red
	game_over_style.set_border_width_all(4)
	game_over_style.corner_radius_top_left = 10
	game_over_style.corner_radius_top_right = 10
	game_over_style.corner_radius_bottom_left = 10
	game_over_style.corner_radius_bottom_right = 10
	game_over_panel.add_theme_stylebox_override("panel", game_over_style)
	add_child(game_over_panel)
	
	# Game over text
	game_over_label = Label.new()
	game_over_label.text = "GAME OVER\n\nYou ran out of HP!\n\nPress ESC to quit"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_label.add_theme_font_size_override("font_size", 36)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	game_over_label.add_theme_color_override("font_outline_color", Color.BLACK)
	game_over_label.add_theme_constant_override("outline_size", 4)
	game_over_panel.add_child(game_over_label)

func _process(_delta: float) -> void:
	global_position = camera.global_position + Vector2(-200,-120)
	scale = Vector2(0.5,0.5)
	# Update HP from player HP node
	if player_hp_node and player_hp_node.has_method("get_current_hp"):
		var new_hp = player_hp_node.get_current_hp()
		if new_hp != current_hp:
			current_hp = new_hp
			_update_hp_display()
			
			# Check for game over
			if current_hp <= 0:
				_show_game_over()

func _on_coin_collected(position: Vector2i, total_coins: int) -> void:
	"""Called when a coin is collected"""
	current_score = total_coins
	_update_score_display()
	
	# Check for victory
	if current_score >= win_coin_count:
		_show_victory()

func _update_score_display() -> void:
	"""Updates the score label"""
	score_label.text = "%d / %d" % [current_score, win_coin_count]
	
	# Animate score change
	var tween = create_tween()
	tween.tween_property(score_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(score_label, "scale", Vector2(1.0, 1.0), 0.1)

func _update_hp_display() -> void:
	"""Updates the HP label with hearts"""
	var hearts = ""
	for i in range(max_hp):
		if i < current_hp:
			hearts += "X "  # Full heart
		else:
			hearts += " "  # Empty heart
	
	hp_label.text = "HP: " + hearts
	
	# Flash red when taking damage
	if current_hp < max_hp:
		var tween = create_tween()
		tween.tween_property(hp_label, "modulate", Color(1.5, 0.5, 0.5), 0.1)
		tween.tween_property(hp_label, "modulate", Color.WHITE, 0.1)

func _show_victory() -> void:
	# Use change_scene_to_file for Godot 4.0+
	var error = get_tree().change_scene_to_file("res://scenes/boss1.tscn")
	if error != OK:
		print("Failed to change scene: ", error)
	
	

func _show_game_over() -> void:
	var error = get_tree().change_scene_to_file("res://scenes/delay.tscn")
	if error != OK:
		print("Failed to change scene: ", error)

func update_hp(new_hp: int) -> void:
	"""Manually update HP display"""
	current_hp = clampi(new_hp, 0, max_hp)
	_update_hp_display()
	
	if current_hp <= 0:
		_show_game_over()

func add_score(amount: int) -> void:
	"""Manually add to score"""
	current_score += amount
	_update_score_display()
	
	bgm_sfx.pitch_scale = bgm_sfx.pitch_scale * 0.5
	if current_score >= win_coin_count:
		_show_victory()

func reset_game() -> void:
	"""Resets the game state"""
	current_score = 0
	current_hp = max_hp
	victory_panel.visible = false
	game_over_panel.visible = false
	_update_score_display()
	_update_hp_display()
