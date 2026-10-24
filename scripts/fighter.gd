class_name Fighter
extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal died

enum State { IDLE, WALK, JUMP, ATTACK, HURT, DEAD }

@export var max_health := 100
@export var move_speed := 80.0
@export var jump_velocity := -240.0
@export var gravity := 700.0

var health := 100
var state := State.IDLE
var facing := 1
var move_dir := 0.0
var current_attack := ""
var hit_targets: Array[Fighter] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox

# Subclasses override these three:
func get_animations() -> Dictionary: return {}
func get_attacks() -> Dictionary: return {}
func think(_delta: float) -> void: pass


func _ready() -> void:
	health = max_health
	sprite.sprite_frames = _build_frames(get_animations())
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	hitbox.monitoring = false
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	if state != State.DEAD:
		think(delta)

	match state:
		State.IDLE, State.WALK, State.JUMP:
			velocity.x = move_dir * move_speed
			if move_dir != 0.0:
				face(int(signf(move_dir)))
		_:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)

	move_and_slide()
	_update_locomotion()


func face(dir: int) -> void:
	facing = dir
	sprite.flip_h = dir < 0
	hitbox.position.x = absf(hitbox.position.x) * dir


func jump() -> void:
	if is_on_floor() and (state == State.IDLE or state == State.WALK):
		velocity.y = jump_velocity


func attack(attack_name: String) -> void:
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		return
	if not get_attacks().has(attack_name):
		return
	state = State.ATTACK
	current_attack = attack_name
	hit_targets.clear()
	sprite.play(attack_name)


func take_hit(damage: int, dir: int, knockback: float) -> void:
	if state == State.DEAD:
		return
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	hitbox.set_deferred("monitoring", false)
	velocity.x = dir * knockback
	sprite.play("hurt")
	if health == 0:
		state = State.DEAD
		died.emit()
	else:
		state = State.HURT


# --- internals ---

func _update_locomotion() -> void:
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		return
	if not is_on_floor():
		_enter(State.JUMP, "jump")
	elif absf(velocity.x) > 1.0:
		_enter(State.WALK, "walk")
	else:
		_enter(State.IDLE, "idle")


func _enter(new_state: State, anim: String) -> void:
	if state == new_state:
		return
	state = new_state
	if sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return
	var data: Dictionary = get_attacks()[current_attack]
	hitbox.set_deferred("monitoring", sprite.frame in data["active"])


func _on_anim_finished() -> void:
	if state == State.ATTACK or state == State.HURT:
		hitbox.set_deferred("monitoring", false)
		state = State.IDLE
		sprite.play("idle")


func _on_hitbox_area_entered(area: Area2D) -> void:
	var target := area.get_parent() as Fighter
	if target == null or target == self or target in hit_targets:
		return
	hit_targets.append(target)
	var data: Dictionary = get_attacks()[current_attack]
	target.take_hit(data["damage"], facing, data["knockback"])


# Builds animations straight from the spritesheets (no editor clicking needed)
func _build_frames(anims: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in anims:
		var d: Dictionary = anims[anim_name]
		var tex: Texture2D = load(d["path"])
		var frame_w := int(tex.get_width() / d["frames"])
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, d["fps"])
		sf.set_animation_loop(anim_name, d["loop"])
		for i in d["frames"]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * frame_w, 0, frame_w, tex.get_height())
			sf.add_frame(anim_name, at)
	return sf
