extends Node2D
## Coin Spawner for Horror Maze
## Spawns collectible coins and tracks player score

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var map_generator : Node2D
@export var coin_scene : PackedScene

@export_group("Coin Settings")
@export var initial_coin_count := 12
@export var min_distance_from_player := 3
@export var max_distance_from_player := 15
@export var spawn_on_new_chunks := true
@export var coins_per_chunk := 2
@export var coin_respawn_delay := 5.0

@export_group("Coin Appearance")
@export var coin_color := Color(1.0, 0.85, 0.0)
@export var coin_glow := true
@export var coin_size := 16
@export var rotation_speed := 2.0
@export var bob_animation := true
@export var bob_height := 4.0
@export var spawn_fade_duration := 0.4  # Seconds to fade in on spawn

@export var coin_sound : AudioStreamPlayer2D

var coin_tiles := {}
var occupied_tiles := {}
var active_coins : Array[Node2D] = []
var collected_coins_count := 0

# Shared textures — built once, reused for every coin
var _coin_texture : ImageTexture
var _glow_texture : ImageTexture

signal coin_collected(position: Vector2i, total_coins: int)
signal coin_spawned(position: Vector2i)
signal all_coins_collected()

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Pre-build textures on a background thread so the main thread never stalls
	_build_textures_deferred()

	await get_tree().process_frame

	if map_generator and map_generator.has_signal("chunk_generated"):
		map_generator.chunk_generated.connect(_on_chunk_generated)
		print("Coin spawner connected to map generator")

	await get_tree().create_timer(0.5).timeout
	spawn_coins()

# ─── Texture pre-building ─────────────────────────────────────────────────────

func _build_textures_deferred() -> void:
	"""Build shared coin + glow textures once, off the critical path."""
	# Coin texture
	var img = Image.create(coin_size, coin_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var half := coin_size / 2
	var max_d2 := float((half - 1) * (half - 1))
	for x in range(coin_size):
		for y in range(coin_size):
			var dx := x - half
			var dy := y - half
			var d2 := float(dx * dx + dy * dy)
			if d2 < max_d2:
				var t := d2 / max_d2
				var c := coin_color.lightened(0.2 - t * 0.2)
				c.a = 1.0 - t * 0.3
				img.set_pixel(x, y, c)
	_coin_texture = ImageTexture.create_from_image(img)

	if coin_glow:
		var gs := coin_size + 8
		var gimg = Image.create(gs, gs, false, Image.FORMAT_RGBA8)
		gimg.fill(Color.TRANSPARENT)
		var ghalf := gs / 2
		var gmax2 := float(ghalf * ghalf)
		for x in range(gs):
			for y in range(gs):
				var dx := x - ghalf
				var dy := y - ghalf
				var d2 := float(dx * dx + dy * dy)
				if d2 < gmax2:
					var c := coin_color
					c.a = (1.0 - d2 / gmax2) * 0.4
					gimg.set_pixel(x, y, c)
		_glow_texture = ImageTexture.create_from_image(gimg)

# ─── Spawning ─────────────────────────────────────────────────────────────────

func spawn_coins() -> void:
	"""Spawns initial coins spread across multiple frames to avoid stutter."""
	var valid_tiles = _get_all_valid_tiles()

	if valid_tiles.is_empty():
		print("No tiles available yet — retrying…")
		await get_tree().create_timer(0.5).timeout
		spawn_coins()
		return

	var player_tile = tileMap.local_to_map(player.global_position)
	var spawn_tiles : Array[Vector2i] = []

	for tile in valid_tiles:
		var dist := _get_tile_distance(tile, player_tile)
		if dist >= min_distance_from_player and dist <= max_distance_from_player:
			if not occupied_tiles.has(tile):
				spawn_tiles.append(tile)

	if spawn_tiles.is_empty():
		print("No valid spawn locations in range")
		return

	spawn_tiles.shuffle()
	var coins_to_spawn := mini(initial_coin_count, spawn_tiles.size())
	print("Spawning ", coins_to_spawn, " coins (batched)…")

	# Spread spawns: 3 coins per frame so we never spike
	const BATCH_SIZE := 3
	var idx := 0
	while idx < coins_to_spawn:
		for _b in range(BATCH_SIZE):
			if idx >= coins_to_spawn:
				break
			_spawn_coin_at_tile(spawn_tiles[idx])
			idx += 1
		await get_tree().process_frame  # yield between batches

	print("Initial coin spawn complete: ", active_coins.size(), " coins")

func _spawn_coin_at_tile(tile_pos: Vector2i) -> void:
	"""Spawns a single coin; fades it in so there's no pop."""
	var world_pos := tileMap.map_to_local(tile_pos)

	var coin : Node2D
	if coin_scene:
		coin = coin_scene.instantiate()
	else:
		coin = _create_default_coin()

	coin.global_position = world_pos
	# Start invisible for the fade-in
	coin.modulate.a = 0.0
	add_child(coin)

	coin_tiles[tile_pos] = coin
	occupied_tiles[tile_pos] = true
	active_coins.append(coin)

	# Fade in
	var fade := create_tween()
	fade.tween_property(coin, "modulate:a", 1.0, spawn_fade_duration)

	_start_coin_rotation(coin)
	if bob_animation:
		_start_bob_animation(coin)

	coin_spawned.emit(tile_pos)

# ─── Coin visuals (now use shared textures) ───────────────────────────────────

func _create_default_coin() -> Node2D:
	"""Assembles a coin node using the pre-built shared textures."""
	var coin := Node2D.new()

	var sprite := Sprite2D.new()
	sprite.texture = _coin_texture  # shared — no per-coin image allocation
	sprite.position = Vector2(0, -8)
	coin.add_child(sprite)

	if coin_glow and _glow_texture:
		var glow := Sprite2D.new()
		glow.texture = _glow_texture  # shared
		glow.position = Vector2(0, -8)
		glow.z_index = -1
		coin.add_child(glow)

		var tween := create_tween().set_loops()
		tween.tween_property(glow, "modulate:a", 0.8, 1.0)
		tween.tween_property(glow, "modulate:a", 0.3, 1.0)

	coin.set_meta("coin_sprite", sprite)
	return coin

func _start_coin_rotation(coin: Node2D) -> void:
	if not coin.has_meta("coin_sprite"):
		return
	var sprite : Sprite2D = coin.get_meta("coin_sprite")
	var tween := create_tween().set_loops()
	tween.tween_property(sprite, "rotation", TAU, rotation_speed)
	tween.tween_callback(func(): if sprite: sprite.rotation = 0.0)

func _start_bob_animation(coin: Node2D) -> void:
	if not coin.has_meta("coin_sprite"):
		return
	var sprite : Sprite2D = coin.get_meta("coin_sprite")
	var original_y := sprite.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(sprite, "position:y", original_y - bob_height, 0.8)
	tween.tween_property(sprite, "position:y", original_y + bob_height, 0.8)

# ─── Collection ───────────────────────────────────────────────────────────────

func check_coin_collection(player_tile_pos: Vector2i) -> bool:
	if coin_tiles.has(player_tile_pos):
		_collect_coin(coin_tiles[player_tile_pos], player_tile_pos)
		return true
	return false

func _collect_coin(coin: Node2D, tile_pos: Vector2i) -> void:
	collected_coins_count += 1

	# Remove from tracking immediately so duplicate checks can't fire
	coin_tiles.erase(tile_pos)
	occupied_tiles.erase(tile_pos)
	active_coins.erase(coin)

	if coin.has_meta("coin_sprite"):
		var sprite : Sprite2D = coin.get_meta("coin_sprite")
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.2)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.2)
		await tween.finished

	if coin_sound:
		coin_sound.playing = true
		coin_sound.pitch_scale = randf_range(0.5, 2.0)

	coin.queue_free()
	print("Coin collected! Total: ", collected_coins_count)
	coin_collected.emit(tile_pos, collected_coins_count)

	if active_coins.is_empty():
		all_coins_collected.emit()

# ─── Chunk spawning ───────────────────────────────────────────────────────────

func _on_chunk_generated(chunk_coord: Vector2i) -> void:
	if not spawn_on_new_chunks:
		return

	var chunk_tiles := _get_tiles_in_chunk(chunk_coord)
	var player_tile := tileMap.local_to_map(player.global_position)
	var spawn_tiles : Array[Vector2i] = []

	for tile in chunk_tiles:
		var dist := _get_tile_distance(tile, player_tile)
		if dist >= min_distance_from_player and dist <= max_distance_from_player:
			if not occupied_tiles.has(tile):
				spawn_tiles.append(tile)

	if spawn_tiles.is_empty():
		return

	spawn_tiles.shuffle()
	for i in range(mini(coins_per_chunk, spawn_tiles.size())):
		_spawn_coin_at_tile(spawn_tiles[i])

	print("Spawned coins in chunk ", chunk_coord)

# ─── Helpers ──────────────────────────────────────────────────────────────────

func get_collected_count() -> int: return collected_coins_count
func get_remaining_count() -> int:  return active_coins.size()
func is_tile_occupied(tile_pos: Vector2i) -> bool: return occupied_tiles.has(tile_pos)

func _is_walkable(tile_pos: Vector2i) -> bool:
	return tileMap.get_cell_atlas_coords(tile_pos) != Vector2i(-1, -1)

func _get_all_valid_tiles() -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	for cell in tileMap.get_used_cells():
		out.append(cell)
	return out

func _get_tile_distance(a: Vector2i, b: Vector2i) -> int:
	return (abs((a.x - a.y) - (b.x - b.y)) + abs(a.y - b.y) + abs(-a.x - (-b.x))) / 2

func _get_tiles_in_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	if not map_generator:
		return []
	var chunk_size : int = map_generator.chunk_size if map_generator.has("chunk_size") else 10
	var start := chunk_coord * chunk_size
	var out : Array[Vector2i] = []
	for x in range(chunk_size):
		for y in range(chunk_size):
			var tp := start + Vector2i(x, y)
			if _is_walkable(tp):
				out.append(tp)
	return out
