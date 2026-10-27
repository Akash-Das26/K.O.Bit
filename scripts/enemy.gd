class_name Enemy
extends Fighter

const DIR := "res://assets/Spritesheets/Enemy Punk/"

## Steering: after this long blocked in x while wanting to move, detour in y.
const BLOCKED_STEER_TIME := 0.3
const DETOUR_TIME := 0.8

## Variants share one spritesheet and differ by stats + tint only.
enum Variant { GRUNT, RUNNER, TANK }

## Grunt baseline; a variant multiplies these in apply_variant().
const BASE_HEALTH := 60
const BASE_SPEED := 40.0
const BASE_DAMAGE := 6
const COOLDOWN_MIN := 0.4
const COOLDOWN_MAX := 1.4
## Attack cooldown after a swing (the random part of the enemy rhythm).
const RECOVER_MIN := 1.0
const RECOVER_MAX := 1.8

## Variant multipliers, straight from the spec.
const RUNNER_HEALTH := 0.55
const RUNNER_SPEED := 1.7
const RUNNER_DAMAGE := 0.7
const RUNNER_COOLDOWN := 0.8
const RUNNER_KNOCKBACK := 1.3
const RUNNER_TINT := Color(1.0, 0.95, 0.4)
const TANK_HEALTH := 2.4
const TANK_SPEED := 0.6
const TANK_DAMAGE := 1.5
const TANK_COOLDOWN := 1.3
const TANK_KNOCKBACK := 0.5
const TANK_TINT := Color(0.55, 0.7, 1.0)

@export var attack_range := 26.0
@export var punch_damage := BASE_DAMAGE

var target: Fighter
var cooldown := 1.0
var cooldown_scale := 1.0
## Multiplies the attack cooldown (Runner swings faster, Tank slower).
var cooldown_mult := 1.0
## Which variant this enemy is; Grunt unless apply_variant() says otherwise.
var variant := Variant.GRUNT
## Variant tint, multiplied by the per-round hardcore tint.
var base_tint := Color(1.0, 1.0, 1.0)
var round_tint := Color(1.0, 1.0, 1.0)
## Random depth standoff relative to the player, picked once on spawn.
var lane_offset := 0.0

var _blocked_time := 0.0
var _detour_left := 0.0
var _detour_dir_y := 0.0


func _ready() -> void:
	# The Enemy Punk spritesheet is drawn facing left.
	sprite_faces_right = false
	move_speed = BASE_SPEED
	max_health = BASE_HEALTH
	punch_damage = BASE_DAMAGE
	lane_offset = randf_range(-6.0, 6.0)
	cooldown = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	super._ready()
	_apply_tint()


## Variant stats. Call after the node is in the tree (base stats live in
## _ready), before any round scaling is applied.
func apply_variant(new_variant: int) -> void:
	variant = new_variant
	max_health = BASE_HEALTH
	move_speed = BASE_SPEED
	punch_damage = BASE_DAMAGE
	cooldown_mult = 1.0
	knockback_resist = 1.0
	base_tint = Color(1.0, 1.0, 1.0)
	match variant:
		Variant.RUNNER:
			max_health = maxi(roundi(float(BASE_HEALTH) * RUNNER_HEALTH), 1)
			move_speed = BASE_SPEED * RUNNER_SPEED
			punch_damage = maxi(roundi(float(BASE_DAMAGE) * RUNNER_DAMAGE), 1)
			cooldown_mult = RUNNER_COOLDOWN
			knockback_resist = RUNNER_KNOCKBACK
			base_tint = RUNNER_TINT
		Variant.TANK:
			max_health = maxi(roundi(float(BASE_HEALTH) * TANK_HEALTH), 1)
			move_speed = BASE_SPEED * TANK_SPEED
			punch_damage = maxi(roundi(float(BASE_DAMAGE) * TANK_DAMAGE), 1)
			cooldown_mult = TANK_COOLDOWN
			knockback_resist = TANK_KNOCKBACK
			base_tint = TANK_TINT
	health = max_health
	cooldown = randf_range(COOLDOWN_MIN, COOLDOWN_MAX) * cooldown_mult
	_apply_tint()
	health_changed.emit(health, max_health)


func variant_name() -> String:
	match variant:
		Variant.RUNNER:
			return "Runner"
		Variant.TANK:
			return "Tank"
		_:
			return "Grunt"


## Hardcore rounds darken every enemy a little; the variant tint stays visible.
func set_round_tint(tint: Color) -> void:
	round_tint = tint
	_apply_tint()


func _apply_tint() -> void:
	if sprite == null:
		return
	sprite.modulate = Color(
		base_tint.r * round_tint.r,
		base_tint.g * round_tint.g,
		base_tint.b * round_tint.b,
		base_tint.a * round_tint.a)


func get_animations() -> Dictionary:
	return {
		"idle":  {"path": DIR + "idle.png",  "frames": 4, "fps": 6, "loop": true},
		"walk":  {"path": DIR + "walk.png",  "frames": 4, "fps": 8, "loop": true},
		"punch": {"path": DIR + "punch.png", "frames": 3, "fps": 8, "loop": false},
		"hurt":  {"path": DIR + "hurt.png",  "frames": 4, "fps": 10, "loop": false},
	}


func get_attacks() -> Dictionary:
	return {
		"punch": {
			"damage": punch_damage,
			"knockback": 80.0,
			"active": [1],
			"heavy": false,
			"sound": "punch_hit",
		},
	}


## Difficulty scaling for Hardcore rounds.
func apply_scaling(health_mult: float, damage_mult_mult: float, speed_mult: float) -> void:
	max_health = maxi(roundi(max_health * health_mult), 1)
	health = max_health
	damage_mult = maxf(damage_mult_mult, 0.01)
	move_speed *= maxf(speed_mult, 0.01)
	health_changed.emit(health, max_health)


func _reset_attack_cooldown() -> void:
	cooldown = randf_range(RECOVER_MIN, RECOVER_MAX) * cooldown_scale * cooldown_mult


func think(delta: float) -> void:
	cooldown -= delta
	move_dir = 0.0
	move_dir_y = 0.0
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Fighter
	if target == null or target.state == State.DEAD:
		return

	# Depth first: close the lane gap (stop a couple of pixels short of the
	# personal lane offset) at the same time as the horizontal approach.
	var aim_y := target.position.y + lane_offset
	var dy := aim_y - position.y
	if absf(dy) >= 4.0:
		move_dir_y = signf(dy)

	var dx := target.position.x - position.x
	if absf(dx) > attack_range:
		move_dir = signf(dx)
	else:
		face(int(signf(dx)))
		if absf(target.position.y - position.y) <= depth_tolerance and cooldown <= 0.0:
			attack("punch")
			_reset_attack_cooldown()

	_update_steering(delta)


## Simple obstacle steering: blocked in x for a while while wanting to move
## means something is in the way; detour in y for a moment, away from the
## obstacle's centre, toward the side with more room, clamped to the lane.
func _update_steering(delta: float) -> void:
	_detour_left = maxf(_detour_left - delta, 0.0)
	if blocked_x and move_dir != 0.0:
		_blocked_time += delta
		if _blocked_time >= BLOCKED_STEER_TIME and _detour_left <= 0.0:
			_detour_dir_y = _pick_detour_dir()
			_detour_left = DETOUR_TIME
	else:
		_blocked_time = 0.0
	if _detour_left > 0.0 and move_dir != 0.0:
		move_dir_y = _detour_dir_y


func _pick_detour_dir() -> float:
	var room_up := position.y - GameState.lane_min_y
	var room_dn := GameState.lane_max_y - position.y
	# Away from the obstacle centre, unless that side has less room.
	var dir := signf(position.y - blocker_y)
	if dir == 0.0 or (dir < 0.0 and room_up < room_dn) or (dir > 0.0 and room_dn < room_up):
		dir = -1.0 if room_up >= room_dn else 1.0
	# Clamped to the lane: never detour into a side we are pressed against.
	if dir < 0.0 and room_up < 2.0:
		dir = 1.0
	elif dir > 0.0 and room_dn < 2.0:
		dir = -1.0
	return dir
