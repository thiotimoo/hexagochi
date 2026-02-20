extends Node2D

## Hexagonal A* Movement System with Game Integration
## Now includes enemy collision, coin collection, and HP depletion

@export var tileMap : TileMapLayer
@export var offSet = Vector2(0, -8)
@export var movement_speed := 0.1
@export var show_path_preview := true
@export var path_preview_color := Color(1, 1, 0, 0.8)
@export var allow_diagonal := true

# Game system references
@export var enemy_spawner : Node  # Reference to EnemySpawner
@export var coin_spawner : Node  # Reference to CoinSpawner
@export var player_hp : Node  # Reference to PlayerHP
@export var walk_sound: AudioStreamPlayer2D

# Diamond isometric hex directions
const HEX_DIRECTIONS_DIAMOND := [
	Vector2i(1, 0),    # East
	Vector2i(1, -1),   # Northeast
	Vector2i(0, -1),   # North
	Vector2i(-1, 0),   # West
	Vector2i(-1, 1),   # Southwest
	Vector2i(0, 1),    # South
]

var isMoving = false
var path_line : Line2D

func _ready() -> void:
	# Create path preview line
	path_line = Line2D.new()
	path_line.width = 4.0
	path_line.default_color = path_preview_color
	path_line.z_index = 10
	path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(path_line)
	print("Movement system initialized with game integration")

func _process(_delta: float) -> void:
	# check if a dialog is already running
	if Dialogic.current_timeline != null:
		return
	if show_path_preview and not isMoving:
		_update_path_preview()

func _update_path_preview() -> void:
	"""Updates the visual path preview"""
	var mousePosition = get_global_mouse_position()
	var isTargetPositionValid = get_tile_global_position(mousePosition)
	
	if not isTargetPositionValid:
		path_line.clear_points()
		return
	
	if not isTargetPositionValid:
		path_line.clear_points()
		return
	
	var route = _get_route_astar(mousePosition)
	if route.is_empty():
		path_line.clear_points()
		return
	
	# Build path line
	path_line.clear_points()
	var current_pos = get_parent().global_position
	path_line.add_point(current_pos - global_position)
	
	for movement in route:
		var playerTilePosition = tileMap.local_to_map(current_pos)
		var targetTilePosition = playerTilePosition + movement
		var targetPosition = tileMap.map_to_local(targetTilePosition) + offSet
		path_line.add_point(targetPosition - global_position)
		current_pos = targetPosition

func _input(event: InputEvent) -> void:
	# check if a dialog is already running
	if Dialogic.current_timeline != null:
		return
	if Input.is_action_just_pressed("leftClick"):
		_move()

func _move():
	"""Movement with enemy and coin collision detection"""
	if isMoving: 
		return
	
	# Check if player is alive
	if player_hp and not player_hp.is_alive():
		print("Cannot move - player is dead!")
		return
	
	var mousePosition = get_global_mouse_position()
	var isTargetPositionValid = get_tile_global_position(mousePosition)
	
	if not isTargetPositionValid: 
		print("Target position invalid")
		return
	
	isMoving = true
	path_line.clear_points()
	
	var movementArray = _get_route_astar(mousePosition)
	
	if movementArray.is_empty():
		print("No path found!")
		isMoving = false
		return
	
	print("Moving along path with ", movementArray.size(), " steps")
	
	# Animate along path
	for i in range(movementArray.size()):
		var movement = movementArray[i]
		var playerTilePosition = tileMap.local_to_map(get_parent().global_position)
		var targetTilePosition = playerTilePosition + movement
		var targetPosition = tileMap.map_to_local(targetTilePosition) + offSet
		
		var direction = (targetPosition - get_parent().global_position).normalized()
		
		await _animate_movement_with_squash(get_parent(), targetPosition, direction)
		
		walk_sound.playing = true
		walk_sound.pitch_scale = randf_range(.5,2)
		
		# Check collisions after each step
		_check_tile_interactions(targetTilePosition)
		
		# Stop if player died
		if player_hp and not player_hp.is_alive():
			print("Player died during movement!")
			break
	
	isMoving = false


func _check_tile_interactions(tile_pos: Vector2i) -> void:
	"""Checks for enemies and coins at the given tile"""
	# Check for coin collection FIRST
	if coin_spawner and coin_spawner.check_coin_collection(tile_pos):
		print("Collected coin!")
		_play_collect_effect()
	
	# Then check for enemy collision
	if enemy_spawner and enemy_spawner.check_player_collision(tile_pos):
		print("Hit enemy!")
		if player_hp:
			player_hp.take_damage(enemy_spawner.damage_per_hit)
			_play_damage_effect()


func _play_damage_effect() -> void:
	"""Visual feedback for taking damage"""
	var parent = get_parent()
	if not parent:
		return
	
	# Flash red
	var original_modulate = parent.modulate
	var tween = create_tween()
	tween.tween_property(parent, "modulate", Color.RED, 0.1)
	tween.tween_property(parent, "modulate", original_modulate, 0.1)

func _play_collect_effect() -> void:
	"""Visual feedback for collecting coin"""
	var parent = get_parent()
	if not parent:
		return
	
	# Flash yellow
	var original_modulate = parent.modulate
	var tween = create_tween()
	tween.tween_property(parent, "modulate", Color.YELLOW, 0.1)
	tween.tween_property(parent, "modulate", original_modulate, 0.1)

func _animate_movement_with_squash(node: Node2D, target_pos: Vector2, direction: Vector2) -> void:
	"""Animates movement with squash and stretch"""
	# ANTICIPATION
	var anticipation_tween := create_tween()
	anticipation_tween.set_trans(Tween.TRANS_QUAD)
	anticipation_tween.set_ease(Tween.EASE_OUT)
	anticipation_tween.tween_property(node, "scale", Vector2(1.15, 0.85), 0.08)
	await anticipation_tween.finished
	
	# MOVEMENT
	var movement_tween := create_tween()
	movement_tween.set_parallel(true)
	movement_tween.set_trans(Tween.TRANS_SINE)
	movement_tween.set_ease(Tween.EASE_IN_OUT)
	
	movement_tween.tween_property(node, "global_position", target_pos, movement_speed)
	movement_tween.tween_property(node, "scale", Vector2(0.95, 1.05), movement_speed * 0.4)
	
	await get_tree().create_timer(movement_speed * 0.6).timeout
	
	# LANDING
	var landing_tween := create_tween()
	landing_tween.set_trans(Tween.TRANS_BACK)
	landing_tween.set_ease(Tween.EASE_OUT)
	landing_tween.tween_property(node, "scale", Vector2(1.12, 0.88), 0.06)
	await landing_tween.finished
	
	# NORMALIZE
	var normalize_tween := create_tween()
	normalize_tween.set_trans(Tween.TRANS_ELASTIC)
	normalize_tween.set_ease(Tween.EASE_OUT)
	normalize_tween.tween_property(node, "scale", Vector2.ONE, 0.2)
	await normalize_tween.finished

func get_tile_global_position(mousePosition):
	"""Validates if mouse position is over a valid tile"""
	var mouseTilePosition := tileMap.local_to_map(mousePosition)
	var mouseTileData = tileMap.get_cell_atlas_coords(mouseTilePosition)
	if mouseTileData == Vector2i(-1, -1): 
		return null
	
	var tileGlobalPosition = tileMap.map_to_local(mouseTilePosition)
	return Vector2i(tileGlobalPosition)

func _get_route_astar(targetPosition) -> Array[Vector2i]:
	"""A* pathfinding for diamond isometric hex grids"""
	var start_tile := tileMap.local_to_map(get_parent().global_position)
	var target_tile := tileMap.local_to_map(targetPosition)
	
	var open_set: Array[Vector2i] = [start_tile]
	var came_from := {}
	var g_score := {start_tile: 0}
	var f_score := {start_tile: _hex_distance_diamond(start_tile, target_tile)}
	
	var iterations = 0
	var max_iterations = 1000
	
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
	"""Checks if a tile is walkable"""
	var tileData = tileMap.get_cell_atlas_coords(tile_pos)
	return tileData != Vector2i(-1, -1)

func _hex_distance_diamond(a: Vector2i, b: Vector2i) -> int:
	"""Calculates hex distance for diamond isometric"""
	var q1 = a.x - a.y
	var r1 = a.y
	var s1 = -a.x
	
	var q2 = b.x - b.y
	var r2 = b.y
	var s2 = -b.x
	
	return (abs(q1 - q2) + abs(r1 - r2) + abs(s1 - s2)) / 2

func _get_lowest_f_score_node(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	"""Finds node with lowest f_score"""
	var lowest_node := open_set[0]
	var lowest_score : int = f_score.get(lowest_node, INF)
	
	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest_score = score
			lowest_node = node
	
	return lowest_node

func _reconstruct_path(came_from: Dictionary, current: Vector2i, start: Vector2i) -> Array[Vector2i]:
	"""Reconstructs path from came_from dictionary"""
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
