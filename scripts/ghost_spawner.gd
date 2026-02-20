extends Node2D
## ██████████████████████████████████████████████████
## ENTITY SPAWNER — analog horror, tile-based horror maze
## "They were here before the map was generated."
## ██████████████████████████████████████████████████

@export var tileMap : TileMapLayer
@export var player : Node2D
@export var map_generator : Node2D
@export var enemy_scene : PackedScene   # leave empty to use procedural visuals

# ── Spawn ──────────────────────────────────────────────────────────────────────
@export_group("Spawn Settings")
@export var spawn_count := 6                  # fewer = scarier
@export var min_distance_from_player := 7
@export var max_distance_from_player := 14
@export var respawn_on_new_chunks := true
@export var spawn_fade_duration := 1.2

# ── Behaviour ──────────────────────────────────────────────────────────────────
@export_group("Behaviour")
@export var chase_interval := 0.45            # seconds between tile steps
@export var chase_stop_distance := 2          # tiles — personal space
@export var teleport_when_stuck := true       # if blocked >N steps, teleport behind player
@export var stuck_threshold := 4             # steps before teleport
@export var damage_per_hit := 1

# ── Distortion (post-process on CanvasLayer, optional) ─────────────────────────
@export_group("Screen Distortion")
@export var distortion_enabled := true
@export var distortion_label : RichTextLabel   # drop a RichTextLabel overlay here
@export var vhs_noise_label : Label            # drop a plain Label here for scan lines

# ── Appearance ─────────────────────────────────────────────────────────────────
@export_group("Appearance")
@export var entity_size := 32
@export var breathing_speed := 1.6

# ── Signals ────────────────────────────────────────────────────────────────────
signal entity_spawned(position: Vector2i)
signal entity_nearby(distance: int)
signal entity_touched_player()

# ── Internals ──────────────────────────────────────────────────────────────────
var entity_tiles   := {}   # tile_pos  -> Node2D
var occupied_tiles := {}   # tile_pos  -> true
var active_entities : Array[Node2D] = []
var _stuck_counters : Dictionary = {}   # entity -> int

var _chase_timer := 0.0
var _distort_timer := 0.0
var _glitch_timer := 0.0

# Shared textures
var _body_tex    : ImageTexture   # main shadowy oval
var _static_tex  : ImageTexture   # TV-static texture for face region
var _eye_tex     : ImageTexture   # single eye sprite (reused)
var _mouth_tex   : ImageTexture   # stitched-mouth line

# Each entity gets a random "variant" at spawn so no two look the same
enum Variant { WATCHER, CRAWLER, SCREAMER, HOLLOW }

# Hex neighbour offsets
const HEX_DIRS : Array[Vector2i] = [
	Vector2i(1,  0), Vector2i(-1,  0),
	Vector2i(0,  1), Vector2i(0, -1),
	Vector2i(1, -1), Vector2i(-1,  1),
]

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_shared_textures()
	await get_tree().process_frame

	if map_generator and map_generator.has_signal("chunk_generated"):
		map_generator.chunk_generated.connect(_on_chunk_generated)

	await get_tree().create_timer(0.6).timeout
	spawn_entities()

# ─────────────────────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_chase_timer += delta
	if _chase_timer >= chase_interval:
		_chase_timer = 0.0
		_step_all_entities()

	_update_entity_behaviors(delta)
	_check_proximity()

	if distortion_enabled:
		_distort_timer += delta
		_glitch_timer  += delta
		_update_screen_distortion(delta)

# ─────────────────────────────────────────────────────────────────────────────
#  TEXTURE BUILDING  (once, shared across all entities)
# ─────────────────────────────────────────────────────────────────────────────
func _build_shared_textures() -> void:
	var s := entity_size

	# ── Body: tall dark oval, wispy edges ──────────────────────────────────────
	var bw := s
	var bh := int(s * 1.6)
	var body_img := Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	body_img.fill(Color.TRANSPARENT)
	var cx := bw / 2.0
	var cy := bh * 0.45
	for x in range(bw):
		for y in range(bh):
			var dx := (x - cx) / (bw * 0.42)
			var dy := (y - cy) / (bh * 0.46)
			var d := dx*dx + dy*dy
			if d < 1.0:
				# Core is near-black with slight desaturated purple tint
				var t := 1.0 - d
				var c := Color(0.04, 0.0, 0.06)
				c.a = pow(t, 0.55) * 0.92
				# Wispy noise at edges
				if t < 0.25:
					var noise_seed := int(x * 7 + y * 13) % 17
					c.a *= 0.4 + 0.6 * (noise_seed / 17.0)
				body_img.set_pixel(x, y, c)
	_body_tex = ImageTexture.create_from_image(body_img)

	# ── Static face texture (TV noise pattern) ────────────────────────────────
	var fs := 20
	var static_img := Image.create(fs, fs, false, Image.FORMAT_RGBA8)
	static_img.fill(Color.TRANSPARENT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEADF00D
	for x in range(fs):
		for y in range(fs):
			var v := rng.randf()
			var alpha := 0.0
			var dx2 := (x - fs/2.0) / (fs * 0.45)
			var dy2 := (y - fs/2.0) / (fs * 0.45)
			if dx2*dx2 + dy2*dy2 < 1.0:
				alpha = v * 0.55
			static_img.set_pixel(x, y, Color(v, v * 0.9, v * 0.8, alpha))
	_static_tex = ImageTexture.create_from_image(static_img)

	# ── Eye: large single eye with cracked sclera ─────────────────────────────
	var es := 14
	var eye_img := Image.create(es, es, false, Image.FORMAT_RGBA8)
	eye_img.fill(Color.TRANSPARENT)
	var er := es / 2.0
	for x in range(es):
		for y in range(es):
			var dx3 := x - er
			var dy3 := y - er
			var d3 := sqrt(dx3*dx3 + dy3*dy3)
			if d3 < er - 0.5:
				# Yellowed sclera
				var base_c := Color(0.85, 0.82, 0.68)
				# Red vein lines (deterministic noise)
				var vein := sin(dx3 * 3.7 + dy3 * 1.1) * cos(dy3 * 2.3 - dx3 * 0.9)
				if vein > 0.6:
					base_c = Color(0.7, 0.1, 0.05)
				# Iris (dark)
				if d3 < er * 0.55:
					base_c = Color(0.15, 0.05, 0.0)
				# Pupil (void black)
				if d3 < er * 0.28:
					base_c = Color(0.0, 0.0, 0.0)
				# Catch light (tiny white dot)
				if dx3 > er * 0.2 and dy3 < -er * 0.15 and d3 < er * 0.25:
					base_c = Color(1.0, 1.0, 1.0)
				base_c.a = 1.0 - pow(d3 / er, 6.0)
				eye_img.set_pixel(x, y, base_c)
	_eye_tex = ImageTexture.create_from_image(eye_img)

	# ── Mouth: horizontal stitched line ───────────────────────────────────────
	var mw := 18
	var mh := 6
	var mouth_img := Image.create(mw, mh, false, Image.FORMAT_RGBA8)
	mouth_img.fill(Color.TRANSPARENT)
	for x in range(mw):
		# Horizontal slit
		for y in [2, 3]:
			mouth_img.set_pixel(x, y, Color(0.25, 0.0, 0.02, 0.9))
		# Vertical stitch marks every 4 pixels
		if x % 4 == 0:
			for y in range(mh):
				mouth_img.set_pixel(x, y, Color(0.4, 0.05, 0.05, 0.7))
	_mouth_tex = ImageTexture.create_from_image(mouth_img)

# ─────────────────────────────────────────────────────────────────────────────
#  ENTITY CONSTRUCTION
# ─────────────────────────────────────────────────────────────────────────────
func _create_entity(variant: Variant) -> Node2D:
	var root := Node2D.new()
	root.set_meta("variant", variant)

	# ── Body ──────────────────────────────────────────────────────────────────
	var body := Sprite2D.new()
	body.texture = _body_tex
	body.name = "Body"

	# Variant tint
	match variant:
		Variant.WATCHER:   body.modulate = Color(0.9, 0.9, 1.0, 0.85)  # cold blue-white
		Variant.CRAWLER:   body.modulate = Color(1.0, 0.7, 0.4, 0.9)   # jaundiced yellow
		Variant.SCREAMER:  body.modulate = Color(1.0, 0.4, 0.3, 0.95)  # angry red tint
		Variant.HOLLOW:    body.modulate = Color(0.5, 1.0, 0.6, 0.6)   # sickly green, translucent

	root.add_child(body)
	root.set_meta("body", body)

	# ── Static face overlay ────────────────────────────────────────────────────
	var face := Sprite2D.new()
	face.texture = _static_tex
	face.position = Vector2(0, -entity_size * 0.28)
	face.z_index = 1
	root.add_child(face)
	root.set_meta("face", face)

	# Animate static face — flicker through scale to simulate static
	var face_tw := create_tween().set_loops()
	face_tw.tween_property(face, "scale", Vector2(1.05, 1.02), 0.07)
	face_tw.tween_property(face, "scale", Vector2(0.97, 1.0),  0.07)
	face_tw.tween_property(face, "scale", Vector2(1.0, 0.98),  0.06)
	face_tw.tween_property(face, "scale", Vector2(1.0, 1.0),   0.05)

	# ── Eyes (variant-based) ──────────────────────────────────────────────────
	match variant:
		Variant.WATCHER:
			# Three eyes in a row — deeply wrong
			for i in range(3):
				_add_eye(root, Vector2((i - 1) * 9, -entity_size * 0.3), 0.7)
		Variant.CRAWLER:
			# Two asymmetric eyes — one huge, one tiny
			_add_eye(root, Vector2(-7, -entity_size * 0.28), 1.4)
			_add_eye(root, Vector2(8,  -entity_size * 0.35), 0.4)
		Variant.SCREAMER:
			# Wide open single eye dead center, no blinking
			_add_eye(root, Vector2(0, -entity_size * 0.3), 1.6, false)
		Variant.HOLLOW:
			# No eyes — just two dark sockets
			for ox in [-7, 6]:
				var socket := Sprite2D.new()
				var si := Image.create(8, 6, false, Image.FORMAT_RGBA8)
				for x in range(8):
					for y in range(6):
						si.set_pixel(x, y, Color(0, 0, 0, 0.85))
				socket.texture = ImageTexture.create_from_image(si)
				socket.position = Vector2(ox, -entity_size * 0.3)
				root.add_child(socket)

	# ── Mouth ─────────────────────────────────────────────────────────────────
	var mouth := Sprite2D.new()
	mouth.texture = _mouth_tex
	mouth.position = Vector2(0, -entity_size * 0.12)
	mouth.z_index = 1
	root.add_child(mouth)
	root.set_meta("mouth", mouth)

	# SCREAMER: mouth yawns open over time
	if variant == Variant.SCREAMER:
		var yawn_tw := create_tween().set_loops()
		yawn_tw.tween_property(mouth, "scale:y", 4.0, 3.5).set_ease(Tween.EASE_IN)
		yawn_tw.tween_property(mouth, "scale:y", 1.0, 0.3).set_ease(Tween.EASE_OUT)

	# ── Shadow beneath entity ──────────────────────────────────────────────────
	var shadow := Sprite2D.new()
	var sh_img := Image.create(entity_size, 6, false, Image.FORMAT_RGBA8)
	for x in range(entity_size):
		for y in range(6):
			var t : float = 1.0 - abs(x - entity_size/2.0) / (entity_size/2.0)
			sh_img.set_pixel(x, y, Color(0, 0, 0, t * 0.3))
	shadow.texture = ImageTexture.create_from_image(sh_img)
	shadow.position = Vector2(0, entity_size * 0.3)
	shadow.z_index = -1
	root.add_child(shadow)

	# ── Breathing ─────────────────────────────────────────────────────────────
	var spd := breathing_speed * randf_range(0.8, 1.2)
	var breath_tw := create_tween().set_loops()
	breath_tw.tween_property(body, "scale", Vector2(1.06, 0.94), spd * 0.5)
	breath_tw.tween_property(body, "scale", Vector2(1.0,  1.0),  spd * 0.5)

	# ── CRAWLER special: tilted, low to ground ────────────────────────────────
	if variant == Variant.CRAWLER:
		root.rotation = deg_to_rad(randf_range(-30, 30))
		body.scale = Vector2(1.3, 0.6)   # squashed horizontally

	# ── HOLLOW special: intermittent visibility pulse ─────────────────────────
	if variant == Variant.HOLLOW:
		var hollow_tw := create_tween().set_loops()
		hollow_tw.tween_property(root, "modulate:a", 0.15, randf_range(1.5, 3.0))
		hollow_tw.tween_property(root, "modulate:a", 0.9,  randf_range(0.5, 1.5))

	return root

func _add_eye(parent: Node2D, pos: Vector2, scale_factor: float, blinks: bool = true) -> void:
	var eye := Sprite2D.new()
	eye.texture = _eye_tex
	eye.position = pos
	eye.scale = Vector2(scale_factor, scale_factor)
	eye.z_index = 2
	parent.add_child(eye)

	if blinks:
		# Occasional slow blink
		var blink_tw := create_tween().set_loops()
		blink_tw.tween_interval(randf_range(2.0, 6.0))
		blink_tw.tween_property(eye, "scale:y", 0.0, 0.08)
		blink_tw.tween_property(eye, "scale:y", scale_factor, 0.12)

# ─────────────────────────────────────────────────────────────────────────────
#  SPAWN
# ─────────────────────────────────────────────────────────────────────────────
func spawn_entities() -> void:
	var valid := _get_all_valid_tiles()
	if valid.is_empty():
		await get_tree().create_timer(0.5).timeout
		spawn_entities()
		return

	var pt := tileMap.local_to_map(player.global_position)
	var candidates : Array[Vector2i] = []
	for tile in valid:
		var d := _get_tile_distance(tile, pt)
		if d >= min_distance_from_player and d <= max_distance_from_player:
			if not occupied_tiles.has(tile):
				candidates.append(tile)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var count := mini(spawn_count, candidates.size())

	const BATCH := 2   # only 2 per frame — each entity is heavier than a coin
	var idx := 0
	while idx < count:
		for _b in range(BATCH):
			if idx >= count: break
			_spawn_entity_at_tile(candidates[idx])
			idx += 1
		await get_tree().process_frame

	print("[ENTITY] Spawn complete — ", active_entities.size(), " entities active")

func _spawn_entity_at_tile(tile_pos: Vector2i) -> void:
	var world_pos := tileMap.map_to_local(tile_pos)

	var variant : Variant = randi() % 4 as Variant
	var entity : Node2D

	if enemy_scene:
		entity = enemy_scene.instantiate()
	else:
		entity = _create_entity(variant)

	entity.global_position = world_pos
	entity.modulate.a = 0.0
	entity.set_meta("variant", variant)
	entity.set_meta("tile", tile_pos)
	add_child(entity)

	entity_tiles[tile_pos]  = entity
	occupied_tiles[tile_pos] = true
	active_entities.append(entity)
	_stuck_counters[entity]  = 0

	# Staggered fade in — some flicker in like a broken signal
	if variant == Variant.SCREAMER or variant == Variant.HOLLOW:
		_glitch_fade_in(entity)
	else:
		var tw := create_tween()
		tw.tween_property(entity, "modulate:a", 1.0, spawn_fade_duration)

	entity_spawned.emit(tile_pos)

func _glitch_fade_in(entity: Node2D) -> void:
	"""Flickering static-like appearance for SCREAMER and HOLLOW variants."""
	var tw := create_tween()
	for _i in range(5):
		tw.tween_property(entity, "modulate:a", randf_range(0.2, 0.9), 0.07)
		tw.tween_property(entity, "modulate:a", 0.0, 0.05)
	tw.tween_property(entity, "modulate:a", 1.0, 0.3)

# ─────────────────────────────────────────────────────────────────────────────
#  CHASE AI
# ─────────────────────────────────────────────────────────────────────────────
func _step_all_entities() -> void:
	var pt := tileMap.local_to_map(player.global_position)

	for entity in active_entities:
		if not is_instance_valid(entity): continue

		var variant : Variant = entity.get_meta("variant", Variant.WATCHER)
		var cur_tile : Vector2i = entity.get_meta("tile", tileMap.local_to_map(entity.global_position))
		var dist := _get_tile_distance(cur_tile, pt)

		if dist <= chase_stop_distance:
			# Too close — emit signal, optional: push slightly sideways
			entity_nearby.emit(dist)
			continue

		var best_tile := cur_tile
		var best_dist := dist

		# SCREAMER takes 2 steps per tick — fast and aggressive
		var steps := 2 if variant == Variant.SCREAMER else 1
		# CRAWLER takes diagonal-only steps — erratic, unsettling path
		var dirs := HEX_DIRS

		var working_tile := cur_tile
		for _step in range(steps):
			var step_best := working_tile
			var step_best_dist := _get_tile_distance(working_tile, pt)

			for d in dirs:
				var candidate := working_tile + d
				if not _is_walkable(candidate): continue
				if occupied_tiles.has(candidate) and entity_tiles.get(candidate) != entity: continue
				var cd := _get_tile_distance(candidate, pt)
				if cd < step_best_dist:
					step_best_dist = cd
					step_best = candidate

			if step_best == working_tile:
				break  # stuck this step
			working_tile = step_best
			best_tile = working_tile
			best_dist = step_best_dist

		# HOLLOW: 20% chance to teleport to a random nearby tile instead of chasing
		if variant == Variant.HOLLOW and randf() < 0.20:
			var random_tiles : Array[Vector2i] = []
			for d in HEX_DIRS:
				var c := cur_tile + d + HEX_DIRS[randi() % HEX_DIRS.size()]
				if _is_walkable(c) and not occupied_tiles.has(c):
					random_tiles.append(c)
			if not random_tiles.is_empty():
				best_tile = random_tiles[randi() % random_tiles.size()]

		if best_tile == cur_tile:
			_stuck_counters[entity] = _stuck_counters.get(entity, 0) + 1
			if teleport_when_stuck and _stuck_counters[entity] >= stuck_threshold:
				_teleport_behind_player(entity, cur_tile, pt)
			continue

		_stuck_counters[entity] = 0

		# Update tracking
		entity_tiles.erase(cur_tile)
		occupied_tiles.erase(cur_tile)
		entity_tiles[best_tile] = entity
		occupied_tiles[best_tile] = true
		entity.set_meta("tile", best_tile)

		var target_pos := tileMap.map_to_local(best_tile)
		var move_time := chase_interval * 0.88

		# WATCHER glides smoothly; CRAWLER jerks
		var tw := create_tween()
		if variant == Variant.CRAWLER:
			tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
		else:
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(entity, "global_position", target_pos, move_time)

func _teleport_behind_player(entity: Node2D, cur_tile: Vector2i, player_tile: Vector2i) -> void:
	"""Last resort: teleport entity to a tile just behind the player (relative to movement)."""
	_stuck_counters[entity] = 0

	# Pick a tile 1–3 steps away from player, preferring tiles the player can't see easily
	var candidates : Array[Vector2i] = []
	for d in HEX_DIRS:
		for radius in [2, 3]:
			var t : Vector2i= player_tile + d * radius
			if _is_walkable(t) and not occupied_tiles.has(t):
				candidates.append(t)

	if candidates.is_empty(): return

	candidates.shuffle()
	var dest := candidates[0]

	# Flicker out, move, flicker in
	var tw := create_tween()
	tw.tween_property(entity, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		entity_tiles.erase(cur_tile)
		occupied_tiles.erase(cur_tile)
		entity.global_position = tileMap.map_to_local(dest)
		entity_tiles[dest] = entity
		occupied_tiles[dest] = true
		entity.set_meta("tile", dest)
	)
	tw.tween_property(entity, "modulate:a", 1.0, 0.3)

# ─────────────────────────────────────────────────────────────────────────────
#  PER-ENTITY BEHAVIOUR UPDATES (stare, lean toward player, etc.)
# ─────────────────────────────────────────────────────────────────────────────
func _update_entity_behaviors(delta: float) -> void:
	for entity in active_entities:
		if not is_instance_valid(entity): continue

		var variant : Variant = entity.get_meta("variant", Variant.WATCHER)
		var to_player := player.global_position - entity.global_position
		var angle := to_player.angle()

		# WATCHER: tilts body to face player (head turn)
		if variant == Variant.WATCHER:
			if entity.has_node("Body"):
				var body : Sprite2D = entity.get_node("Body")
				body.rotation = lerp_angle(body.rotation, angle * 0.15, delta * 2.5)

		# SCREAMER: stretches vertically as it closes in, then snaps
		if variant == Variant.SCREAMER:
			var pt := tileMap.local_to_map(player.global_position)
			var et : Vector2i= entity.get_meta("tile", tileMap.local_to_map(entity.global_position))
			var dist := float(_get_tile_distance(et, pt))
			var stretch : float= 1.0 + clamp((8.0 - dist) / 8.0, 0.0, 1.0) * 0.6
			entity.scale.y = lerp(entity.scale.y, stretch, delta * 3.0)

		# CRAWLER: skitters side to side slightly around its position
		if variant == Variant.CRAWLER:
			var skitter := sin(Time.get_ticks_msec() * 0.012 + entity.get_instance_id()) * 3.0
			entity.position.x += skitter * delta

		# All: rotate face sprite to always face player (eye tracking)
		if entity.has_node("Body"):
			var face_node := entity.get_node_or_null("Body")
			if face_node:
				# subtle lean — 10% of actual angle
				pass

# ─────────────────────────────────────────────────────────────────────────────
#  PROXIMITY + COLLISION
# ─────────────────────────────────────────────────────────────────────────────
func _check_proximity() -> void:
	var pt := tileMap.local_to_map(player.global_position)
	for entity in active_entities:
		if not is_instance_valid(entity): continue
		var et : Vector2i = entity.get_meta("tile", tileMap.local_to_map(entity.global_position))
		var dist := _get_tile_distance(et, pt)
		if dist <= 4:
			entity_nearby.emit(dist)

func check_player_collision(player_tile_pos: Vector2i) -> bool:
	if entity_tiles.has(player_tile_pos):
		entity_touched_player.emit()
		return true
	return false

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN DISTORTION
#  Connect distortion_label (RichTextLabel) and vhs_noise_label (Label)
#  to make the screen glitch based on proximity
# ─────────────────────────────────────────────────────────────────────────────
func _update_screen_distortion(delta: float) -> void:
	if not distortion_label and not vhs_noise_label:
		return

	# Find nearest entity
	var pt := tileMap.local_to_map(player.global_position)
	var min_dist := 999
	for entity in active_entities:
		if not is_instance_valid(entity): continue
		var et : Vector2i = entity.get_meta("tile", tileMap.local_to_map(entity.global_position))
		min_dist = mini(min_dist, _get_tile_distance(et, pt))

	# Intensity: 0 at distance 10+, 1.0 at distance 1
	var intensity : float = clamp(1.0 - (min_dist - 1) / 9.0, 0.0, 1.0)
	intensity = pow(intensity, 2.0)  # quadratic — only scary when VERY close

	# ── VHS scan line overlay ──────────────────────────────────────────────────
	if vhs_noise_label and intensity > 0.05:
		vhs_noise_label.visible = true
		vhs_noise_label.modulate.a = intensity * 0.35
		# Scroll scan line position
		var line_y := int(_distort_timer * 80.0) % 600
		vhs_noise_label.position.y = float(line_y)
	elif vhs_noise_label:
		vhs_noise_label.visible = false

	# ── BBCode text glitch on the RichTextLabel ────────────────────────────────
	if distortion_label and intensity > 0.15:
		distortion_label.visible = true
		distortion_label.modulate.a = intensity * 0.7

		# Random glitch every 0.2–0.8s
		if _glitch_timer > randf_range(0.2, 0.8):
			_glitch_timer = 0.0
			var chars := "▓▒░█▄▀■□▪▫◘◙"
			var line := ""
			var len := int(intensity * 18)
			for _i in range(len):
				line += chars[randi() % chars.length()]
			distortion_label.text = "[color=#ff2200]" + line + "[/color]"
			distortion_label.position = Vector2(
				randf_range(0, 200),
				randf_range(0, 400)
			)
	elif distortion_label:
		distortion_label.visible = false

# ─────────────────────────────────────────────────────────────────────────────
#  CHUNK SPAWNING
# ─────────────────────────────────────────────────────────────────────────────
func _on_chunk_generated(chunk_coord: Vector2i) -> void:
	if not respawn_on_new_chunks: return

	var chunk_tiles := _get_tiles_in_chunk(chunk_coord)
	var pt := tileMap.local_to_map(player.global_position)
	var spawn_tiles : Array[Vector2i] = []

	for tile in chunk_tiles:
		var d := _get_tile_distance(tile, pt)
		if d >= min_distance_from_player and d <= max_distance_from_player:
			if not occupied_tiles.has(tile):
				spawn_tiles.append(tile)

	if spawn_tiles.is_empty(): return
	spawn_tiles.shuffle()

	var count := randi_range(1, 2)
	for i in range(mini(count, spawn_tiles.size())):
		_spawn_entity_at_tile(spawn_tiles[i])

# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────────────────────
func is_tile_occupied(tile_pos: Vector2i) -> bool:
	return occupied_tiles.has(tile_pos)

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
	if not map_generator: return []
	var cs : int = map_generator.chunk_size if map_generator.has("chunk_size") else 10
	var start := chunk_coord * cs
	var out : Array[Vector2i] = []
	for x in range(cs):
		for y in range(cs):
			var tp := start + Vector2i(x, y)
			if _is_walkable(tp):
				out.append(tp)
	return out
