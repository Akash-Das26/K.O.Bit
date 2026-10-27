extends Control

@onready var best_label: Label = $BestLabel
@onready var stage_button: Button = $CenterContainer/VBoxContainer/StageButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/Survival
@onready var volume_slider: HSlider = $VolumeRow/VolumeSlider
@onready var volume_label: Label = $VolumeRow/VolumeLabel
@onready var music_slider: HSlider = $MusicRow/MusicSlider
@onready var music_label: Label = $MusicRow/MusicLabel


func _ready() -> void:
	_refresh_stage()
	var best: Dictionary = GameState.get_best_survival()
	if int(best["kills"]) > 0 or float(best["seconds"]) > 0.0:
		best_label.text = "Best survival: %d kills  %s" % [
			int(best["kills"]), _format_time(float(best["seconds"]))]
	else:
		best_label.visible = false
	# Keyboard and gamepad both need somewhere to start from.
	_sync_audio()
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_changed)
	start_button.grab_focus()


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _refresh_stage() -> void:
	stage_button.text = "Stage: %s" % GameState.stage_name()


func _sync_audio() -> void:
	volume_slider.value = Settings.master_volume
	music_slider.value = Settings.music_volume
	_update_audio_labels()


func _update_audio_labels() -> void:
	volume_label.text = "Volume %d%%" % roundi(float(volume_slider.value) * 100.0)
	music_label.text = "Music %d%%" % roundi(float(music_slider.value) * 100.0)


func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
	_update_audio_labels()


func _on_music_changed(value: float) -> void:
	Settings.set_music_volume(value)
	_update_audio_labels()


func _on_stage_pressed() -> void:
	GameState.toggle_stage()
	_refresh_stage()


func _on_survival_pressed() -> void:
	GameState.start_survival()


func _on_round_pressed(rounds: int) -> void:
	GameState.start_rounds(rounds)


func _on_hardcore_pressed() -> void:
	GameState.start_hardcore()


func _on_exit_pressed() -> void:
	get_tree().quit()
