extends Node2D

## Enemy Spawner for Hexagonal Grid
## Spawns enemies randomly on valid tiles and handles player collision

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var enemy_scene : PackedScene  # Drag your enemy scene here
@export var spawn_count := 10  # Number of enemies to spawn
@export var min_distance_from_player := 3  # Minimum tiles away from player
@export var damage_per_enemy := 1  # HP damage when hitting enemy

var enemy_tiles := {}  # Dictionary of tile_pos -> enemy_node
var occupied_tiles := {}  # Track which tiles have enemies

signal enemy_hit(enemy_position: Vector2i, remaining_enemies: int)

func _ready() -> void:
	await get_tree().process_frame  # Wait for player to be positioned
	spawn_enemies()

func spawn_enemies() -> void:
	"""Spawns enemies on random valid tiles"""
	var valid_tiles = _get_all_valid_tiles()
	var player_tile = tileMap.local_to_map(player.global_position)
	
	# Filter out tiles too close to player
	var spawn_tiles : Array[Vector2i] = []
	for tile in valid_tiles:
		if _get_tile_distance(tile, player_tile) >= min_distance_from_player:
			spawn_tiles.append(tile)
	
	# Shuffle and take first spawn_count tiles
	spawn_tiles.shuffle()
	var enemies_to_spawn = min(spawn_count, spawn_tiles.size())
	
	print("Spawning ", enemies_to_spawn, " enemies")
	
	for i in range(enemies_to_spawn):
		var tile_pos = spawn_tiles[i]
		_spawn_enemy_at_tile(tile_pos)

func _spawn_enemy_at_tile(tile_pos: Vector2i) -> void:
	"""Spawns a single enemy at the given tile position"""
	var world_pos = tileMap.map_to_local(tile_pos)
	
	var enemy : Node2D
	if enemy_scene:
		enemy = enemy_scene.instantiate()
	else:
		# Create a simple visual representation if no scene provided
		enemy = _create_default_enemy()
	
	enemy.global_position = world_pos
	add_child(enemy)
	
	# Track this enemy
	enemy_tiles[tile_pos] = enemy
	occupied_tiles[tile_pos] = true
	
	print("Enemy spawned at tile ", tile_pos)

func _create_default_enemy() -> Node2D:
	"""Creates a default enemy visual (red circle)"""
	var enemy = Node2D.new()
	
	# Create sprite
	var sprite = Sprite2D.new()
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Draw red circle
	for x in range(32):
		for y in range(32):
			var dx = x - 16
			var dy = y - 16
			if dx * dx + dy * dy < 144:  # radius ~12
				image.set_pixel(x, y, Color.RED)
	
	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.position = Vector2(0, -8)  # Offset to match player
	enemy.add_child(sprite)
	
	return enemy

func check_player_collision(player_tile_pos: Vector2i) -> bool:
	"""
	Checks if player moved onto an enemy tile
	Returns true if enemy was hit
	"""
	if enemy_tiles.has(player_tile_pos):
		var enemy = enemy_tiles[player_tile_pos]
		
		# Remove enemy
		enemy.queue_free()
		enemy_tiles.erase(player_tile_pos)
		occupied_tiles.erase(player_tile_pos)
		
		print("Enemy hit at ", player_tile_pos, "! Remaining enemies: ", enemy_tiles.size())
		
		# Emit signal
		enemy_hit.emit(player_tile_pos, enemy_tiles.size())
		
		return true
	
	return false

func is_tile_occupied(tile_pos: Vector2i) -> bool:
	"""Checks if a tile has an enemy on it"""
	return occupied_tiles.has(tile_pos)

func _get_all_valid_tiles() -> Array[Vector2i]:
	"""Gets all walkable tiles from the tilemap"""
	var valid_tiles : Array[Vector2i] = []
	var used_cells = tileMap.get_used_cells()
	
	for cell in used_cells:
		valid_tiles.append(cell)
	
	return valid_tiles

func _get_tile_distance(a: Vector2i, b: Vector2i) -> int:
	"""Calculate hex distance between two tiles (same as in movement script)"""
	var q1 = a.x - a.y
	var r1 = a.y
	var s1 = -a.x
	
	var q2 = b.x - b.y
	var r2 = b.y
	var s2 = -b.x
	
	return (abs(q1 - q2) + abs(r1 - r2) + abs(s1 - s2)) / 2
