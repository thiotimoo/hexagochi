extends Node2D

## Analog Horror Chasing Entity - Webcore Nightmare
## Relentlessly pursues player from behind with disturbing visuals

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var path_generator : Node  # Reference to path generator
@export var offset = Vector2(0, -8)

# Entity behavior settings
@export_group("Entity Settings")
@export var movement_speed := 0.12  # Slower than player but RELENTLESS
@export var movement_delay := 0.25  # Moves frequently
@export var always_active := true  # Never stops chasing
@export var teleport_when_far := true  # Teleports if too far behind
@export var teleport_distance := 25.0  # Distance to trigger teleport
@export var damage_on_catch := 999  # Instant game over basically

# Visual/Audio settings
@export_group("Horror Atmosphere")
@export var entity_color := Color(0.1, 0.1, 0.1, 0.9)  # Almost black
@export var glitch_effect := true
@export var distortion_intensity := 2.0
@export var static_noise := true
@export var red_outline := true  # Red glitchy outline

@export var ambient_sound : AudioStreamPlayer2D  # Constant drone/static
@export var movement_sound : AudioStreamPlayer2D  # Glitch/distorted sound
@export var proximity_sound : AudioStreamPlayer2D  # Gets louder when close

# Hex directions
const HEX_DIRECTIONS_DIAMOND := [
	Vector2i(1, 0),    # East
	Vector2i(1, -1),   # Northeast
	Vector2i(0, -1),   # North
	Vector2i(-1, 0),   # West
	Vector2i(-1, 1),   # Southwest
	Vector2i(0, 1),    # South
]

# State
var is_moving := false
var is_active := true
var current_tile : Vector2i
var movement_timer := 0.0
var glitch_timer := 0.0
var teleport_timer := 0.0

# Visual effects
var sprite : Sprite2D
var outline_particles : CPUParticles2D
var distortion_shader : ShaderMaterial

signal entity_caught_player()
signal entity_teleported()
signal entity_very_close(distance: float)

func _ready() -> void:
	current_tile = tileMap.local_to_map(global_position)
	_setup_visuals()
	_setup_audio()
	
	if always_active:
		is_active = true
	
	print("Analog horror entity initialized - CHASE SEQUENCE ACTIVE")

func _setup_visuals() -> void:
	"""Sets up disturbing visual effects"""
	modulate = entity_color
	
	# Glitch outline effect
	if red_outline:
		outline_particles = CPUParticles2D.new()
		add_child(outline_particles)
		outline_particles.amount = 8
		outline_particles.lifetime = 0.5
		outline_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		outline_particles.emission_sphere_radius = 16
		outline_particles.color = Color.RED
		outline_particles.emitting = true

func _setup_audio() -> void:
	"""Sets up horror audio"""
	if ambient_sound:
		ambient_sound.play()
		ambient_sound.volume_db = -20

func _process(delta: float) -> void:
	if not is_active:
		return
	
	movement_timer += delta
	glitch_timer += delta
	teleport_timer += delta
	
	# Check distance to player
	var player_tile = tileMap.local_to_map(player.global_position)
	var distance = _hex_distance_diamond(current_tile, player_tile)
	
	# Proximity audio
	if proximity_sound and distance < 10:
		var volume = -30 + (10 - distance) * 3  # Gets louder when closer
		proximity_sound.volume_db = volume
		if not proximity_sound.playing:
			proximity_sound.play()
	
	# Visual glitch effect
	if glitch_effect and glitch_timer > 0.1:
		glitch_timer = 0.0
		_apply_glitch_effect()
	
	# Check if should teleport (player got too far ahead)
	if teleport_when_far and distance > teleport_distance and teleport_timer > 5.0:
		_teleport_behind_player()
		teleport_timer = 0.0
	
	# Check if caught player
	if distance <= 1:
		_catch_player()
		return
	
	# Emit warning if very close
	if distance < 5:
		emit_signal("entity_very_close", distance)
	
	# Move towards player
	if movement_timer >= movement_delay and not is_moving:
		movement_timer = 0.0
		_pursue_player()

func _pursue_player() -> void:
	"""Relentlessly chases the player"""
	if is_moving or not player:
		return
	
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Find path to player
	var path = _get_route_astar(player.global_position)
	
	if path.is_empty():
		# If no path, try teleporting
		if teleport_when_far:
			_teleport_behind_player()
		return
	
	# Take first step
	var movement = path[0]
	var target_tile = current_tile + movement
	var target_position = tileMap.map_to_local(target_tile) + offset
	
	is_moving = true
	
	# Shake tiles when entity moves
	if path_generator and path_generator.shake_enabled:
		path_generator.shake_area(current_tile, 4.0, 2.0)
	
	await _animate_movement(target_position)
	
	current_tile = target_tile
	is_moving = false
	
	# Play movement sound
	if movement_sound:
		movement_sound.pitch_scale = randf_range(0.3, 0.7)  # Low, distorted
		movement_sound.play()

func _teleport_behind_player() -> void:
	"""Teleports entity behind player when too far"""
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Find a tile behind the player
	var behind_offset = Vector2i(
		-randi_range(8, 12),  # Behind player
		randi_range(-2, 2)    # Slightly offset
	)
	
	var new_tile = player_tile + behind_offset
	
	# Check if tile is valid
	if tileMap.get_cell_atlas_coords(new_tile) != Vector2i(-1, -1):
		current_tile = new_tile
		global_position = tileMap.map_to_local(new_tile) + offset
		
		# Massive glitch effect
		_massive_glitch()
		
		# Huge shake
		if path_generator:
			path_generator.shake_area(new_tile, 12.0, 4.0)
		
		emit_signal("entity_teleported")
		print("ENTITY TELEPORTED - IT'S BEHIND YOU")

func _catch_player() -> void:
	"""Entity caught the player - game over"""
	print("ENTITY HAS CAUGHT YOU")
	emit_signal("entity_caught_player")
	
	# Stop moving
	is_active = false
	
	# Massive visual distortion
	_massive_glitch()
	
	# Huge shake
	if path_generator:
		path_generator.shake_area(current_tile, 20.0, 10.0)
	
	# Play catch sound if available
	if proximity_sound:
		proximity_sound.volume_db = 0
		proximity_sound.pitch_scale = 0.5

func _apply_glitch_effect() -> void:
	"""Creates glitch visual effect"""
	# Random position offset
	position = Vector2(
		randf_range(-distortion_intensity, distortion_intensity),
		randf_range(-distortion_intensity, distortion_intensity)
	)
	
	# Random color corruption
	var glitch_color = entity_color
	if randf() < 0.1:
		glitch_color = Color(randf(), 0, 0, 0.9)  # Red glitch
	modulate = glitch_color

func _massive_glitch() -> void:
	"""Intense glitch effect for teleportation"""
	for i in range(10):
		position = Vector2(
			randf_range(-10, 10),
			randf_range(-10, 10)
		)
		modulate = Color(randf(), 0, 0, randf())
		await get_tree().create_timer(0.05).timeout
	
	position = Vector2.ZERO
	modulate = entity_color

func _animate_movement(target_pos: Vector2) -> void:
	"""Disturbing, unnatural movement animation"""
	# No anticipation - instant jerky movement
	var movement_tween := create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)  # Unnatural, robotic
	movement_tween.tween_property(self, "global_position", target_pos, movement_speed)
	
	# Random glitch during movement
	if randf() < 0.3:
		modulate = Color.RED
		await get_tree().create_timer(movement_speed * 0.5).timeout
		modulate = entity_color
	
	await movement_tween.finished

# ============================================================================
# A* PATHFINDING
# ============================================================================

func _get_route_astar(targetPosition: Vector2) -> Array[Vector2i]:
	"""A* pathfinding"""
	var start_tile := current_tile
	var target_tile := tileMap.local_to_map(targetPosition)
	
	var open_set: Array[Vector2i] = [start_tile]
	var came_from := {}
	var g_score := {start_tile: 0}
	var f_score := {start_tile: _hex_distance_diamond(start_tile, target_tile)}
	
	var iterations = 0
	var max_iterations = 300
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		var current := _get_lowest_f_score_node(open_set, f_score)
		
		if current == target_tile:
			return _reconstruct_path(came_from, current, start_tile)
		
		open_set.erase(current)
		
		for dir in HEX_DIRECTIONS_DIAMOND:
			var neighbor = current + dir
			
			if not _is_walkable(neighbor):
				continue
			
			var tentative_g_score = g_score[current] + 1
			
			if not g_score.has(neighbor) or tentative_g_score < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g_score
				f_score[neighbor] = tentative_g_score + _hex_distance_diamond(neighbor, target_tile)
				
				if not open_set.has(neighbor):
					open_set.append(neighbor)
	
	return []

func _is_walkable(tile_pos: Vector2i) -> bool:
	var tileData = tileMap.get_cell_atlas_coords(tile_pos)
	return tileData != Vector2i(-1, -1)

func _hex_distance_diamond(a: Vector2i, b: Vector2i) -> int:
	var q1 = a.x - a.y
	var r1 = a.y
	var s1 = -a.x
	
	var q2 = b.x - b.y
	var r2 = b.y
	var s2 = -b.x
	
	return (abs(q1 - q2) + abs(r1 - r2) + abs(s1 - s2)) / 2

func _get_lowest_f_score_node(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest_node := open_set[0]
	var lowest_score : int = f_score.get(lowest_node, INF)
	
	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest_score = score
			lowest_node = node
	
	return lowest_node

func _reconstruct_path(came_from: Dictionary, current: Vector2i, start: Vector2i) -> Array[Vector2i]:
	var path_tiles: Array[Vector2i] = [current]
	
	while came_from.has(current):
		current = came_from[current]
		path_tiles.push_front(current)
	
	var route: Array[Vector2i] = []
	for i in range(path_tiles.size() - 1):
		var a := path_tiles[i]
		var b := path_tiles[i + 1]
		var movement = b - a
		route.append(movement)
	
	return route
