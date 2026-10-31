extends Node
## Audio volumes and rebindable controls, autoloaded as "Settings".
##
## UI volume values are linear (0..1); audio buses use decibels.
## Bindings are stored in user://settings.cfg under [controls] and rebuilt
## into the InputMap at startup (see apply_controls()).

const PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_MASTER := "master"
const KEY_MUSIC := "music"
const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const DEFAULT_VOLUME := 0.7
const DEFAULT_MUSIC_VOLUME := 0.8
const MUSIC_BASE_DB := -8.0
## linear_to_db(0) is -inf; mute the bus below this instead.
const SILENT := 0.001

const CONTROLS_SECTION := "controls"
## Gameplay actions whose keyboard/gamepad-buttons are rebindable.
const CONTROL_ACTIONS := [
	"player_move_left", "player_move_right", "player_move_up", "player_move_down",
	"player_jump", "player_punch", "player_kick", "player_dash", "pause",
]
## Movement keeps its fixed stick / d-pad events; only its keys are editable.
const MOVE_ACTIONS := [
	"player_move_left", "player_move_right", "player_move_up", "player_move_down",
]
## Actions with one editable gamepad-button slot.
const PAD_ACTIONS := ["player_jump", "player_punch", "player_kick", "player_dash", "pause"]

const ACTION_LABELS := {
	"player_move_left": "Move Left",
	"player_move_right": "Move Right",
	"player_move_up": "Move Up",
	"player_move_down": "Move Down",
	"player_jump": "Jump",
	"player_punch": "Punch",
	"player_kick": "Kick",
	"player_dash": "Dash",
	"pause": "Pause",
}

const PAD_LABELS := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}

## Stick and d-pad stay on these buttons forever; apply_controls() never
## removes them.
const DPAD_BUTTONS := [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
]

## Physical keycodes (0 = empty slot). Pad -1 = no editable pad slot.
const DEFAULTS := {
	"player_move_left": {"keys": [KEY_A, KEY_LEFT], "pad": -1},
	"player_move_right": {"keys": [KEY_D, KEY_RIGHT], "pad": -1},
	"player_move_up": {"keys": [KEY_W, KEY_UP], "pad": -1},
	"player_move_down": {"keys": [KEY_S, KEY_DOWN], "pad": -1},
	"player_jump": {"keys": [KEY_SPACE, 0], "pad": JOY_BUTTON_A},
	"player_punch": {"keys": [KEY_J, 0], "pad": JOY_BUTTON_X},
	"player_kick": {"keys": [KEY_K, 0], "pad": JOY_BUTTON_B},
	"player_dash": {"keys": [KEY_L, 0], "pad": JOY_BUTTON_RIGHT_SHOULDER},
	"pause": {"keys": [KEY_ESCAPE, 0], "pad": JOY_BUTTON_START},
}

const MAX_KEYCODE := 0x1FFFFFF
const MAX_JOY_BUTTON := 64

var master_volume := DEFAULT_VOLUME
var music_volume := DEFAULT_MUSIC_VOLUME
## action -> {"keys": [int, int], "pad": int}
var bindings: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply()
	load_controls()
	apply_controls()
	get_tree().scene_changed.connect(_on_scene_changed)
	apply.call_deferred()


# --- audio -------------------------------------------------------------

func set_master_volume(value: float, save_now := true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply()
	if save_now:
		save_settings()


func set_music_volume(value: float, save_now := true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply()
	if save_now:
		save_settings()


## Apply both faders after settings load and after every scene transition.
func apply() -> void:
	var master_bus := AudioServer.get_bus_index(MASTER_BUS)
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, master_volume < SILENT)
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(master_volume, SILENT)))
	var music_bus := AudioServer.get_bus_index(MUSIC_BUS)
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, music_volume < SILENT)
		AudioServer.set_bus_volume_db(music_bus, MUSIC_BASE_DB + linear_to_db(maxf(music_volume, SILENT)))


func _on_scene_changed() -> void:
	apply()


func master_db() -> float:
	var bus := AudioServer.get_bus_index(MASTER_BUS)
	if bus < 0:
		return -80.0
	return AudioServer.get_bus_volume_db(bus)


func master_muted() -> bool:
	var bus := AudioServer.get_bus_index(MASTER_BUS)
	return bus < 0 or AudioServer.is_bus_mute(bus)


func load_settings() -> void:
	master_volume = DEFAULT_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		master_volume = clampf(float(cfg.get_value(SECTION, KEY_MASTER, DEFAULT_VOLUME)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value(SECTION, KEY_MUSIC, DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, KEY_MASTER, master_volume)
	cfg.set_value(SECTION, KEY_MUSIC, music_volume)
	cfg.save(PATH)


# --- controls: state ---------------------------------------------------

func action_label(action: String) -> String:
	return String(ACTION_LABELS.get(action, action))


func default_bindings() -> Dictionary:
	var out := {}
	for action in CONTROL_ACTIONS:
		var d: Dictionary = DEFAULTS[action]
		out[action] = {
			"keys": [int(d["keys"][0]), int(d["keys"][1])],
			"pad": int(d["pad"]),
		}
	return out


func load_controls() -> void:
	bindings = default_bindings()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if not cfg.has_section(CONTROLS_SECTION):
		return
	for action in CONTROL_ACTIONS:
		var fallback: Dictionary = DEFAULTS[action]
		bindings[action]["keys"][0] = _read_int(
			cfg, action + "_1", int(fallback["keys"][0]), 0, MAX_KEYCODE)
		bindings[action]["keys"][1] = _read_int(
			cfg, action + "_2", int(fallback["keys"][1]), 0, MAX_KEYCODE)
		if PAD_ACTIONS.has(action):
			bindings[action]["pad"] = _read_int(
				cfg, action + "_pad", int(fallback["pad"]), -1, MAX_JOY_BUTTON)


## Missing, wrong-typed or out-of-range entries fall back to the default.
func _read_int(cfg: ConfigFile, key: String, fallback: int, low: int, high: int) -> int:
	if not cfg.has_section_key(CONTROLS_SECTION, key):
		return fallback
	var raw = cfg.get_value(CONTROLS_SECTION, key, fallback)
	var kind := typeof(raw)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return fallback
	var value := float(raw)
	if value != floorf(value):
		return fallback
	var code := int(value)
	if code < low or code > high:
		return fallback
	return code


func save_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for action in CONTROL_ACTIONS:
		var b: Dictionary = bindings[action]
		cfg.set_value(CONTROLS_SECTION, action + "_1", int(b["keys"][0]))
		cfg.set_value(CONTROLS_SECTION, action + "_2", int(b["keys"][1]))
		if PAD_ACTIONS.has(action):
			cfg.set_value(CONTROLS_SECTION, action + "_pad", int(b["pad"]))
	cfg.save(PATH)


## Rebuilds the keys + gamepad buttons of the rebindable actions. Stick axes
## and d-pad buttons are preserved, and ui_* actions are never touched.
func apply_controls() -> void:
	for action in CONTROL_ACTIONS:
		# Actions added by a newer build still get an InputMap entry.
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var keep: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				continue
			if event is InputEventJoypadButton:
				if MOVE_ACTIONS.has(action) and int(event.button_index) in DPAD_BUTTONS:
					keep.append(event)
				continue
			if event is InputEventJoypadMotion:
				keep.append(event)
		InputMap.action_erase_events(action)
		for event in keep:
			InputMap.action_add_event(action, event)
		var b: Dictionary = bindings[action]
		for slot in 2:
			var code := int(b["keys"][slot])
			if code > 0:
				var key := InputEventKey.new()
				key.physical_keycode = code
				InputMap.action_add_event(action, key)
		if PAD_ACTIONS.has(action) and int(b["pad"]) >= 0:
			var button := InputEventJoypadButton.new()
			button.button_index = int(b["pad"])
			InputMap.action_add_event(action, button)


func reset_controls() -> void:
	bindings = default_bindings()
	save_controls()
	apply_controls()


func binding_keys(action: String) -> Array:
	return (bindings[action] as Dictionary)["keys"]


func binding_pad(action: String) -> int:
	if not PAD_ACTIONS.has(action):
		return -1
	return int((bindings[action] as Dictionary)["pad"])


func binding_count(action: String) -> int:
	var b: Dictionary = bindings[action]
	var count := 0
	for slot in 2:
		if int(b["keys"][slot]) > 0:
			count += 1
	if PAD_ACTIONS.has(action) and int(b["pad"]) >= 0:
		count += 1
	return count


func key_display(code: int) -> String:
	if code <= 0:
		return "(none)"
	var keycode := code
	# The headless display server does not implement the physical mapping.
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_keycode_from_physical(code)
		if mapped != 0:
			keycode = mapped
	return OS.get_keycode_string(keycode)


func pad_display(button: int) -> String:
	if button < 0:
		return "(none)"
	if PAD_LABELS.has(button):
		return String(PAD_LABELS[button])
	return "Button %d" % button


func is_modifier_key(code: int) -> bool:
	return code == KEY_SHIFT or code == KEY_CTRL \
		or code == KEY_ALT or code == KEY_META


# --- controls: editing -------------------------------------------------

## slot: 0 = Key 1, 1 = Key 2, 2 = gamepad button.
## Returns "" on a plain change, "Swapped with X" when the input was moved off
## another action, or a rejection message when an action would lose its last
## binding. Never writes a score worse than the stored one.
func set_binding(action: String, slot: int, code: int) -> String:
	var b: Dictionary = bindings[action]
	var old := _slot_value(action, slot)
	if code == old:
		return ""
	if slot == 2:
		var pad_other := _find_pad_action(code, action)
		if pad_other != "":
			var other_slot := 2
			if _count_after_swap(pad_other, other_slot, old) < 1:
				return "Keep %s bound" % action_label(pad_other)
			bindings[pad_other]["pad"] = old
		b["pad"] = code
		save_controls()
		apply_controls()
		return "" if pad_other == "" else "Swapped with %s" % action_label(pad_other)

	var key_other := ""
	var key_other_slot := -1
	for other in CONTROL_ACTIONS:
		if other == action:
			continue
		for s in 2:
			if int(bindings[other]["keys"][s]) == code:
				key_other = other
				key_other_slot = s
	if key_other != "":
		if _count_after_swap(key_other, key_other_slot, old) < 1:
			return "Keep %s bound" % action_label(key_other)
		bindings[key_other]["keys"][key_other_slot] = old
	b["keys"][slot] = code
	save_controls()
	apply_controls()
	return "" if key_other == "" else "Swapped with %s" % action_label(key_other)


## Returns "" on success or a message when this is the action's last binding.
func clear_binding(action: String, slot: int) -> String:
	var b: Dictionary = bindings[action]
	if _slot_value(action, slot) <= 0 and slot < 2:
		return ""
	if slot == 2 and int(b["pad"]) < 0:
		return ""
	if binding_count(action) <= 1:
		return "Keep at least one binding"
	if slot == 2:
		b["pad"] = -1
	else:
		b["keys"][slot] = 0
	save_controls()
	apply_controls()
	return ""


func _slot_value(action: String, slot: int) -> int:
	var b: Dictionary = bindings[action]
	if slot == 2:
		return int(b["pad"])
	return int(b["keys"][slot])


func _find_pad_action(code: int, exclude: String) -> String:
	for other in PAD_ACTIONS:
		if other == exclude:
			continue
		if int(bindings[other]["pad"]) == code:
			return other
	return ""


## Binding count of `action` if its `slot` received `value` (before applying).
func _count_after_swap(action: String, slot: int, value: int) -> int:
	var b: Dictionary = bindings[action]
	var count := 0
	for s in 2:
		var v := value if (slot == s and slot < 2) else int(b["keys"][s])
		if v > 0:
			count += 1
	if slot == 2:
		if value >= 0:
			count += 1
	elif PAD_ACTIONS.has(action) and int(b["pad"]) >= 0:
		count += 1
	return count
