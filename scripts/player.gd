extends Fighter

## Rage: below this share of max health the player hits harder and glows red.
const DIR := "res://assets/Spritesheets/Brawler Girl/"
const COMBO_WINDOW := 0.45
const COMBO_ATTACKS := ["jab", "punch", "kick"]
const RAGE_THRESHOLD := 0.3
const RAGE_DAMAGE_MULT := 1.5

var is_raging := false

var _combo_step := 0
var _combo_window := 0.0
var _jab_buffered := false
var _rage_time := 0.0


func _ready() -> void:
	sprite_faces_right = true
	is_player = true
	team = "player"
	ko_sound = "player_ko"
	fades_on_death = false
	super._ready()
	add_to_group("player")
	health_changed.connect(_on_health_changed)
	_update_rage()


## Low health turns on extra damage; the pulse makes it readable at a glance.
func _update_rage() -> void:
	var raging := state != State.DEAD and health > 0 \
		and health <= roundi(float(max_health) * RAGE_THRESHOLD)
	damage_mult = RAGE_DAMAGE_MULT if raging else 1.0
	if raging == is_raging:
		return
	is_raging = raging
	if not is_raging:
		_rage_time = 0.0
		sprite.modulate = Color(1, 1, 1, 1)
	rage_changed.emit(is_raging)


func _on_health_changed(_current: int, _maximum: int) -> void:
	_update_rage()


func _process(delta: float) -> void:
	if not is_raging:
		return
	_rage_time += delta
	var pulse := 0.5 + 0.5 * sin(_rage_time * 9.0)
	sprite.modulate = Color(1.0, 0.72 - 0.2 * pulse, 0.72 - 0.2 * pulse, 1.0)


func get_animations() -> Dictionary:
	return {
		"idle":      {"path": DIR + "idle.png",      "frames": 4,  "fps": 6,  "loop": true},
		"walk":      {"path": DIR + "walk.png",      "frames": 10, "fps": 12, "loop": true},
		"jump":      {"path": DIR + "jump.png",      "frames": 4,  "fps": 8,  "loop": false},
		"punch":     {"path": DIR + "punch.png",     "frames": 3,  "fps": 12, "loop": false},
		"kick":      {"path": DIR + "kick.png",      "frames": 5,  "fps": 12, "loop": false},
		"jab":       {"path": DIR + "jab.png",       "frames": 3,  "fps": 14, "loop": false},
		"jump_kick": {"path": DIR + "jump_kick.png", "frames": 3,  "fps": 10, "loop": false},
		"dive_kick": {"path": DIR + "dive_kick.png", "frames": 5,  "fps": 12, "loop": false},
		"hurt":      {"path": DIR + "hurt.png",      "frames": 2,  "fps": 8,  "loop": false},
	}


func get_attacks() -> Dictionary:
	return {
		"jab":       {"damage": 5,  "knockback": 50.0,  "active": [1],       "heavy": false, "sound": "jab_hit"},
		"punch":     {"damage": 8,  "knockback": 80.0,  "active": [1],       "heavy": false, "sound": "punch_hit"},
		"kick":      {"damage": 14, "knockback": 180.0, "active": [2, 3],    "heavy": true,  "sound": "kick_hit"},
		"jump_kick": {"damage": 10, "knockback": 120.0, "active": [1, 2],    "heavy": true,  "sound": "heavy_hit"},
		"dive_kick": {"damage": 16, "knockback": 160.0, "active": [0, 1, 2, 3, 4], "heavy": true,  "sound": "heavy_hit"},
	}


func think(delta: float) -> void:
	_combo_window = maxf(_combo_window - delta, 0.0)
	if _combo_window <= 0.0 and state != State.ATTACK:
		_combo_step = 0
		combo_count = 0
	move_dir = Input.get_axis("player_move_left", "player_move_right")
	move_dir_y = Input.get_axis("player_move_up", "player_move_down")
	if Input.is_action_just_pressed("player_jump"):
		jump()
	if Input.is_action_just_pressed("player_punch"):
		press_jab()
	if Input.is_action_just_pressed("player_kick"):
		press_kick()


# --- jab combo ---------------------------------------------------------

func press_jab() -> void:
	if state == State.HURT or state == State.DEAD:
		return
	if state == State.ATTACK:
		if String(current_attack) in COMBO_ATTACKS:
			_jab_buffered = true
		return
	_advance_combo()


func _advance_combo() -> void:
	if _combo_step >= 1 and _combo_step < COMBO_ATTACKS.size() and _combo_window > 0.0:
		_combo_step += 1
	else:
		_combo_step = 1
	_combo_window = 0.0
	attack(String(COMBO_ATTACKS[_combo_step - 1]))


func _on_anim_finished() -> void:
	var finished := String(current_attack)
	super._on_anim_finished()
	if String(finished) in COMBO_ATTACKS:
		if _combo_step >= COMBO_ATTACKS.size():
			_combo_step = 0
			_combo_window = 0.0
		else:
			_combo_window = COMBO_WINDOW
	if _jab_buffered:
		_jab_buffered = false
		if _combo_window > 0.0 and _combo_step < COMBO_ATTACKS.size():
			_advance_combo()


# --- kicks -------------------------------------------------------------

func press_kick() -> void:
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		return
	if height > 0.0:
		if Input.is_action_pressed("player_move_down"):
			start_dive_kick()
		else:
			Fx.play("jump_kick")
			attack("jump_kick")
	else:
		attack("kick")


## The dive kick damages only while the dive is actually descending with an
## active frame; landing or an interrupted attack turns it off.
func is_attack_active() -> bool:
	if state == State.ATTACK and String(current_attack) == "dive_kick" and dive_speed > 0.0:
		return sprite.frame in get_attacks()["dive_kick"]["active"]
	return super.is_attack_active()


func start_dive_kick() -> void:
	attack("dive_kick")
	if state == State.ATTACK and current_attack == "dive_kick":
		dive_speed = 260.0
		dive_forward = 110.0
		height_velocity = 0.0
		Fx.play("dive_kick")
