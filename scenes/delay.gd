extends Node

func _ready():
	# Call the function to start the delayed scene change when the current scene is ready
	change_scene_after_delay(3.0) # Delay for 3 seconds

func change_scene_after_delay(seconds: float):
	# Wait for the specified number of seconds using a SceneTreeTimer
	await get_tree().create_timer(seconds).timeout
	
	# After the delay, change the scene
	change_scene_to_next()

func change_scene_to_next():
	# Use change_scene_to_file for Godot 4.0+
	var error = get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		print("Failed to change scene: ", error)
