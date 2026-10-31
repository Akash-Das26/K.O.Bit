class_name Boss
extends Enemy

enum Phase { NONE, TELEGRAPH, DASH, STUN }

const CHARGE_COOLDOWN := 5.0
const TELEGRAPH_TIME := 0.7
const DASH_TIME := 0.5
const STUN_TIME := 1.0
const DASH_SPEED := 320.0
const CHARGE_DAMAGE := 18
const CHARGE_MIN_DIST := 140.0
const STUN_DAMAGE_MULT := 1.5

var phase := Phase.NONE
var _phase_left := 0.0
var _charge_cd := CHARGE_COOLDOWN
var _dash_dir := 1


func _ready() -> void:
	super._ready()
	max_health = 260
	health = max_health
	move_speed = 38.0
	punch_damage = 14
	knockback_resist = 0.4
	uninterruptible = true
	ko_sound = "boss_ko"
	cooldown = 1.4
	# Purple boss tint; the flash shader works on the sprite material, so it
	# stays independent from this modulate.
	modulate = Color(1.0, 0.45, 1.0)


func get_attacks() -> Dictionary:
	return {
		"punch": {
			"damage": punch_damage,
			"knockback": 80.0,
			"active": [1],
			"heavy": false,
			"sound": "punch_hit",
		},
		"charge": {
			"damage": CHARGE_DAMAGE,
			"knockback": 220.0,
			"active": [0, 1, 2, 3],
			"heavy": true,
			"sound": "heavy_hit",
		},
	}


func _reset_attack_cooldown() -> void:
	cooldown = 1.4 * cooldown_scale


func think(delta: float) -> void:
	match phase:
		Phase.TELEGRAPH:
			_phase_left -= delta
			move_dir = 0.0
			move_dir_y = 0.0
			if int(_phase_left * 12.0) % 2 == 0:
				Fx.flash(self, 0.05)
			if _phase_left <= 0.0:
				_start_dash()
			return
		Phase.DASH:
			_phase_left -= delta
			move_dir = 0.0
			move_dir_y = 0.0
			if not try_move_x(_dash_dir * DASH_SPEED * delta):
				# The charge is cancelled by a solid obstacle: 1.0 s stun.
				_start_stun()
				return
			hitbox.set_deferred("monitoring", true)
			if _phase_left <= 0.0:
				_start_stun()
			return
		Phase.STUN:
			_phase_left -= delta
			move_dir = 0.0
			move_dir_y = 0.0
			if _phase_left <= 0.0:
				phase = Phase.NONE
				cooldown = 1.0
			return

	_charge_cd = maxf(_charge_cd - delta, 0.0)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Fighter
	if target == null or target.state == State.DEAD:
		return
	var dx := target.position.x - position.x
	var dy := absf(target.position.y - position.y)
	if _charge_cd <= 0.0 and absf(dx) > CHARGE_MIN_DIST and dy <= depth_tolerance + 30.0:
		_start_telegraph()
		return
	super.think(delta)


func _start_telegraph() -> void:
	phase = Phase.TELEGRAPH
	_phase_left = TELEGRAPH_TIME
	_charge_cd = CHARGE_COOLDOWN
	move_dir = 0.0
	move_dir_y = 0.0
	Fx.play("whoosh")


func _start_dash() -> void:
	phase = Phase.DASH
	_phase_left = DASH_TIME
	# The charge is its own swing: it may hit each target once, like a punch.
	_hit_this_swing.clear()
	var target_x := target.position.x if target != null and is_instance_valid(target) else position.x
	_dash_dir = 1 if target_x >= position.x else -1
	face(_dash_dir)
	state = State.ATTACK
	current_attack = "charge"
	if sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	hitbox.set_deferred("monitoring", true)


func _start_stun() -> void:
	phase = Phase.STUN
	_phase_left = STUN_TIME
	hitbox.set_deferred("monitoring", false)
	current_attack = ""
	state = State.IDLE
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")


## The charge hits for the whole dash (its hitbox is forced on while dashing);
## telegraph and stun never land a hit even if the sprite still shows an
## attack frame from the previous attack.
func is_attack_active() -> bool:
	match phase:
		Phase.DASH:
			return state == State.ATTACK
		Phase.TELEGRAPH, Phase.STUN:
			return false
		_:
			return super.is_attack_active()
	return false


func take_hit(damage: int, dir: int, knockback: float, was_fatal: bool = false, is_heavy: bool = false, attacker: Fighter = null) -> void:
	var final_damage := damage
	if phase == Phase.STUN:
		final_damage = roundi(float(damage) * STUN_DAMAGE_MULT)
	super.take_hit(final_damage, dir, knockback, was_fatal, is_heavy, attacker)


func _die_fx() -> void:
	Fx.play("boss_ko")
	Fx.hitstop(0.25)
	Fx.shake(6.0, 0.35)
