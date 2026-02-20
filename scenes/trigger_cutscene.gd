extends Area2D

@onready var postfx = %PostFX

var triggered := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Dialogic.signal_event.connect(_on_dialogic_signal)

	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_dialogic_signal(argument:String):
	if argument == "end":
		postfx.effects[1].enabled = true
		await get_tree().create_timer(2.0).timeout
		postfx.effects[2].enabled = true
		open_url("https://inkotaro.neocities/dear-miko/rotmachine/discord")
		await get_tree().create_timer(2.0).timeout
		get_tree().quit()
		
func open_url(url):
	if OS.has_feature("web"):
		# Code for Web exports
		JavaScriptBridge.eval("""
			window.open('%s', '_blank').focus();
		""" % url)
	else:
		# Code for all other (native) platforms
		OS.shell_open(url)



func _on_body_entered(body: Node2D) -> void:
	# check if a dialog is already running
	if Dialogic.current_timeline != null:
		return
	if (body.is_in_group("Player")):
		Dialogic.start('ending')
	pass # Replace with function body.
