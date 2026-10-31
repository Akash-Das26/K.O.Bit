extends Area2D
## Food pickup: bobs, blinks out after 12 s, heals the player on touch.

enum FoodType { APPLE, DRUMSTICK, BURGER }

const HEAL_AMOUNT := [15, 25, 40]
const LIFETIME := 12.0
const BLINK_TIME := 3.0

var food_type := FoodType.APPLE

var _life := LIFETIME
var _t := 0.0
var _collected := false

@onready var sprite: Sprite2D = $Sprite
@onready var label: Label = $Label


func _ready() -> void:
	add_to_group("pickups")
	sprite.hframes = 3
	sprite.frame = food_type
	label.visible = false
	_t = randf() * TAU
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	if _collected:
		return
	_t += delta
	_life -= delta
	sprite.position.y = -8.0 + sin(_t * 3.0) * 2.0
	if _life <= BLINK_TIME:
		sprite.modulate.a = 0.35 if int(_life * 8.0) % 2 == 0 else 1.0
	if _life <= 0.0:
		queue_free()


func heal_amount() -> int:
	return int(HEAL_AMOUNT[food_type])


func _on_area_entered(area: Area2D) -> void:
	if _collected:
		return
	var body := area.get_parent()
	if not (body is Fighter):
		return
	var fighter := body as Fighter
	if not fighter.is_player or fighter.state == Fighter.State.DEAD:
		return
	if absf(fighter.global_position.y - global_position.y) > fighter.depth_tolerance:
		return
	# Leave the food on the ground rather than burning it for a +0 heal.
	if fighter.health >= fighter.max_health:
		return
	_collect(fighter)


func _collect(fighter: Fighter) -> void:
	_collected = true
	set_deferred("monitoring", false)
	var before := fighter.health
	fighter.health = mini(fighter.health + heal_amount(), fighter.max_health)
	fighter.health_changed.emit(fighter.health, fighter.max_health)
	Fx.play("food_pickup")
	Fx.play("heal")
	sprite.visible = false
	label.text = "+%d" % (fighter.health - before)
	label.visible = true
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 16.0, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
