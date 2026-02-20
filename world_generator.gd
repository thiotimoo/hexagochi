extends Node2D

## Procedural Hexagonal Map Generator - Horror Edition
## Generates cramped, claustrophobic dungeon maps

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var chunk_size := 10  # Tiles per chunk
@export var tile_source_id := 0
@export var generation_seed := 0  # 0 = random seed

# Horror-themed generation parameters - MUCH MORE CRAMPED
@export_group("Horror Settings")
@export var wall_probability := 0.65  # INCREASED from 0.25 - way more walls
@export var min_open_space := 0.15  # REDUCED from 0.6 - very cramped
@export var corridor_width := 1  # Single-tile corridors only
@export var add_dead_ends := true  # Create scary dead-end corridors
@export var dead_end_probability := 0.3  # Chance to create dead ends
@export var twist_corridors := true  # Make paths winding and confusing

# Biome system - Different atmospheric areas using atlas IDs
@export_group("Biome Settings")
@export var enable_biomes := true
@export var biome_size := 3  # Chunks per biome (3x3 chunk areas)
@export var blend_biomes := true  # Smooth transitions between biomes
@export var blend_distance := 2  # Tiles to blend at edges

# Define biomes with atlas IDs (configure based on your tileset)
@export_subgroup("Biome Atlas IDs")
@export var default_biome_id := 0  # Default stone/floor
@export var decay_biome_id := 1  # Rotting/organic
@export var blood_biome_id := 2  # Bloodstained
@export var shadow_biome_id := 3  # Dark/void
@export var bone_biome_id := 4  # Skeletal/death
@export var flesh_biome_id := 5  # Fleshy/organic horror
@export var corruption_biome_id := 6  # Corrupted/twisted

# Biome tracking
var biome_map := {}  # Maps biome_coord -> biome_type
var biome_noise : FastNoiseLite  # Separate noise for biome selection

# Chunk tracking
var generated_chunks := {}  # Dictionary of chunk_coords -> true
var active_chunks : Array[Vector2i] = []

# Map generation parameters
var noise : FastNoiseLite
var rng : RandomNumberGenerator

signal chunk_generated(chunk_coord: Vector2i)

func _ready() -> void:
	_initialize_generation()
	_generate_initial_chunks()

func _initialize_generation() -> void:
	"""Sets up noise and RNG for procedural generation"""
	# Setup RNG
	rng = RandomNumberGenerator.new()
	if generation_seed == 0:
		rng.randomize()
	else:
		rng.seed = generation_seed
	
	# Setup noise for organic patterns (more chaotic for horror)
	noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.18  # INCREASED from 0.08 for tighter, more claustrophobic patterns
	noise.fractal_octaves = 4  # More detail and complexity
	noise.fractal_lacunarity = 2.8  # Sharper, more dramatic transitions
	noise.fractal_gain = 0.6  # Rougher terrain
	
	# Setup biome noise for regional variation
	biome_noise = FastNoiseLite.new()
	biome_noise.seed = rng.randi()
	biome_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	biome_noise.frequency = 0.03  # Much lower - creates large biome regions
	biome_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	biome_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	
	print("Horror map generator initialized with seed: ", noise.seed)
	print("Biome system enabled: ", enable_biomes)

func _generate_initial_chunks() -> void:
	"""Generates starting chunks around player"""
	var player_chunk = _world_to_chunk(player.global_position)
	
	# Generate 3x3 grid of chunks around player
	for x in range(-1, 2):
		for y in range(-1, 2):
			var chunk_coord = player_chunk + Vector2i(x, y)
			_generate_chunk(chunk_coord)

func _process(_delta: float) -> void:
	"""Continuously checks if new chunks need generation"""
	_update_chunks_around_player()

func _update_chunks_around_player() -> void:
	"""Generates chunks near player and unloads distant ones"""
	var player_chunk = _world_to_chunk(player.global_position)
	var load_distance := 2  # Chunks to keep loaded around player
	
	# Generate nearby chunks
	for x in range(-load_distance, load_distance + 1):
		for y in range(-load_distance, load_distance + 1):
			var chunk_coord = player_chunk + Vector2i(x, y)
			if not generated_chunks.has(chunk_coord):
				_generate_chunk(chunk_coord)

func _generate_chunk(chunk_coord: Vector2i) -> void:
	"""Generates a single chunk of tiles - HORROR VERSION"""
	if generated_chunks.has(chunk_coord):
		return
	
	print("Generating horror chunk: ", chunk_coord)
	
	var start_tile = chunk_coord * chunk_size
	var tiles_placed = 0
	var walkable_tiles = 0
	
	# Generate tiles in this chunk with MUCH LESS open space
	for x in range(chunk_size):
		for y in range(chunk_size):
			var tile_pos = start_tile + Vector2i(x, y)
			
			# Use noise to determine if this should be walkable
			if _should_generate_tile(tile_pos):
				_place_tile(tile_pos)
				walkable_tiles += 1
				tiles_placed += 1
	
	# Add narrow, winding corridors instead of open paths
	_add_cramped_corridors(start_tile)
	
	# Occasionally add dead ends for horror effect
	if add_dead_ends and rng.randf() < dead_end_probability:
		_add_dead_end_corridor(start_tile)
	
	generated_chunks[chunk_coord] = true
	active_chunks.append(chunk_coord)
	
	emit_signal("chunk_generated", chunk_coord)
	
	print("Horror chunk ", chunk_coord, " generated: ", tiles_placed, " tiles (very cramped)")

func _should_generate_tile(tile_pos: Vector2i) -> bool:
	"""Determines if a tile should exist - MUCH MORE RESTRICTIVE"""
	# Get noise value (-1 to 1)
	var noise_value = noise.get_noise_2d(tile_pos.x, tile_pos.y)
	
	# Convert to 0-1 range
	var threshold = (noise_value + 1.0) / 2.0
	
	# Add extra randomness for more chaotic feel
	var random_factor = rng.randf() * 0.15
	threshold += random_factor
	
	# Generate tile ONLY if well above wall probability (creates cramped spaces)
	return threshold > wall_probability

func _add_cramped_corridors(start_tile: Vector2i) -> void:
	"""Creates narrow, single-tile winding corridors for claustrophobic feel"""
	var center = start_tile + Vector2i(chunk_size / 2, chunk_size / 2)
	
	if twist_corridors:
		# Create winding path instead of straight
		var current_pos = start_tile
		
		# Horizontal winding path
		for x in range(chunk_size):
			var tile_pos = start_tile + Vector2i(x, chunk_size / 2)
			_place_tile(tile_pos)
			
			# Occasionally zigzag
			if rng.randf() < 0.3:
				var offset = 1 if rng.randf() > 0.5 else -1
				_place_tile(tile_pos + Vector2i(0, offset))
		
		# Vertical winding path
		for y in range(chunk_size):
			var tile_pos = start_tile + Vector2i(chunk_size / 2, y)
			_place_tile(tile_pos)
			
			# Occasionally zigzag
			if rng.randf() < 0.3:
				var offset = 1 if rng.randf() > 0.5 else -1
				_place_tile(tile_pos + Vector2i(offset, 0))
	else:
		# Simple narrow corridors
		for x in range(chunk_size):
			_place_tile(start_tile + Vector2i(x, chunk_size / 2))
		
		for y in range(chunk_size):
			_place_tile(start_tile + Vector2i(chunk_size / 2, y))

func _add_dead_end_corridor(start_tile: Vector2i) -> void:
	"""Creates a dead-end corridor for horror atmosphere"""
	# Pick random starting edge
	var start_x = rng.randi_range(0, chunk_size - 1)
	var start_y = rng.randi_range(0, chunk_size - 1)
	
	var current = start_tile + Vector2i(start_x, start_y)
	var length = rng.randi_range(3, 6)
	
	# Random direction
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var dir = directions[rng.randi() % directions.size()]
	
	# Create corridor
	for i in range(length):
		_place_tile(current)
		current += dir
		
		# Occasionally branch for extra confusion
		if rng.randf() < 0.2:
			var branch_dir = Vector2i(dir.y, dir.x)  # Perpendicular
			_place_tile(current + branch_dir)

func _place_tile(tile_pos: Vector2i) -> void:
	"""Places a single tile on the map with biome-appropriate atlas ID"""
	var atlas_id = default_biome_id
	
	if enable_biomes:
		atlas_id = _get_biome_tile_id(tile_pos)
	
	tileMap.set_cell(tile_pos, tile_source_id, Vector2i(0, atlas_id))

func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	"""Converts world position to chunk coordinate"""
	var tile_pos = tileMap.local_to_map(world_pos)
	return Vector2i(
		floori(float(tile_pos.x) / chunk_size),
		floori(float(tile_pos.y) / chunk_size)
	)

func get_random_walkable_tile() -> Vector2i:
	"""Returns a random walkable tile from generated chunks"""
	var attempts = 0
	var max_attempts = 100
	
	while attempts < max_attempts:
		# Pick random chunk
		if active_chunks.is_empty():
			return Vector2i.ZERO
		
		var chunk = active_chunks[rng.randi() % active_chunks.size()]
		var start_tile = chunk * chunk_size
		
		# Pick random tile in chunk
		var random_offset = Vector2i(
			rng.randi() % chunk_size,
			rng.randi() % chunk_size
		)
		var tile_pos = start_tile + random_offset
		
		# Check if walkable
		if tileMap.get_cell_atlas_coords(tile_pos) != Vector2i(-1, -1):
			return tile_pos
		
		attempts += 1
	
	return Vector2i.ZERO

func _get_biome_tile_id(tile_pos: Vector2i) -> int:
	"""Determines which atlas ID to use based on biome"""
	var biome_coord = _tile_to_biome(tile_pos)
	
	# Get or generate biome type for this region
	if not biome_map.has(biome_coord):
		biome_map[biome_coord] = _generate_biome_type(biome_coord)
	
	var biome_type = biome_map[biome_coord]
	
	# Blend at edges if enabled
	if blend_biomes:
		var blend_id = _get_blended_biome_id(tile_pos, biome_coord, biome_type)
		if blend_id != -1:
			return blend_id
	
	return biome_type

func _generate_biome_type(biome_coord: Vector2i) -> int:
	"""Generates a biome type for a biome region"""
	# Use noise to determine biome
	var noise_val = biome_noise.get_noise_2d(biome_coord.x, biome_coord.y)
	
	# Map noise value (-1 to 1) to biome types
	# Create distinct regions for each biome
	var all_biomes = [
		default_biome_id,
		decay_biome_id,
		blood_biome_id,
		shadow_biome_id,
		bone_biome_id,
		flesh_biome_id,
		corruption_biome_id
	]
	
	# Normalize noise to 0-1
	var normalized = (noise_val + 1.0) / 2.0
	
	# Pick biome based on noise
	var biome_index = int(normalized * all_biomes.size())
	biome_index = clamp(biome_index, 0, all_biomes.size() - 1)
	
	var selected_biome = all_biomes[biome_index]
	print("Biome region ", biome_coord, " = ", _get_biome_name(selected_biome))
	
	return selected_biome

func _get_blended_biome_id(tile_pos: Vector2i, current_biome_coord: Vector2i, current_biome: int) -> int:
	"""Creates smooth transitions between biomes"""
	# Check distance to biome edge
	var biome_tile_size = biome_size * chunk_size
	var local_pos = Vector2i(
		tile_pos.x % biome_tile_size,
		tile_pos.y % biome_tile_size
	)
	
	# Calculate distance to nearest edge
	var dist_to_edge_x = mini(local_pos.x, biome_tile_size - local_pos.x)
	var dist_to_edge_y = mini(local_pos.y, biome_tile_size - local_pos.y)
	var min_dist = mini(dist_to_edge_x, dist_to_edge_y)
	
	# If within blend distance, check neighboring biomes
	if min_dist < blend_distance:
		# Check which edge we're near and get neighbor biome
		var neighbor_biome_coord = current_biome_coord
		
		if dist_to_edge_x < dist_to_edge_y:
			# Near horizontal edge
			if local_pos.x < blend_distance:
				neighbor_biome_coord.x -= 1
			else:
				neighbor_biome_coord.x += 1
		else:
			# Near vertical edge
			if local_pos.y < blend_distance:
				neighbor_biome_coord.y -= 1
			else:
				neighbor_biome_coord.y += 1
		
		# Get neighbor biome
		if not biome_map.has(neighbor_biome_coord):
			biome_map[neighbor_biome_coord] = _generate_biome_type(neighbor_biome_coord)
		
		var neighbor_biome = biome_map[neighbor_biome_coord]
		
		# Use noise to blend between biomes
		var blend_noise = noise.get_noise_2d(tile_pos.x * 0.5, tile_pos.y * 0.5)
		var blend_factor = (blend_noise + 1.0) / 2.0
		
		# Randomly pick between current and neighbor based on noise
		if blend_factor > 0.5:
			return neighbor_biome
	
	return -1  # No blend needed

func _tile_to_biome(tile_pos: Vector2i) -> Vector2i:
	"""Converts tile position to biome coordinate"""
	var biome_tile_size = biome_size * chunk_size
	return Vector2i(
		floori(float(tile_pos.x) / biome_tile_size),
		floori(float(tile_pos.y) / biome_tile_size)
	)

func _get_biome_name(biome_id: int) -> String:
	"""Returns readable biome name for debugging"""
	match biome_id:
		0: return "Default"
		1: return "Decay"
		2: return "Blood"
		3: return "Shadow"
		4: return "Bone"
		5: return "Flesh"
		6: return "Corruption"
		_: return "Unknown"

func clear_map() -> void:
	"""Clears all generated chunks"""
	tileMap.clear()
	generated_chunks.clear()
	active_chunks.clear()
