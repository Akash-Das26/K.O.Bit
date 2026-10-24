extends Fighter

const DIR := "res://assests/Streets of Fight files/Assets/Spritesheets/Enemy Punk/"

@export var attack_range := 26.0
var target: Fighter
var cooldown := 1.0


func _ready() -> void:
	super._ready()
	move_speed = 40.0
	max_health = 60
	health = max_health


func get_animations() -> Dictionary:
	return {
		"idle":  {"path": DIR + "idle.png",  "frames": 4, "fps": 6,  "loop": true},
		"walk":  {"path": DIR + "walk.png",  "frames": 4, "fps": 8,  "loop": true},
		"punch": {"path": DIR + "punch.png", "frames": 3, "fps": 8,  "loop": false},
		"hurt":  {"path": DIR + "hurt.png",  "frames": 4, "fps": 10, "loop": false},
	}


func get_attacks() -> Dictionary:
	return {"punch": {"damage": 6, "knockback": 80.0, "active": [1]}}


func think(delta: float) -> void:
	cooldown -= delta
	move_dir = 0.0
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Fighter
	if target == null or target.state == State.DEAD:
		return
	var dx := target.global_position.x - global_position.x
	if absf(dx) > attack_range:
		move_dir = signf(dx)
	else:
		face(int(signf(dx)))
		if cooldown <= 0.0:
			attack("punch")
			cooldown = 1.2
