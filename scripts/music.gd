extends AudioStreamPlayer
## Persistent background music shared by the menu and game scenes.

const MUSIC_PATH := "res://assets/audio/music/Of Far Different Nature - Oldskool (CC0).wav"
const DEBUG_AUDIO := false

var _music_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = "Music"
	_music_stream = load(MUSIC_PATH) as AudioStreamWAV
	if _music_stream != null:
		_configure_loop(_music_stream)
	stream = _music_stream
	finished.connect(_on_music_finished)
	get_tree().scene_changed.connect(_keep_playing)
	if DisplayServer.get_name() != "headless" and not playing:
		play()
	if DEBUG_AUDIO and DisplayServer.get_name() != "headless":
		print("Music: %s length=%.2fs bus=%s playing=%s" % [
			MUSIC_PATH, get_stream_length(), String(bus), str(playing)])


## Safety net only: the WAV import settings already loop the whole sample
## forward (edit/loop_mode = Forward, edit/loop_end = end of sample), so a
## normal import is left untouched.
##
## AudioStreamWAV.loop_end == 0 is NOT "loop to the end": it is a zero-length
## loop, and the player then reports playing == true while outputting silence
## forever. Repair that (and a disabled loop) so music can never go missing.
func _configure_loop(wav: AudioStreamWAV) -> void:
	if wav.loop_end > 0:
		return
	var old_end := wav.loop_end
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	push_warning("Music: stream had no loop end (was %d); repaired to %d frames" % [
		old_end, frames])


func get_stream_length() -> float:
	if _music_stream == null:
		return 0.0
	return _music_stream.get_length()


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
