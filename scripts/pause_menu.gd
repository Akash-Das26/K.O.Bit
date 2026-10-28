class_name PauseMenu
extends CanvasLayer

## ESC / Start pause overlay. Lives inside main_game, processes while the
## tree is paused, and refuses to open while a round-end/game-over banner
## shows. B (ui_cancel) resumes, like the Escape key.

const SETTINGS_SCENE := preload("res://scenes/settings_screen.tscn")

## Set by main_game while the end sequence is running, and while the settings
## overlay is open.
var blocked := false

@onready var layout_root: Control = $LayoutRoot
@onready var resume_button: Button = $LayoutRoot/CenterContainer/VBoxContainer/Resume

var _settings_screen: CanvasLayer = null


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
		resume_button.grab_focus()
	else:
		resume_button.release_focus()


func _on_resume_pressed() -> void:
	Fx.reset_hitstop()
	get_tree().paused = false
	visible = false
	resume_button.release_focus()


func _on_settings_pressed() -> void:
	if _settings_screen != null:
		return
	var screen = SETTINGS_SCENE.instantiate()
	screen.overlay = true
	# The screen handles its own input; keep the pause menu from reacting.
	blocked = true
	layout_root.visible = false
	_settings_screen = screen
	add_child(screen)
	screen.closed.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	_settings_screen = null
	blocked = false
	layout_root.visible = true
	resume_button.grab_focus()


func _on_restart_pressed() -> void:
	GameState.goto_scene(GameState.GAME_SCENE)


func _on_main_menu_pressed() -> void:
	GameState.goto_scene(GameState.MENU_SCENE)


func _on_quit_pressed() -> void:
	Fx.reset_hitstop()
	get_tree().paused = false
	get_tree().quit()
