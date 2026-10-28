extends Control

@onready var best_label: Label = $BestLabel
@onready var stage_button: Button = $CenterContainer/VBoxContainer/StageButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/Survival
@onready var settings_button: Button = $CenterContainer/VBoxContainer/ButtonRow/Settings


func _ready() -> void:
	_refresh_stage()
	var best: Dictionary = GameState.get_best_survival()
	if int(best["kills"]) > 0 or float(best["seconds"]) > 0.0:
		best_label.text = "Best survival: %d kills  %s" % [
			int(best["kills"]), _format_time(float(best["seconds"]))]
	else:
		best_label.visible = false
	# Keyboard and gamepad both need somewhere to start from.
	if GameState.menu_focus_hint == "settings":
		GameState.menu_focus_hint = ""
		settings_button.grab_focus()
	else:
		GameState.menu_focus_hint = ""
		start_button.grab_focus()


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _refresh_stage() -> void:
	stage_button.text = "Stage: %s" % GameState.stage_name()


func _on_stage_pressed() -> void:
	GameState.toggle_stage()
	_refresh_stage()


func _on_survival_pressed() -> void:
	GameState.start_survival()


func _on_round_pressed(rounds: int) -> void:
	GameState.start_rounds(rounds)


func _on_hardcore_pressed() -> void:
	GameState.start_hardcore()


func _on_settings_pressed() -> void:
	GameState.goto_scene(GameState.SETTINGS_SCENE)


func _on_exit_pressed() -> void:
	get_tree().quit()
