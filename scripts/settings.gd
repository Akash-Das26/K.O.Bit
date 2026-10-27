extends Node
## Audio volumes, autoloaded as "Settings" (see project.godot).
##
## UI volume values are linear (0..1); audio buses use decibels.

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

var master_volume := DEFAULT_VOLUME
var music_volume := DEFAULT_MUSIC_VOLUME


func _ready() -> void:
	load_settings()
	apply()
	get_tree().scene_changed.connect(_on_scene_changed)
	apply.call_deferred()


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
	cfg.set_value(SECTION, KEY_MASTER, master_volume)
	cfg.set_value(SECTION, KEY_MUSIC, music_volume)
	cfg.save(PATH)
