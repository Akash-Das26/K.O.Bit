extends AudioStreamPlayer
## Persistent background music shared by the menu and game scenes.

var _music_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = "Music"
	_music_stream = load("res://assets/audio/music/Of Far Different Nature - Oldskool (CC0).wav") as AudioStreamWAV
	stream = _music_stream
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	finished.connect(_on_music_finished)
	get_tree().scene_changed.connect(_keep_playing)
	if DisplayServer.get_name() != "headless" and not playing:
		play()


func _exit_tree() -> void:
	stop()
	stream = null
	_music_stream = null
	bus = "Master"


func _on_music_finished() -> void:
	play()


func _keep_playing() -> void:
	if DisplayServer.get_name() != "headless" and not playing:
		play()