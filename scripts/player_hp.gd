extends Node
## Player HP Management System
## Tracks player health and handles damage

@export var max_hp := 5  # Maximum health points
@export var starting_hp := 5  # HP at game start
@export var invulnerability_time := 1.0  # Seconds of invulnerability after taking damage
@export var game_hud: CanvasLayer
@export var hurt_sound: AudioStreamPlayer2D

var current_hp := 5
var is_invulnerable := false
var invulnerability_timer := 0.0

signal hp_changed(new_hp: int, max_hp: int)
signal damage_taken(damage: int, remaining_hp: int)
signal player_died()
signal healed(amount: int, new_hp: int)

func _ready() -> void:
	current_hp = starting_hp
	print("Player HP initialized: ", current_hp, "/", max_hp)

func _process(delta: float) -> void:
	# Handle invulnerability timer
	if is_invulnerable:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0:
			is_invulnerable = false
			print("Invulnerability ended")

func take_damage(amount: int) -> void:
	"""Reduces player HP by the given amount"""
	if is_invulnerable:
		print("Player is invulnerable - damage ignored")
		return
	
	if current_hp <= 0:
		return  # Already dead
	
	current_hp = maxi(0, current_hp - amount)
	
	# Start invulnerability
	is_invulnerable = true
	invulnerability_timer = invulnerability_time
	
	hurt_sound.playing = true
	hurt_sound.pitch_scale = randf_range(.5,2)
	
	print("Player took ", amount, " damage! HP: ", current_hp, "/", max_hp)
	
	# Emit signals
	damage_taken.emit(amount, current_hp)
	hp_changed.emit(current_hp, max_hp)
	
	# Check for death
	if current_hp <= 0:
		_on_player_death()

func heal(amount: int) -> void:
	"""Restores player HP by the given amount"""
	if current_hp >= max_hp:
		print("Already at max HP")
		return
	
	var old_hp = current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var actual_heal = current_hp - old_hp
	
	print("Player healed ", actual_heal, " HP! HP: ", current_hp, "/", max_hp)
	
	# Emit signals
	healed.emit(actual_heal, current_hp)
	hp_changed.emit(current_hp, max_hp)

func set_hp(new_hp: int) -> void:
	"""Directly sets player HP"""
	current_hp = clampi(new_hp, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0:
		_on_player_death()

func get_current_hp() -> int:
	"""Returns current HP"""
	return current_hp

func get_max_hp() -> int:
	"""Returns maximum HP"""
	return max_hp

func is_alive() -> bool:
	"""Returns true if player has HP remaining"""
	return current_hp > 0

func is_at_max_hp() -> bool:
	"""Returns true if at maximum HP"""
	return current_hp >= max_hp

func get_hp_percentage() -> float:
	"""Returns HP as percentage (0.0 to 1.0)"""
	return float(current_hp) / float(max_hp)

func _on_player_death() -> void:
	"""Called when player HP reaches 0"""
	print("PLAYER DIED!")
	player_died.emit()

func reset() -> void:
	"""Resets HP to starting value"""
	current_hp = starting_hp
	is_invulnerable = false
	invulnerability_timer = 0.0
	hp_changed.emit(current_hp, max_hp)
	print("Player HP reset to: ", current_hp, "/", max_hp)
