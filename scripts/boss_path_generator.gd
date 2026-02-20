extends Node2D

## Infinite World Generation - Webcore Horror Chase
## Creates truly infinite procedural hex world as player moves
## Player chases mysterious target while pursued by analog horror entity

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var tile_source_id := 0
@export var generation_seed := 0

# Infinite world generation settings
@export_group("World Generation")
@export var generation_radius := 15  # Tiles around player to keep generated
@export var deletion_distance := 20  # Tiles behind player to delete
@export var path_density := 0.35  # How much open space (0.0-1.0, lower = more walls)
@export var noise_scale := 0.08  # Larger = bigger path features
@export var use_multi_noise := true  # More complex/interesting paths

# Path style settings
@export_group("Path Style")
@export var min_corridor_width := 2
@export var max_corridor_width := 5
@export var organic_paths := true  # Use noise for natural-looking paths
@export var create_rooms := true  # Occasional open areas
@export var room_chance := 0.05
@export var room_size_min := 5
@export var room_size_max := 10

# Tile shaking settings
@export_group("Tile Shake Settings")
@export var shake_enabled := true
@export var shake_intensity := 6.0
@export var shake_speed := 20.0
@export var shake_decay := 3.0
@export var entity_proximity_shake := true
@export var entity_shake_range := 12.0
@export var random_shake_chance := 0.01

# Webcore/Analog Horror settings
@export_group("Horror Atmosphere")
@export var glitch_intensity := 2.0
@export var glitch_tile_chance := 0.03
@export var false_paths := true
@export var false_path_chance := 0.08

# Chase mechanics
@export_group("Chase Mechanics")
@export var chase_target_distance := 25.0
@export var target_move_trigger := 12.0
@export var delete_behind_player := true

# World state
var generated_tiles := {}  # tile_pos -> true
var last_player_tile := Vector2.ZERO
var total_tiles_generated := 0

# Tile effects
var tile_shakes := {}
var tile_offsets := {}
var glitched_tiles := {}

# Noise generators
var world_noise : FastNoiseLite
var path_noise : FastNoiseLite
var detail_noise : FastNoiseLite
var room_noise : FastNoiseLite

# RNG
var rng : RandomNumberGenerator

# References
var chasing_entity : Node2D = null
var chase_target : Node2D = null
var target_tile : Vector2

signal tiles_generated(count: int)
signal tiles_deleted(count: int)
signal reality_collapsing()
signal entity_approaching(distance: float)
signal target_moved(new_position: Vector2)

func _ready() -> void:
	_initialize_generation()
	_generate_initial_world()

func _initialize_generation() -> void:
	"""Sets up noise and RNG for infinite world generation"""
	rng = RandomNumberGenerator.new()
	if generation_seed == 0:
		rng.randomize()
	else:
		rng.seed = generation_seed
	
	# Main world noise - determines general path flow
	world_noise = FastNoiseLite.new()
	world_noise.seed = rng.randi()
	world_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	world_noise.frequency = noise_scale
	world_noise.fractal_octaves = 3
	world_noise.fractal_lacunarity = 2.0
	world_noise.fractal_gain = 0.5
	
	# Path noise - creates organic corridors
	path_noise = FastNoiseLite.new()
	path_noise.seed = rng.randi()
	path_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	path_noise.frequency = 0.15
	path_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	path_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	
	# Detail noise - adds variation
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = rng.randi()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.3
	
	# Room noise - determines room locations
	room_noise = FastNoiseLite.new()
	room_noise.seed = rng.randi()
	room_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	room_noise.frequency = 0.02
	room_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	
	# Initialize positions
	var player_tile : Vector2= tileMap.local_to_map(player.global_position)
	last_player_tile = player_tile
	target_tile = player_tile + Vector2(int(chase_target_distance), 0)
	
	print("Infinite world generator initialized - seed: ", world_noise.seed)
	print("World will generate infinitely as player moves!")

func _generate_initial_world() -> void:
	"""Generates starting area around player"""
	var player_tile = tileMap.local_to_map(player.global_position)
	_generate_tiles_around(player_tile, generation_radius + 5)  # Extra radius for start

func _process(delta: float) -> void:
	"""Continuously generates world as player moves"""
	var player_tile: Vector2 = tileMap.local_to_map(player.global_position)
	
	# Only update if player moved to new tile
	if player_tile != last_player_tile:
		_generate_tiles_around(player_tile, generation_radius)
		_update_chase_target(player_tile)
		
		if delete_behind_player:
			_delete_tiles_behind(player_tile)
		
		last_player_tile = player_tile
	
	if shake_enabled:
		_update_tile_shakes(delta)
	
	_apply_horror_effects(delta)

func _generate_tiles_around(center: Vector2i, radius: int) -> void:
	"""Generates all tiles in radius around center point"""
	var tiles_added = 0
	
	# Generate in a circle around center
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var tile_pos = center + Vector2i(x, y)
			
			# Skip if already generated
			if generated_tiles.has(tile_pos):
				continue
			
			# Skip if too far (circular generation)
			if Vector2(x, y).length() > radius:
				continue
			
			# Check if this tile should exist
			if _should_generate_tile(tile_pos):
				_place_tile(tile_pos)
				tiles_added += 1
	
	if tiles_added > 0:
		total_tiles_generated += tiles_added
		emit_signal("tiles_generated", tiles_added)

func _should_generate_tile(tile_pos: Vector2i) -> bool:
	"""Uses noise to determine if a tile should exist"""
	
	# Check if we're in a room area
	if create_rooms and _is_in_room(tile_pos):
		return true
	
	if organic_paths and use_multi_noise:
		# Multi-layer noise for complex paths
		var main = world_noise.get_noise_2d(tile_pos.x, tile_pos.y)
		var path = path_noise.get_noise_2d(tile_pos.x, tile_pos.y)
		var detail = detail_noise.get_noise_2d(tile_pos.x, tile_pos.y)
		
		# Combine noise layers with weights
		var combined = (main * 0.5) + (path * 0.35) + (detail * 0.15)
		
		# Normalize to 0-1
		combined = (combined + 1.0) / 2.0
		
		# Apply density threshold
		return combined > (1.0 - path_density)
	else:
		# Simple single-noise generation
		var noise_val = world_noise.get_noise_2d(tile_pos.x, tile_pos.y)
		var threshold = (noise_val + 1.0) / 2.0
		return threshold > (1.0 - path_density)

func _is_in_room(tile_pos: Vector2i) -> bool:
	"""Checks if position is in a procedural room"""
	var room_value = room_noise.get_noise_2d(tile_pos.x, tile_pos.y)
	
	# Rooms appear at noise "valleys"
	if room_value < 0.3:
		# Check distance to room center
		var room_center_x = round(tile_pos.x / 30.0) * 30
		var room_center_y = round(tile_pos.y / 30.0) * 30
		var center = Vector2i(room_center_x, room_center_y)
		
		var dist_to_center = tile_pos.distance_to(center)
		var room_size = rng.randf_range(room_size_min, room_size_max)
		
		if dist_to_center < room_size:
			return rng.randf() < room_chance or dist_to_center < room_size * 0.7
	
	return false

func _place_tile(tile_pos: Vector2i) -> void:
	"""Places a single tile in the infinite world"""
	tileMap.set_cell(tile_pos, tile_source_id, Vector2i(0, 0))
	generated_tiles[tile_pos] = true
	
	# Initialize effects
	if shake_enabled:
		tile_shakes[tile_pos] = 0.0
		tile_offsets[tile_pos] = Vector2.ZERO
	
	# Random glitch tiles
	if rng.randf() < glitch_tile_chance:
		glitched_tiles[tile_pos] = rng.randf_range(0.5, glitch_intensity)
	
	# Occasionally create false paths
	if false_paths and rng.randf() < false_path_chance:
		_create_false_path(tile_pos)

func _create_false_path(start_pos: Vector2i) -> void:
	"""Creates a deceptive dead-end path"""
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
	]
	var dir = directions[rng.randi() % directions.size()]
	
	var length = rng.randi_range(4, 10)
	
	for i in range(length):
		var pos = start_pos + (dir * i)
		
		if not generated_tiles.has(pos):
			tileMap.set_cell(pos, tile_source_id, Vector2i(0, 0))
			generated_tiles[pos] = true
			
			if shake_enabled:
				tile_shakes[pos] = 0.0
				tile_offsets[pos] = Vector2.ZERO
			
			# Add width at start
			if i < length / 3:
				var perp1 = Vector2i(-dir.y, dir.x)
				var perp2 = Vector2i(dir.y, -dir.x)
				
				var side1 = pos + perp1
				var side2 = pos + perp2
				
				if not generated_tiles.has(side1):
					tileMap.set_cell(side1, tile_source_id, Vector2i(0, 0))
					generated_tiles[side1] = true
					if shake_enabled:
						tile_shakes[side1] = 0.0
				
				if not generated_tiles.has(side2):
					tileMap.set_cell(side2, tile_source_id, Vector2i(0, 0))
					generated_tiles[side2] = true
					if shake_enabled:
						tile_shakes[side2] = 0.0
		
		# Increase glitch near end
		if i > length * 0.6:
			glitched_tiles[pos] = rng.randf_range(2.0, 4.0)
			tile_shakes[pos] = shake_intensity * 0.5

func _delete_tiles_behind(player_tile: Vector2i) -> void:
	"""Deletes tiles far from player (reality collapse)"""
	var tiles_to_delete = []
	
	for tile_pos in generated_tiles.keys():
		var distance = tile_pos.distance_to(player_tile)
		
		# Delete if too far
		if distance > deletion_distance:
			tiles_to_delete.append(tile_pos)
	
	# Delete the tiles
	for tile_pos in tiles_to_delete:
		tileMap.set_cell(tile_pos, -1)
		generated_tiles.erase(tile_pos)
		tile_shakes.erase(tile_pos)
		tile_offsets.erase(tile_pos)
		glitched_tiles.erase(tile_pos)
	
	if tiles_to_delete.size() > 0:
		emit_signal("tiles_deleted", tiles_to_delete.size())
		emit_signal("reality_collapsing")

func _update_chase_target(player_tile: Vector2) -> void:
	"""Moves chase target to stay ahead"""
	if not chase_target:
		return
	
	var distance = player_tile.distance_to(target_tile)
	
	# Target escapes when player gets close
	if distance < target_move_trigger:
		# Find new position ahead
		var direction = (target_tile - player_tile).normalized()
		target_tile = player_tile + Vector2(direction * chase_target_distance)
		
		# Ensure target is on walkable tile
		var attempts = 0
		while attempts < 10:
			if is_tile_generated(target_tile):
				break
			target_tile += Vector2(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			attempts += 1
		
		var target_world_pos = tileMap.map_to_local(target_tile)
		emit_signal("target_moved", target_world_pos)

func _apply_horror_effects(delta: float) -> void:
	"""Webcore horror atmosphere effects"""
	# Random glitches
	if rng.randf() < random_shake_chance:
		var tile_keys = tile_shakes.keys()
		if tile_keys.size() > 0:
			var random_tile = tile_keys[rng.randi() % tile_keys.size()]
			shake_tile(random_tile, rng.randf_range(2.0, 4.0))
	
	# Entity proximity
	if entity_proximity_shake and chasing_entity:
		var player_tile = tileMap.local_to_map(player.global_position)
		var entity_tile = tileMap.local_to_map(chasing_entity.global_position)
		var distance = player_tile.distance_to(entity_tile)
		
		if distance < entity_shake_range:
			var proximity = 1.0 - (distance / entity_shake_range)
			shake_area(player_tile, entity_shake_range * proximity, proximity * 2.0)
			emit_signal("entity_approaching", distance)

# ============================================================================
# TILE SHAKING SYSTEM
# ============================================================================

func shake_tile(tile_pos: Vector2i, intensity: float = 1.0) -> void:
	"""Shake a specific tile"""
	if not tile_shakes.has(tile_pos):
		return
	tile_shakes[tile_pos] = min(tile_shakes[tile_pos] + intensity * shake_intensity, shake_intensity * 3)

func shake_area(center_pos: Vector2i, radius: float, intensity: float = 1.0) -> void:
	"""Shake area around position"""
	for tile_pos in tile_shakes.keys():
		var dist = Vector2(tile_pos).distance_to(Vector2(center_pos))
		if dist <= radius:
			var falloff = 1.0 - (dist / radius)
			shake_tile(tile_pos, intensity * falloff)

func _update_tile_shakes(delta: float) -> void:
	"""Update shake animations"""
	for tile_pos in tile_shakes.keys():
		var shake_amount = tile_shakes[tile_pos]
		
		# Add glitch shake
		if glitched_tiles.has(tile_pos):
			shake_amount += glitched_tiles[tile_pos] * sin(Time.get_ticks_msec() * 0.003)
		
		if shake_amount > 0.01:
			var shake_offset = Vector2(
				sin(Time.get_ticks_msec() * 0.001 * shake_speed + tile_pos.x) * shake_amount,
				cos(Time.get_ticks_msec() * 0.001 * shake_speed + tile_pos.y) * shake_amount
			)
			
			tile_offsets[tile_pos] = shake_offset
			tile_shakes[tile_pos] = max(0, shake_amount - shake_decay * delta)
		else:
			tile_offsets[tile_pos] = Vector2.ZERO

func get_tile_offset(tile_pos: Vector2i) -> Vector2:
	"""Get shake offset for tile"""
	return tile_offsets.get(tile_pos, Vector2.ZERO)

# ============================================================================
# UTILITY
# ============================================================================

func get_random_walkable_tile() -> Vector2i:
	"""Get random walkable tile"""
	var keys = generated_tiles.keys()
	return keys[rng.randi() % keys.size()] if not keys.is_empty() else Vector2i.ZERO

func is_tile_generated(tile_pos: Vector2i) -> bool:
	"""Check if tile exists"""
	return generated_tiles.has(tile_pos)

func clear_world() -> void:
	"""Clear everything"""
	tileMap.clear()
	generated_tiles.clear()
	tile_shakes.clear()
	tile_offsets.clear()
	glitched_tiles.clear()
	total_tiles_generated = 0

func get_tile_count() -> int:
	"""Current tile count"""
	return generated_tiles.size()
