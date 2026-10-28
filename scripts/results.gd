extends CanvasLayer
## End-of-run summary. Reads GameState.last_result, which main_game fills in
## with the run's stats and new-best flags before changing to this scene.

const COUNT_TIME := 0.8
const GOLD := Color(1.0, 0.85, 0.35)

@onready var title: Label = $LayoutRoot/Title
@onready var mode_line: Label = $LayoutRoot/ModeLine
@onready var rows_box: VBoxContainer = $LayoutRoot/Rows
@onready var play_button: Button = $LayoutRoot/Buttons/PlayAgain
@onready var menu_button: Button = $LayoutRoot/Buttons/MainMenu
@onready var hint_label: Label = $LayoutRoot/Hint

var _result: Dictionary = {}
var _labels: Dictionary = {}
var _best_text := ""
var _best_is_new := false
var _animating := true
var _anim_time := 0.0


func _ready() -> void:
	# The results screen is always a clean, live scene: no pause, no hitstop.
	Engine.time_scale = 1.0
	Fx.reset_hitstop()
	get_tree().paused = false
	_result = GameState.last_result.duplicate(true)
	if _result.is_empty():
		_result = _fallback_result()
	_build_rows()
	title.text = _title_text()
	mode_line.text = GameState.results_mode_line()
	_best_text = _best_row_text()
	_best_is_new = _run_set_a_best()
	play_button.pressed.connect(_on_play_again_pressed)
	menu_button.pressed.connect(_on_main_menu_pressed)
	play_button.call_deferred("grab_focus")
	Fx.play("win" if String(_result.get("outcome", "lose")) == "win" else "player_ko")
	_render(0.0)


func _fallback_result() -> Dictionary:
	return {
		"mode": int(GameState.mode),
		"stage": int(GameState.stage),
		"total_rounds": int(GameState.total_rounds),
		"outcome": "lose",
		"kills": 0,
		"seconds": 0.0,
		"max_combo": 0,
		"rounds_cleared": 0,
		"round_reached": 1,
		"player_health_left": 0,
		"new_best": {},
	}


# --- layout ------------------------------------------------------------

func _build_rows() -> void:
	var names := [
		["kills", "Kills"],
		["time", "Time"],
		["max_combo", "Max combo"],
		["rounds_cleared", "Rounds cleared"],
		["best", "Best"],
	]
	for pair in names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = String(pair[1])
		name_label.custom_minimum_size = Vector2(120, 15)
		name_label.add_theme_font_size_override("font_size", 11)
		var value_label := Label.new()
		value_label.text = ""
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 11)
		row.add_child(name_label)
		row.add_child(value_label)
		rows_box.add_child(row)
		_labels[String(pair[0])] = {"row": row, "value": value_label}
	# "Rounds cleared" only means something for Rounds / Hardcore.
	var show_rounds := int(_result.get("mode", GameState.Mode.SURVIVAL)) != GameState.Mode.SURVIVAL
	if not show_rounds:
		var rounds_row: Control = _labels["rounds_cleared"]["row"]
		rounds_row.queue_free()
		_labels.erase("rounds_cleared")


func _set_row(key: String, text: String, gold := false) -> void:
	if not _labels.has(key):
		return
	var value: Label = _labels[key]["value"]
	value.text = text
	var color := GOLD if gold else Color(1, 1, 1, 1)
	value.add_theme_color_override("font_color", color)


func _title_text() -> String:
	match String(_result.get("outcome", "lose")):
		"win":
			return "VICTORY"
	if int(_result.get("mode", GameState.Mode.SURVIVAL)) == GameState.Mode.SURVIVAL:
		return "GAME OVER"
	return "DEFEAT"


func _run_set_a_best() -> bool:
	var flags: Dictionary = _result.get("new_best", {})
	for key in flags:
		if bool(flags[key]):
			return true
	return false


func _best_row_text() -> String:
	var flags: Dictionary = _result.get("new_best", {})
	match int(_result.get("mode", GameState.Mode.SURVIVAL)):
		GameState.Mode.SURVIVAL:
			var best := GameState.get_best_survival()
			if bool(flags.get("survival", false)):
				return "NEW BEST!  %d kills  %s" % [
					int(_result.get("kills", 0)), _format_time(float(_result.get("seconds", 0.0)))]
			if int(best["kills"]) <= 0 and float(best["seconds"]) <= 0.0:
				return "Best:  --"
			return "Best:  %d kills  %s" % [int(best["kills"]), _format_time(float(best["seconds"]))]
		GameState.Mode.ROUNDS:
			var best := GameState.get_best_rounds(int(_result.get("total_rounds", 0)))
			if bool(flags.get("rounds", false)):
				return "NEW BEST!  %s" % _format_time(float(_result.get("seconds", 0.0)))
			if not bool(best["set"]):
				return "Best:  --"
			return "Best:  %s" % _format_time(float(best["seconds"]))
		_:
			var best := GameState.get_best_hardcore()
			var body := ""
			if bool(best["clear"]):
				body = _format_time(float(best["seconds"]))
			if int(best["round_reached"]) > 0:
				var rounds := "round %d" % int(best["round_reached"])
				body = rounds if body == "" else "%s  %s" % [body, rounds]
			if body == "":
				body = "--"
			var is_new := bool(flags.get("hardcore_clear", false)) \
				or bool(flags.get("hardcore_round", false))
			return ("NEW BEST!  " if is_new else "Best:  ") + body


func _format_time(seconds: float) -> String:
	var total := maxi(roundi(seconds), 0)
	return "%d:%02d" % [total / 60, total % 60]


# --- count-up ----------------------------------------------------------

func _process(delta: float) -> void:
	if not _animating:
		return
	_anim_time = minf(_anim_time + delta, COUNT_TIME)
	_render(_anim_time / COUNT_TIME)
	if _anim_time >= COUNT_TIME:
		_finish_animation()


func _render(fraction: float) -> void:
	var kills := roundi(float(_result.get("kills", 0)) * fraction)
	_set_row("kills", str(kills))
	_set_row("time", _format_time(float(_result.get("seconds", 0.0)) * fraction))
	_set_row("max_combo", "x%d" % roundi(float(_result.get("max_combo", 0)) * fraction))
	if _labels.has("rounds_cleared"):
		_set_row("rounds_cleared", "%d / %d" % [
			roundi(float(_result.get("rounds_cleared", 0)) * fraction),
			int(_result.get("total_rounds", 0))])
	_set_row("best", _best_text, _best_is_new)


func _finish_animation() -> void:
	_animating = false
	_anim_time = COUNT_TIME
	_render(1.0)


func _input(event: InputEvent) -> void:
	if _animating and _is_press(event):
		_finish_animation()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_main_menu_pressed()


func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	return false


# --- buttons -----------------------------------------------------------

func _on_play_again_pressed() -> void:
	GameState.restart_last_run()


func _on_main_menu_pressed() -> void:
	GameState.goto_scene(GameState.MENU_SCENE)
