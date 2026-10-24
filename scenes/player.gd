extends CharacterBody2D
const move_speed := 100



func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("player_move_left"):
		velocity.x = -move_speed
	elif Input.is_action_pressed("player_move_right"):
		velocity.x = move_speed
	else:
		velocity.x = 0
	
	move_and_slide()
