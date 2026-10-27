extends Node
## Game mode / stage / best-score state, autoloaded as "GameState".

enum Mode { SURVIVAL, ROUNDS, HARDCORE }
enum Stage { STREET, DESERT }

const GAME_SCENE := "res://scenes/main_game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
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

var mode: Mode = Mode.SURVIVAL
var total_rounds := 0
var stage: Stage = Stage.STREET
var lane_min_y := LANE_MIN_Y_STREET
var lane_max_y := LANE_MAX_Y_STREET


func _ready() -> void:
	select_stage(stage)


func get_best_survival() -> Dictionary:
	var cfg := ConfigFile.new()
	var best := {"kills": 0, "seconds": 0.0}
	if cfg.load(SCORES_PATH) == OK:
		best["kills"] = int(cfg.get_value("survival", "kills", 0))
		best["seconds"] = float(cfg.get_value("survival", "seconds", 0.0))
	return best


func save_survival(kills: int, seconds: float) -> bool:
	var best := get_best_survival()
	var better := kills > int(best["kills"]) \
		or (kills == int(best["kills"]) and seconds > float(best["seconds"]))
	if not better:
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("survival", "kills", kills)
	cfg.set_value("survival", "seconds", seconds)
	return cfg.save(SCORES_PATH) == OK


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
	return "Street" if stage == Stage.STREET else "Desert"


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
