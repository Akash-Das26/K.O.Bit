class_name PauseMenu
extends CanvasLayer

## ESC / Start pause overlay. Lives inside main_game, processes while the
## tree is paused, and refuses to open while a round-end/game-over banner
## shows. B (ui_cancel) resumes, like the Escape key.

## Set by main_game while the end sequence is running.
var blocked := false

@onready var resume_button: Button = $LayoutRoot/CenterContainer/VBoxContainer/Resume
@onready var volume_slider: HSlider = $LayoutRoot/CenterContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_label: Label = $LayoutRoot/CenterContainer/VBoxContainer/VolumeRow/VolumeLabel
@onready var music_slider: HSlider = $LayoutRoot/CenterContainer/VBoxContainer/MusicRow/MusicSlider
@onready var music_label: Label = $LayoutRoot/CenterContainer/VBoxContainer/MusicRow/MusicLabel


func _ready() -> void:
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_changed)
	_sync_audio()


func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event.is_action_pressed("pause"):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	# B on a gamepad is ui_cancel; while paused it closes the menu again.
	if visible and event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	var tree := get_tree()
	var pause_now := not tree.paused
	Fx.reset_hitstop()
	tree.paused = pause_now
	visible = pause_now
	if pause_now:
		_sync_audio()
		resume_button.grab_focus()
	else:
		resume_button.release_focus()


func _on_resume_pressed() -> void:
	Fx.reset_hitstop()
	get_tree().paused = false
	visible = false
	resume_button.release_focus()


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


func _on_restart_pressed() -> void:
	GameState.goto_scene(GameState.GAME_SCENE)


func _on_main_menu_pressed() -> void:
	GameState.goto_scene(GameState.MENU_SCENE)


func _on_quit_pressed() -> void:
	Fx.reset_hitstop()
	get_tree().paused = false
	get_tree().quit()
