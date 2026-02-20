extends Node2D

## Chase Target - The Thing You're Pursuing
## Mysterious entity that stays ahead of player, glitches away when caught

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var path_generator : Node  # Reference to path generator
@export var offset = Vector2(0, -8)

# Target behavior
@export_group("Target Settings")
@export var stay_ahead_distance := 20.0  # How far ahead to stay
@export var escape_trigger_distance := 10.0  # When to run away
@export var movement_type := "teleport"  # "teleport" or "run"
@export var taunt_player := true  # Occasionally gets closer then escapes
@export var taunt_chance := 0.15
@export var min_taunt_distance := 8.0

# Visual settings
@export_group("Visual Settings")
@export var target_color := Color(1, 1, 1, 0.8)  # Pale, ghostly
@export var glitch_appearance := true
@export var flicker_effect := true
@export var leave_trail := true  # Leaves fading particles behind

# Audio
@export var whisper_sound : AudioStreamPlayer2D
@export var escape_sound : AudioStreamPlayer2D

# State
var current_tile : Vector2i
var is_escaping := false
var taunt_timer := 0.0
var flicker_timer := 0.0
var trail_particles : CPUParticles2D

signal target_escaped()
signal target_taunting()
signal target_almost_caught()

func _ready() -> void:
	current_tile = tileMap.local_to_map(global_position)
	_setup_visuals()
	print("Chase target initialized - RUN AFTER IT")

func _setup_visuals() -> void:
	"""Sets up mysterious visual effects"""
	modulate = target_color
	scale = Vector2(0.8, 0.8)  # Smaller, more ethereal
	
	# Trail effect
	if leave_trail:
		trail_particles = CPUParticles2D.new()
		add_child(trail_particles)
		trail_particles.amount = 20
		trail_particles.lifetime = 1.5
		trail_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		trail_particles.emission_sphere_radius = 8
		trail_particles.color = Color(1, 1, 1, 0.5)
		trail_particles.gravity = Vector2.ZERO
		trail_particles.initial_velocity_min = 5
		trail_particles.initial_velocity_max = 15
		trail_particles.emitting = true

func _process(delta: float) -> void:
	var player_tile = tileMap.local_to_map(player.global_position)
	var distance = _manhattan_distance(current_tile, player_tile)
	
	taunt_timer += delta
	flicker_timer += delta
	
	# Flicker effect
	if flicker_effect and flicker_timer > 0.15:
		flicker_timer = 0.0
		visible = not visible
		# Reappear after brief flicker
		if not visible:
			await get_tree().create_timer(0.05).timeout
			visible = true
	
	# Check if player is getting close
	if distance < escape_trigger_distance and not is_escaping:
		_escape()
		emit_signal("target_almost_caught")
	
	# Occasionally taunt player
	if taunt_player and taunt_timer > 5.0 and distance > min_taunt_distance:
		if randf() < taunt_chance:
			_taunt_player()
			taunt_timer = 0.0
	
	# Whisper audio gets louder when player is closer
	if whisper_sound:
		var volume = -40 + (stay_ahead_distance - distance) * 2
		whisper_sound.volume_db = clamp(volume, -40, -10)
		if not whisper_sound.playing:
			whisper_sound.play()

func _escape() -> void:
	"""Target escapes when player gets too close"""
	if is_escaping:
		return
	
	is_escaping = true
	print("Target escaping!")
	
	if movement_type == "teleport":
		_teleport_away()
	else:
		await _run_away()
	
	emit_signal("target_escaped")
	is_escaping = false

func _teleport_away() -> void:
	"""Glitches away to a new position ahead"""
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Find new position ahead
	var new_tile = player_tile + Vector2i(
		randi_range(15, 25),  # Far ahead
		randi_range(-5, 5)    # Slightly offset
	)
	
	# Check if tile is valid, if not try nearby tiles
	for attempt in range(10):
		if tileMap.get_cell_atlas_coords(new_tile) != Vector2i(-1, -1):
			break
		new_tile += Vector2i(randi_range(-2, 2), randi_range(-2, 2))
	
	# Glitch effect before teleport
	await _glitch_vanish()
	
	# Teleport
	current_tile = new_tile
	global_position = tileMap.map_to_local(new_tile) + offset
	
	# Update path generator
	if path_generator:
		path_generator.target_tile = new_tile
		path_generator.shake_area(new_tile, 6.0, 1.5)
	
	# Glitch appear
	await _glitch_appear()
	
	if escape_sound:
		escape_sound.play()

func _run_away() -> void:
	"""Runs away from player (alternative to teleport)"""
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Calculate direction away from player
	var away_direction = current_tile - player_tile
	away_direction = away_direction.sign()
	
	# Move several tiles away
	for i in range(8):
		var target_tile = current_tile + away_direction
		
		# Check if walkable
		if tileMap.get_cell_atlas_coords(target_tile) != Vector2i(-1, -1):
			var target_pos = tileMap.map_to_local(target_tile) + offset
			
			# Quick movement
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "global_position", target_pos, 0.08)
			await tween.finished
			
			current_tile = target_tile
		
		await get_tree().create_timer(0.05).timeout

func _taunt_player() -> void:
	"""Gets slightly closer to player then escapes"""
	print("Target taunting player!")
	emit_signal("target_taunting")
	
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Move a bit closer
	var closer_tile = player_tile + (current_tile - player_tile).sign() * 12
	
	if tileMap.get_cell_atlas_coords(closer_tile) != Vector2i(-1, -1):
		# Glitch to closer position
		await _glitch_vanish()
		current_tile = closer_tile
		global_position = tileMap.map_to_local(closer_tile) + offset
		await _glitch_appear()
		
		# Wait a moment
		await get_tree().create_timer(0.5).timeout
		
		# Then escape
		_escape()

func _glitch_vanish() -> void:
	"""Glitch effect when disappearing"""
	if not glitch_appearance:
		visible = false
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Rapid flicker
	for i in range(6):
		tween.tween_property(self, "modulate:a", 0.0, 0.03)
		tween.tween_property(self, "modulate:a", 1.0, 0.03)
	
	# Distort
	tween.tween_property(self, "scale", Vector2(2.0, 0.2), 0.2)
	tween.tween_property(self, "modulate", Color.RED, 0.2)
	
	await tween.finished
	visible = false

func _glitch_appear() -> void:
	"""Glitch effect when appearing"""
	if not glitch_appearance:
		visible = true
		modulate = target_color
		scale = Vector2(0.8, 0.8)
		return
	
	visible = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Distorted appearance
	scale = Vector2(0.2, 2.0)
	modulate = Color.BLUE
	
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.3)
	tween.tween_property(self, "modulate", target_color, 0.3)
	
	# Rapid flicker
	for i in range(4):
		tween.tween_property(self, "modulate:a", 0.3, 0.04)
		tween.tween_property(self, "modulate:a", 1.0, 0.04)
	
	await tween.finished

func set_position_tile(tile: Vector2i) -> void:
	"""Sets target position by tile coordinate"""
	current_tile = tile
	global_position = tileMap.map_to_local(tile) + offset

func _manhattan_distance(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)
