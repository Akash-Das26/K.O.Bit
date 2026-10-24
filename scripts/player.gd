extends Fighter

const DIR := "res://assests/Streets of Fight files/Assets/Spritesheets/Brawler Girl/"


func _ready() -> void:
	super._ready()
	add_to_group("player")
	_ensure_action("player_jump", [KEY_W, KEY_SPACE])
	_ensure_action("player_punch", [KEY_J])
	_ensure_action("player_kick", [KEY_K])


func get_animations() -> Dictionary:
	return {
		"idle":      {"path": DIR + "idle.png",      "frames": 4,  "fps": 6,  "loop": true},
		"walk":      {"path": DIR + "walk.png",      "frames": 10, "fps": 12, "loop": true},
		"jump":      {"path": DIR + "jump.png",      "frames": 4,  "fps": 8,  "loop": false},
		"punch":     {"path": DIR + "punch.png",     "frames": 3,  "fps": 12, "loop": false},
		"kick":      {"path": DIR + "kick.png",      "frames": 5,  "fps": 12, "loop": false},
		"jump_kick": {"path": DIR + "jump_kick.png", "frames": 3,  "fps": 10, "loop": false},
		"hurt":      {"path": DIR + "hurt.png",      "frames": 2,  "fps": 8,  "loop": false},
	}


func get_attacks() -> Dictionary:
	# "active" = which animation frames can damage
	return {
		"punch":     {"damage": 8,  "knockback": 80.0,  "active": [1]},
		"kick":      {"damage": 12, "knockback": 140.0, "active": [2, 3]},
		"jump_kick": {"damage": 10, "knockback": 120.0, "active": [1, 2]},
	}


func think(_delta: float) -> void:
	move_dir = Input.get_axis("player_move_left", "player_move_right")
	if Input.is_action_just_pressed("player_jump"):
		jump()
	if Input.is_action_just_pressed("player_punch"):
		attack("punch")
	if Input.is_action_just_pressed("player_kick"):
		attack("kick" if is_on_floor() else "jump_kick")


func _ensure_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
