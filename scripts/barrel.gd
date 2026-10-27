extends Area2D
## Breakable barrel: 2 hits, then the broken frame, a food drop and a fade.

const HP := 2
const FADE_DELAY := 3.0
const FADE_TIME := 0.4

var hp := HP
var broken := false
## Called with the barrel's global position when it breaks (drops food).
var on_break: Callable = Callable()

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var obstacle: Obstacle = $Obstacle


func _ready() -> void:
	add_to_group("props")
	sprite.hframes = 2
	sprite.frame = 0


## Temporary Part 1 instrumentation (uses Fighter's flag/counter).
func take_prop_hit(_damage: int, _dir: int, attacker: Fighter = null) -> void:
	if broken or attacker == null or attacker.team != "player":
		return
	if Fighter.DEBUG_DAMAGE:
		var atk_name := "<none>"
		var atk_type := "unknown"
		var atk_state := "-"
		var atk_monitoring := "?"
		var atk_animation := "-"
		var atk_frame := -1
		var current_attack := "-"
		if attacker != null and is_instance_valid(attacker):
			atk_name = String(attacker.name)
			atk_type = "player" if attacker.is_player else ("boss" if attacker is Boss else "enemy")
			atk_state = Fighter.State.keys()[attacker.state]
			atk_monitoring = str(attacker.hitbox.monitoring)
			atk_animation = attacker.sprite.animation
			atk_frame = attacker.sprite.frame
			current_attack = attacker.current_attack
		Fighter.debug_total += 1
		var key := "%s -> prop" % atk_type
		Fighter.debug_counts[key] = int(Fighter.debug_counts.get(key, 0)) + 1
		if atk_state != "ATTACK":
			Fighter.debug_not_attacking += 1
		print("[DMG] t=%.2f attacker=%s(%s) target=%s(barrel) attack=%s damage=%d atk_state=%s atk_monitoring=%s atk_anim=%s atk_frame=%d" % [
			Time.get_ticks_msec() / 1000.0, atk_name, atk_type, String(name), current_attack,
			_damage, atk_state, atk_monitoring, atk_animation, atk_frame])
	hp = maxi(hp - 1, 0)
	if hp <= 0:
		_break()


func _break() -> void:
	broken = true
	# Broken barrels stop blocking movement and spawns.
	obstacle.solid = false
	sprite.frame = 1
	var shape := $CollisionShape2D as CollisionShape2D
	shape.set_deferred("disabled", true)
	Fx.play("heavy_hit")
	if on_break.is_valid():
		on_break.call(global_position)
	var tween := create_tween()
	tween.tween_interval(FADE_DELAY)
	tween.tween_property(sprite, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_property(shadow, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
