class_name Fighter
extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal died
signal hit_landed(attacker: Fighter, target: Fighter, damage: int, attack_name: String, hit_pos: Vector2)
signal hurt(damage: int, was_fatal: bool)
signal rage_changed(active: bool)

enum State { IDLE, WALK, JUMP, ATTACK, HURT, DEAD }

@export var max_health := 100
@export var move_speed := 80.0
@export var depth_speed := 45.0
@export var jump_speed := 200.0
@export var gravity := 800.0
@export var depth_tolerance := 12.0

var health := 100
var state := State.IDLE
var facing := 1
## Which way the spritesheet art is drawn; subclasses set it before super._ready().
var sprite_faces_right := true
var move_dir := 0.0
var move_dir_y := 0.0
var height := 0.0
var height_velocity := 0.0
var damage_mult := 1.0
var current_attack := ""
var combo_count := 0
var knockback_resist := 1.0
var uninterruptible := false
var is_player := false
var ko_sound := "enemy_ko"
var fades_on_death := true
var corpse_time := 1.5

# Corpses slide away with 1.5x the knockback of the killing blow, then blink
# (alpha only) and fade out. The hurt animation is the death animation: it is
# started once in _start_death() and nothing restarts it afterwards.
const DEATH_KNOCKBACK_MULT := 1.5
const CORPSE_BLINK_STEP := 0.06
const CORPSE_BLINK_DIM := 0.3
const CORPSE_FADE_TIME := 0.5
## Time the blinking+fade need, plus a hair of margin so alpha hits 0 before
## the corpse is freed.
const CORPSE_TAIL := 4.0 * CORPSE_BLINK_STEP + CORPSE_FADE_TIME + 0.08

# Dive kick (player): constant descent while active.
var dive_speed := 0.0
var dive_forward := 110.0

## Which side this fighter fights for. Damage is only ever dealt across
## teams (player <-> enemy); same-team fighters ignore each other entirely.
## Player sets "player" in its _ready(); enemies, variants and the boss stay
## "enemy" (the default).
var team := "enemy"

## Ground-plane footprint of a fighter, centred on the feet (position).
const FOOTPRINT := Rect2(-6, -3, 12, 6)

## Temporary Part 1 instrumentation: one printed line per damage event.
const DEBUG_DAMAGE := false
static var debug_total := 0
static var debug_not_attacking := 0
static var debug_counts := {}
static var debug_verbose := true

## Set by the movement code when a wanted x move hit a solid obstacle this
## frame; blocker_y is the global y of that obstacle's centre (for AI steering).
var blocked_x := false
var blocker_y := 0.0

## Targets already struck by the current swing, so one attack can only hit a
## given fighter or prop once even if it leaves and re-enters the hitbox.
var _hit_this_swing: Array[Node] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox
@onready var hurtbox: Area2D = $Hurtbox

var _base_sprite_y := 0.0
var _base_hurtbox_y := 0.0
var _base_hitbox_y := 0.0
var _base_hitbox_x := 0.0

# Subclasses override these three:
func get_animations() -> Dictionary: return {}
func get_attacks() -> Dictionary: return {}
func think(_delta: float) -> void: pass


func _ready() -> void:
	health = max_health
	_base_sprite_y = sprite.position.y
	_base_hurtbox_y = hurtbox.position.y
	_base_hitbox_y = hitbox.position.y
	_base_hitbox_x = hitbox.position.x
	collision_mask = 0
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)
	sprite.sprite_frames = _build_frames(get_animations())
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	hitbox.monitoring = false
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	# A hitbox may only be armed while this fighter is really in an active
	# attack frame. Anything that interrupted an attack (hurt, stun, landing,
	# death, a scene/state change) therefore can never leave a hitbox on.
	if hitbox != null and hitbox.monitoring and not is_attack_active():
		hitbox.set_deferred("monitoring", false)
	if state != State.DEAD:
		think(delta)

	match state:
		State.IDLE, State.WALK, State.JUMP:
			velocity.x = move_dir * move_speed
			if move_dir != 0.0:
				face(int(signf(move_dir)))
		_:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)

	# Horizontal first: if the new footprint lands inside a solid obstacle,
	# undo the move and kill the speed (this also stops knockback slides).
	blocked_x = false
	var dx := velocity.x * delta
	if dx != 0.0:
		position.x += dx
		var blocker := _blocking_obstacle()
		if blocker != null:
			position.x -= dx
			velocity.x = 0.0
			if move_dir != 0.0 \
					and (state == State.IDLE or state == State.WALK or state == State.JUMP):
				blocked_x = true
				blocker_y = blocker.get_blocker_rect().get_center().y

	# Depth independently, so fighters slide along obstacles.
	var dy := 0.0
	if state == State.IDLE or state == State.WALK or state == State.JUMP:
		dy = move_dir_y * depth_speed * delta
		if dy != 0.0:
			position.y += dy
			if _hits_solid():
				position.y -= dy

	if dive_speed > 0.0:
		height = maxf(height - dive_speed * delta, 0.0)
		height_velocity = 0.0
		var dive_dx := facing * dive_forward * delta
		position.x += dive_dx
		if _hits_solid():
			position.x -= dive_dx
		if height <= 0.0:
			_land_dive()
	elif height > 0.0 or height_velocity > 0.0:
		height += height_velocity * delta
		height_velocity -= gravity * delta
		if height <= 0.0:
			height = 0.0
			height_velocity = 0.0

	position.x = clampf(position.x, 16.0, GameState.WORLD_W - 16.0)
	position.y = clampf(position.y, GameState.lane_min_y, GameState.lane_max_y)
	_unstick()

	sprite.position.y = _base_sprite_y - height
	hurtbox.position.y = _base_hurtbox_y - height
	hitbox.position.y = _base_hitbox_y - height

	_update_locomotion()


# --- solid obstacles --------------------------------------------------

## The fighter's ground-plane footprint in world coordinates.
func footprint_rect() -> Rect2:
	return Rect2(
		position.x + FOOTPRINT.position.x,
		position.y + FOOTPRINT.position.y,
		FOOTPRINT.size.x,
		FOOTPRINT.size.y)


func _hits_solid() -> bool:
	var mine := footprint_rect()
	for node in get_tree().get_nodes_in_group("obstacles"):
		var obstacle := node as Obstacle
		if obstacle != null and obstacle.solid and mine.intersects(obstacle.get_blocker_rect()):
			return true
	return false


func _blocking_obstacle() -> Obstacle:
	var mine := footprint_rect()
	for node in get_tree().get_nodes_in_group("obstacles"):
		var obstacle := node as Obstacle
		if obstacle != null and obstacle.solid and mine.intersects(obstacle.get_blocker_rect()):
			return obstacle
	return null


## Moves by dx; returns false when a solid obstacle blocks it, undoing the move.
func try_move_x(dx: float) -> bool:
	position.x += dx
	if _hits_solid():
		position.x -= dx
		return false
	position.x = clampf(position.x, 16.0, GameState.WORLD_W - 16.0)
	return true


## Never trap a fighter: if the footprint somehow ended up inside an obstacle
## (spawn, knockback squeeze), push it out along the shortest axis.
func _unstick() -> void:
	for _pass in 2:
		var mine := footprint_rect()
		var push_x := 0.0
		var push_y := 0.0
		for node in get_tree().get_nodes_in_group("obstacles"):
			var obstacle := node as Obstacle
			if obstacle == null or not obstacle.solid:
				continue
			var rect := obstacle.get_blocker_rect()
			if not mine.intersects(rect):
				continue
			var pc := mine.get_center()
			var rc := rect.get_center()
			var need_x := (rect.size.x + mine.size.x) * 0.5 - absf(rc.x - pc.x)
			var need_y := (rect.size.y + mine.size.y) * 0.5 - absf(rc.y - pc.y)
			if need_x <= need_y:
				var cand := need_x * (-1.0 if pc.x <= rc.x else 1.0)
				if absf(cand) > absf(push_x):
					push_x = cand
			else:
				var cand := need_y * (-1.0 if pc.y <= rc.y else 1.0)
				if absf(cand) > absf(push_y):
					push_y = cand
		if absf(push_x) < 0.01 and absf(push_y) < 0.01:
			return
		# Slide out along whichever axis needs the smaller push.
		if absf(push_x) > 0.01 and (absf(push_y) < 0.01 or absf(push_x) <= absf(push_y)):
			position.x += push_x
		else:
			position.y += push_y


func face(dir: int) -> void:
	# signf() of a perfectly aligned target is 0: keep the current facing
	# instead of collapsing it (and the hitbox offset) to zero for good.
	if dir == 0:
		return
	facing = dir
	sprite.flip_h = (dir < 0) if sprite_faces_right else (dir > 0)
	hitbox.position.x = _base_hitbox_x * dir


func jump() -> void:
	if height <= 0.0 and (state == State.IDLE or state == State.WALK):
		height_velocity = jump_speed
		Fx.play("jump")


func attack(attack_name: String) -> void:
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		return
	if not get_attacks().has(attack_name):
		return
	state = State.ATTACK
	current_attack = attack_name
	_hit_this_swing.clear()
	Fx.play("whoosh")
	sprite.play(attack_name)
	# Frame 0 never emits frame_changed, so arm the hitbox here when the
	# attack is already active on its first frame.
	if sprite.frame in _attack_data().get("active", []):
		hitbox.set_deferred("monitoring", true)


func take_hit(damage: int, dir: int, knockback: float, was_fatal: bool = false, is_heavy: bool = false, attacker: Fighter = null) -> void:
	if DEBUG_DAMAGE:
		_debug_damage(damage, attacker)
	if state == State.DEAD:
		return
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	hitbox.set_deferred("monitoring", false)
	dive_speed = 0.0
	combo_count = 0
	velocity.x = dir * knockback * knockback_resist
	var fatal := was_fatal or health == 0
	if fatal:
		state = State.DEAD
		_start_death(dir, knockback)
		died.emit()
		_die_fx()
		if fades_on_death:
			_start_corpse_fade()
		hurt.emit(damage, true)
		return
	if not uninterruptible or state != State.ATTACK:
		state = State.HURT
		sprite.play("hurt")
	if is_player:
		Fx.play("player_hurt")
		Fx.hitstop(Fx.HITSTOP_LIGHT)
		Fx.shake(Fx.SHAKE_PLAYER_HIT, 0.1)
	elif is_heavy:
		Fx.hitstop(Fx.HITSTOP_HEAVY)
		Fx.shake(Fx.SHAKE_HEAVY, 0.12)
	else:
		Fx.hitstop(Fx.HITSTOP_LIGHT)
		Fx.shake(Fx.SHAKE_PLAYER_HIT, 0.1)
	hurt.emit(damage, false)


## Temporary Part 1 instrumentation: prints and counts one damage event.
func _debug_damage(damage: int, attacker: Fighter) -> void:
	var atk_name := "<none>"
	var atk_type := "unknown"
	var atk_state := "-"
	var atk_monitoring := "?"
	var atk_anim := "-"
	var atk_frame := -1
	var atk_attack := "-"
	var atk_path := "-"
	if attacker != null and is_instance_valid(attacker):
		atk_path = str(attacker.get_path())
		atk_name = String(attacker.name)
		atk_type = "player" if attacker.is_player else ("boss" if attacker is Boss else "enemy")
		atk_state = State.keys()[attacker.state]
		atk_monitoring = str(attacker.hitbox.monitoring)
		atk_anim = attacker.sprite.animation
		atk_frame = attacker.sprite.frame
		atk_attack = String(attacker.current_attack)
	var tgt_type := "player" if is_player else ("boss" if self is Boss else "enemy")
	debug_total += 1
	var key := "%s -> %s" % [atk_type, tgt_type]
	debug_counts[key] = int(debug_counts.get(key, 0)) + 1
	if atk_state != "ATTACK":
		debug_not_attacking += 1
	if not debug_verbose:
		return
	print("[DMG] t=%.2f attacker=%s(%s) target=%s(%s) attack=%s dmg=%d atk_state=%s atk_monitoring=%s atk_anim=%s atk_frame=%d atk_path=%s tgt_path=%s tgt_script=%s" % [
		Time.get_ticks_msec() / 1000.0, atk_name, atk_type, String(name), tgt_type,
		atk_attack, damage, atk_state, atk_monitoring, atk_anim, atk_frame,
		atk_path if attacker != null and is_instance_valid(attacker) else "-",
		str(get_path()), str(get_script().resource_path) if get_script() != null else "-"])


func _die_fx() -> void:
	Fx.play(ko_sound)
	Fx.hitstop(Fx.HITSTOP_KILL)
	Fx.shake(Fx.SHAKE_KILL, 0.2)


## Corpse setup: the killing blow starts the hurt animation from frame 0, turns
## the body away from the attacker and slides it with 1.5x knockback. Combat
## areas go dark here and stay dark: a corpse never hits or gets hit again.
func _start_death(dir: int, knockback: float) -> void:
	move_dir = 0.0
	move_dir_y = 0.0
	current_attack = ""
	dive_speed = 0.0
	height_velocity = 0.0
	velocity.x = float(dir) * knockback * knockback_resist * DEATH_KNOCKBACK_MULT
	if dir != 0:
		face(-dir)
	hitbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)
	hurtbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)
	for path in ["Hitbox/CollisionShape2D", "Hurtbox/CollisionShape2D"]:
		var shape := get_node_or_null(path) as CollisionShape2D
		if shape != null:
			shape.set_deferred("disabled", true)
	# Non-looping "hurt" stops on its last frame by itself and stays there.
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("hurt"):
		sprite.play("hurt")
		sprite.frame = 0
	else:
		sprite.stop()


## Hold the last hurt frame, blink twice (alpha only) and fade out.
func _start_corpse_fade() -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(corpse_time - CORPSE_TAIL, 0.0))
	for _i in 2:
		tween.tween_property(sprite, "modulate:a", CORPSE_BLINK_DIM, CORPSE_BLINK_STEP)
		tween.tween_property(sprite, "modulate:a", 1.0, CORPSE_BLINK_STEP)
	tween.tween_property(sprite, "modulate:a", 0.0, CORPSE_FADE_TIME)


func _land_dive() -> void:
	dive_speed = 0.0
	if current_attack == "dive_kick":
		hitbox.set_deferred("monitoring", false)
		current_attack = ""
		state = State.IDLE
		if sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
	Fx.shake(3.0, 0.15)
	Fx.spark(global_position, true)


func _update_locomotion() -> void:
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		return
	if height > 0.0:
		_enter(State.JUMP, "jump")
	elif move_dir != 0.0 or move_dir_y != 0.0:
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
	if not get_attacks().has(current_attack):
		return
	var data: Dictionary = get_attacks()[current_attack]
	hitbox.set_deferred("monitoring", sprite.frame in data["active"])


func _on_anim_finished() -> void:
	if state == State.DEAD:
		return
	if state == State.ATTACK or state == State.HURT:
		hitbox.set_deferred("monitoring", false)
		state = State.IDLE
		current_attack = ""
		sprite.play("idle")


# --- hitbox collision --------------------------------------------------

func _on_hitbox_area_entered(area: Area2D) -> void:
	if state == State.DEAD:
		return
	# Damage only lands while the attack is actually active.
	if not is_attack_active():
		return
	# Breakable props are Area2D roots (the area itself is the prop).
	if area != self and area.has_method("take_prop_hit"):
		# Props belong to the player team only: enemies never break them.
		if team != "player" or not _in_front(area) or not _in_lane(area):
			return
		_strike_prop(area, area)
		return
	var target := area.get_parent()
	if target == null or target == self:
		return
	if not (target is Node2D):
		return
	var target_node := target as Node2D
	if not _in_front(target_node) or not _in_lane(target_node):
		return
	if target is Fighter:
		var fighter := target as Fighter
		if fighter.state == State.DEAD:
			return
		# Same team: no damage and no feedback at all (no spark/flash/sound,
		# no shake, no hitstop). This stops enemies, escorts and the boss
		# from damaging each other.
		if fighter.team == team:
			return
		_strike_fighter(fighter)
	elif target.has_method("take_prop_hit"):
		if team != "player":
			return
		_strike_prop(target, target_node)


func _in_front(target: Node2D) -> bool:
	var dx := target.global_position.x - global_position.x
	return dx == 0.0 or int(signf(dx)) == facing


func _in_lane(target: Node2D) -> bool:
	return absf(target.global_position.y - global_position.y) <= depth_tolerance


func is_attack_active() -> bool:
	if state != State.ATTACK:
		return false
	var data := _attack_data()
	if data.is_empty():
		return false
	return sprite.frame in data["active"]


func _attack_data() -> Dictionary:
	if not get_attacks().has(current_attack):
		return {}
	return get_attacks()[current_attack]


func _strike_fighter(target: Fighter) -> void:
	var data := _attack_data()
	if data.is_empty() or _hit_this_swing.has(target):
		return
	_hit_this_swing.append(target)
	var damage := maxi(roundi(float(data["damage"]) * damage_mult), 1)
	var is_heavy: bool = bool(data.get("heavy", false))
	var hit_pos := (global_position + target.global_position) * 0.5 - Vector2(0, 24.0 + target.height)
	Fx.spark(hit_pos, is_heavy)
	Fx.flash(target, Fx.FLASH_SECONDS)
	Fx.play(String(data.get("sound", "punch_hit")))
	var fatal := target.health - damage <= 0
	combo_count += 1
	hit_landed.emit(self, target, damage, current_attack, hit_pos)
	target.take_hit(damage, facing, float(data["knockback"]), fatal, is_heavy, self)


func _strike_prop(prop: Node, prop_node: Node2D) -> void:
	var data := _attack_data()
	if data.is_empty() or _hit_this_swing.has(prop_node):
		return
	_hit_this_swing.append(prop_node)
	var damage := maxi(roundi(float(data["damage"]) * damage_mult), 1)
	var pos := (global_position + prop_node.global_position) * 0.5 - Vector2(0, 20)
	Fx.spark(pos, false)
	Fx.shake(1.0, 0.08)
	Fx.play(String(data.get("sound", "punch_hit")))
	prop.call("take_prop_hit", damage, facing, self)


# Builds animations straight from the spritesheets (no editor clicking needed)
func _build_frames(anims: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in anims:
		var d: Dictionary = anims[anim_name]
		var tex: Texture2D = load(String(d["path"]))
		var frame_w := int(tex.get_width() / int(d["frames"]))
		sf.add_animation(String(anim_name))
		sf.set_animation_speed(String(anim_name), float(d["fps"]))
		sf.set_animation_loop(String(anim_name), bool(d["loop"]))
		for i in int(d["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * frame_w, 0, frame_w, tex.get_height())
			sf.add_frame(String(anim_name), at)
	return sf
