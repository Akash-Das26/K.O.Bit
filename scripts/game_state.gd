extends Node
## Game mode / stage / best-score state, autoloaded as "GameState".

enum Mode { SURVIVAL, ROUNDS, HARDCORE }
enum Stage { STREET, DESERT }

const GAME_SCENE := "res://scenes/main_game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const RESULTS_SCENE := "res://scenes/results.tscn"
const SETTINGS_SCENE := "res://scenes/settings_screen.tscn"
const SCORES_PATH := "user://scores.cfg"

# 600x240 viewport, 1200x480 window (exact 2x).
const VIEW_W := 600
const VIEW_H := 240
const WORLD_W := 1200

## The street band is 138 (the sidewalk) so the hydrant is reachable; the
## stage script applies the same value on load - see scripts/stage_street.gd.
const LANE_MIN_Y_STREET := 138.0
const LANE_MAX_Y_STREET := 232.0
const LANE_MIN_Y_DESERT := 168.0
const LANE_MAX_Y_DESERT := 236.0

## Rounds-mode best times are stored once per round count.
const ROUNDS_COUNTS := [3, 5, 7, 10]

var mode: Mode = Mode.SURVIVAL
var total_rounds := 0
var stage: Stage = Stage.STREET
var lane_min_y := LANE_MIN_Y_STREET
var lane_max_y := LANE_MAX_Y_STREET

## Filled by main_game when a run ends, read by the results screen.
var last_result: Dictionary = {}
## Set by the settings screen so the menu can restore focus on its button.
var menu_focus_hint := ""


func _ready() -> void:
	select_stage(stage)


# --- scores ------------------------------------------------------------

func _read_scores() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SCORES_PATH)
	return cfg


func _write_scores(cfg: ConfigFile) -> bool:
	return cfg.save(SCORES_PATH) == OK


func get_best_survival() -> Dictionary:
	var cfg := _read_scores()
	var best := {"kills": 0, "seconds": 0.0}
	best["kills"] = int(cfg.get_value("survival", "kills", 0))
	best["seconds"] = float(cfg.get_value("survival", "seconds", 0.0))
	return best


## SURVIVAL: best by kills, seconds as the tie-break (more time is better).
func save_survival(kills: int, seconds: float) -> bool:
	var best := get_best_survival()
	var better := kills > int(best["kills"]) \
		or (kills == int(best["kills"]) and seconds > float(best["seconds"]))
	if not better:
		return false
	var cfg := _read_scores()
	cfg.set_value("survival", "kills", kills)
	cfg.set_value("survival", "seconds", seconds)
	return _write_scores(cfg)


## ROUNDS: fastest clear time, stored per round count ([rounds_3] ... [rounds_10]).
func rounds_section(rounds: int) -> String:
	return "rounds_%d" % rounds


func get_best_rounds(rounds: int) -> Dictionary:
	var cfg := _read_scores()
	var section := rounds_section(rounds)
	var best := {"set": false, "seconds": 0.0}
	if cfg.has_section(section) and cfg.has_section_key(section, "seconds"):
		best["set"] = true
		best["seconds"] = float(cfg.get_value(section, "seconds", 0.0))
	return best


func save_rounds(rounds: int, seconds: float) -> bool:
	var best := get_best_rounds(rounds)
	if bool(best["set"]) and float(best["seconds"]) <= seconds:
		return false
	var cfg := _read_scores()
	var section := rounds_section(rounds)
	cfg.set_value(section, "seconds", seconds)
	return _write_scores(cfg)


## HARDCORE: fastest clear plus the highest round reached on a loss.
func get_best_hardcore() -> Dictionary:
	var cfg := _read_scores()
	var best := {"clear": false, "seconds": 0.0, "round_reached": 0}
	if cfg.has_section("hardcore"):
		if cfg.has_section_key("hardcore", "seconds"):
			best["clear"] = true
			best["seconds"] = float(cfg.get_value("hardcore", "seconds", 0.0))
		best["round_reached"] = int(cfg.get_value("hardcore", "round_reached", 0))
	return best


func save_hardcore_clear(seconds: float) -> bool:
	var best := get_best_hardcore()
	if bool(best["clear"]) and float(best["seconds"]) <= seconds:
		return false
	var cfg := _read_scores()
	cfg.set_value("hardcore", "seconds", seconds)
	return _write_scores(cfg)


func save_hardcore_round(reached: int) -> bool:
	if reached <= int(get_best_hardcore()["round_reached"]):
		return false
	var cfg := _read_scores()
	cfg.set_value("hardcore", "round_reached", reached)
	return _write_scores(cfg)


## Stores the run's new-best flags into result["new_best"] and remembers the
## result for the results screen. Never overwrites a better stored score.
func submit_result(result: Dictionary) -> Dictionary:
	var flags := {
		"survival": false,
		"rounds": false,
		"hardcore_clear": false,
		"hardcore_round": false,
	}
	var run_mode := int(result.get("mode", Mode.SURVIVAL))
	var outcome := String(result.get("outcome", "lose"))
	if run_mode == Mode.SURVIVAL:
		flags["survival"] = save_survival(
			int(result.get("kills", 0)), float(result.get("seconds", 0.0)))
	elif run_mode == Mode.ROUNDS:
		if outcome == "win":
			flags["rounds"] = save_rounds(
				int(result.get("total_rounds", 0)), float(result.get("seconds", 0.0)))
	else:
		if outcome == "win":
			flags["hardcore_clear"] = save_hardcore_clear(float(result.get("seconds", 0.0)))
		flags["hardcore_round"] = save_hardcore_round(int(result.get("round_reached", 0)))
	result["new_best"] = flags
	last_result = result
	return flags


# --- results helpers ---------------------------------------------------

func mode_name(value: int) -> String:
	match value:
		Mode.ROUNDS:
			return "Rounds %d" % total_rounds
		Mode.HARDCORE:
			return "Hardcore"
	return "Survival"


func results_mode_line() -> String:
	var run_mode := int(last_result.get("mode", mode))
	var run_stage := int(last_result.get("stage", stage))
	if run_mode == Mode.ROUNDS:
		return "Rounds %d - %s" % [
			int(last_result.get("total_rounds", total_rounds)), _stage_name(run_stage)]
	return "%s - %s" % [
		mode_name(run_mode) if run_mode != Mode.SURVIVAL else "Survival",
		_stage_name(run_stage)]


func _stage_name(value: int) -> String:
	return "Street" if value == Stage.STREET else "Desert"


## Restarts the run described by last_result (same mode, stage, round count).
func restart_last_run() -> void:
	var new_stage := int(last_result.get("stage", int(stage)))
	select_stage(Stage.DESERT if new_stage == int(Stage.DESERT) else Stage.STREET)
	var new_mode := int(last_result.get("mode", int(mode)))
	if new_mode == int(Mode.ROUNDS):
		mode = Mode.ROUNDS
	elif new_mode == int(Mode.HARDCORE):
		mode = Mode.HARDCORE
	else:
		mode = Mode.SURVIVAL
	total_rounds = int(last_result.get("total_rounds", total_rounds))
	goto_scene(GAME_SCENE)


# --- mode / stage ------------------------------------------------------

func select_stage(new_stage: Stage) -> void:
	stage = new_stage
	if stage == Stage.STREET:
		lane_min_y = LANE_MIN_Y_STREET
		lane_max_y = LANE_MAX_Y_STREET
	else:
		lane_min_y = LANE_MIN_Y_DESERT
		lane_max_y = LANE_MAX_Y_DESERT


## Used by a stage script that needs its own band (the street sidewalk).
func apply_lane(min_y: float, max_y: float) -> void:
	lane_min_y = min_y
	lane_max_y = max_y


func toggle_stage() -> void:
	select_stage(Stage.DESERT if stage == Stage.STREET else Stage.STREET)


func stage_name() -> String:
	return _stage_name(int(stage))


func start_survival() -> void:
	mode = Mode.SURVIVAL
	total_rounds = 0
	select_stage(stage)
	goto_scene(GAME_SCENE)


func start_rounds(n: int) -> void:
	mode = Mode.ROUNDS
	total_rounds = n
	select_stage(stage)
	goto_scene(GAME_SCENE)


func start_hardcore() -> void:
	mode = Mode.HARDCORE
	total_rounds = 5
	select_stage(stage)
	goto_scene(GAME_SCENE)


## Always leaves the runtime in a clean state (no leftover hitstop/pause).
func goto_scene(path: String) -> void:
	Fx.reset_hitstop()
	var tree := get_tree()
	tree.paused = false
	tree.change_scene_to_file(path)
