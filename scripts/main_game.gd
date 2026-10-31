extends Node2D
## Game-mode driver: Survival (endless), Rounds (2+r enemies per round)
## and Hardcore (scaled difficulty, 5 rounds).

const SPAWN_INTERVAL := 4.0
const MAX_ALIVE := 8
const KO_HOLD := 1.5
const WIN_HOLD := 3.0
const LOSE_HOLD := 2.0
const GAME_OVER_HOLD := 3.0
const ROUND_BANNER_TIME := 1.5
const ROUND_BREAK := 2.0
const ENEMY_SPAWN_DELAY := 0.8
const CORPSE_TIME := 1.5
const PLAYER_MAX_HEALTH := 100
const ROUND_HEAL := 25
const ROUNDS_MAX_ALIVE := 3
const HARDCORE_MAX_ALIVE := 5
const HARDCORE_HEALTH_STEP := 0.4
const HARDCORE_DAMAGE_STEP := 0.3
const HARDCORE_SPEED_STEP := 0.08
const HARDCORE_COOLDOWN_STEP := 0.06

## Variant mix (see Enemy.Variant). Percentages are per spawn; the tank cap
## limits how many tanks may be alive at once.
const SURVIVAL_RUNNER_AFTER := 30.0
const SURVIVAL_TANK_AFTER := 90.0
const SURVIVAL_RUNNER_LATE := 0.30
const SURVIVAL_RUNNER_EARLY := 0.25
const SURVIVAL_TANK_LATE := 0.20
const SURVIVAL_MAX_TANKS := 2
const ROUNDS_RUNNER_FROM := 2
const ROUNDS_RUNNER_CHANCE := 0.25
const ROUNDS_TANK_FROM := 3
const ROUNDS_TANK_CHANCE := 0.20
const ROUNDS_MAX_TANKS := 2
const HARDCORE_R1_RUNNER := 0.20
const HARDCORE_R2_RUNNER := 0.30
const HARDCORE_R2_TANK := 0.15
const HARDCORE_R3_RUNNER := 0.35
const HARDCORE_R3_TANK := 0.25
const HARDCORE_MAX_TANKS := 3

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")
const BARREL_SCENE := preload("res://scenes/barrel.tscn")
const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const STAGE_STREET := preload("res://scenes/stage_street.tscn")
const STAGE_DESERT := preload("res://scenes/stage_desert.tscn")

const SURVIVAL_BARRELS := 3
const ROUND_BARRELS := 2
const MAX_FOOD := 3
const DROP_APPLE_CHANCE := 0.2

## Combo reward: every 10 hits in a row unleashes a close-range K.O. burst.
const BURST_COMBO := 10
const BURST_DAMAGE := 15
const BURST_KNOCKBACK := 220.0
const BURST_RADIUS := 130.0

## Ground-plane footprints used when checking spawns against obstacles.
const FIGHTER_FOOTPRINT := Rect2(-6, -3, 12, 6)
const BARREL_FOOTPRINT := Rect2(-10, -4, 20, 8)
const FOOD_FOOTPRINT := Rect2(-7, -3, 14, 6)

@onready var fighters: Node2D = $Fighters
@onready var player: Fighter = $Fighters/Player
@onready var hud: GameHud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var spawn_timer: Timer = $SpawnTimer
@onready var camera: Camera2D = $ShakeCamera
@onready var stage_holder: Node2D = $StageHolder

var kills := 0
var elapsed := 0.0
## Run-wide stats handed to the results screen (paused time never counts).
var run_seconds := 0.0
var max_combo := 0
var round_over := false
var end_done := false
var current_round := 1
var round_pending := 0
var enemies_alive := 0
var wave_busy := false
var hardcore := false
var boss: Boss = null

var _barrels: Array[Node] = []
var _food: Array[Node] = []
var _boss_round := false
var _next_burst := BURST_COMBO


func _ready() -> void:
	player.max_health = PLAYER_MAX_HEALTH
	player.health = PLAYER_MAX_HEALTH
	player.position.y = clampf(player.position.y, GameState.lane_min_y, GameState.lane_max_y)
	hud.bind_player(player)
	player.hit_landed.connect(_on_player_hit_landed)
	player.hurt.connect(_on_player_hurt)
	player.died.connect(_on_player_died)
	player.rage_changed.connect(_on_player_rage_changed)
	spawn_timer.wait_time = SPAWN_INTERVAL
	spawn_timer.timeout.connect(_on_spawn_timeout)
	_setup_camera()
	_load_stage()
	if GameState.mode == GameState.Mode.SURVIVAL:
		spawn_timer.start()
		_place_barrels(SURVIVAL_BARRELS)
	else:
		hardcore = GameState.mode == GameState.Mode.HARDCORE
		current_round = 0
		_next_round()
	_update_info()


func _process(delta: float) -> void:
	if not end_done:
		run_seconds += delta
		if is_instance_valid(player):
			max_combo = maxi(max_combo, player.combo_count)
			if player.combo_count < 2:
				_next_burst = BURST_COMBO
	if GameState.mode == GameState.Mode.SURVIVAL and not round_over:
		elapsed += delta
	_update_camera()
	_update_info()


# --- camera ------------------------------------------------------------

func _setup_camera() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = GameState.WORLD_W
	camera.limit_bottom = GameState.VIEW_H
	camera.position_smoothing_enabled = false
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_update_camera()


func _camera_x() -> float:
	var px := 0.0
	if is_instance_valid(player):
		px = player.position.x
	var half := float(GameState.VIEW_W) * 0.5
	return clampf(roundf(px), half, float(GameState.WORLD_W) - half)


func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	camera.position.x = _camera_x()
	camera.position.y = float(GameState.VIEW_H) * 0.5


# --- stage -------------------------------------------------------------

func _load_stage() -> void:
	for child in stage_holder.get_children():
		child.queue_free()
	# Stage props live in the y-sorted Fighters node; drop the previous stage's
	# ones so a reload cannot leave ghost obstacles behind.
	for child in fighters.get_children():
		if child is Obstacle:
			child.queue_free()
	var scene: PackedScene = STAGE_STREET
	if GameState.stage == GameState.Stage.DESERT:
		scene = STAGE_DESERT
	var stage := scene.instantiate()
	stage_holder.add_child(stage)
	# Stage props are obstacles: they are added to the y-sorted Fighters node.
	if stage.has_method("setup"):
		stage.call("setup", fighters)


# --- spawning ----------------------------------------------------------

func _spot_free(pos: Vector2, footprint: Rect2) -> bool:
	var probe := Rect2(pos + footprint.position, footprint.size)
	for node in get_tree().get_nodes_in_group("obstacles"):
		var obstacle := node as Obstacle
		if obstacle != null and obstacle.solid and probe.intersects(obstacle.get_blocker_rect()):
			return false
	return true


## Spawns must never land inside a solid obstacle: retry a few times with a
## new lane depth, then nudge in small steps until the spot is free.
func _avoid_obstacles(pos: Vector2, footprint: Rect2) -> Vector2:
	for _i in 6:
		if _spot_free(pos, footprint):
			return pos
		pos.y = randf_range(GameState.lane_min_y, GameState.lane_max_y)
	for radius in range(4, 64, 4):
		for cand in [
			Vector2(pos.x, pos.y + float(radius)),
			Vector2(pos.x, pos.y - float(radius)),
			Vector2(pos.x + float(radius), pos.y),
			Vector2(pos.x - float(radius), pos.y)]:
			cand.y = clampf(cand.y, GameState.lane_min_y, GameState.lane_max_y)
			cand.x = clampf(cand.x, 40.0, float(GameState.WORLD_W) - 40.0)
			if _spot_free(cand, footprint):
				return cand
	return pos

func _spawn_x() -> float:
	var cam_x := camera.position.x
	var half := float(GameState.VIEW_W) * 0.5
	var side := 1 if randi() % 2 == 0 else -1
	var x := clampf(cam_x + float(side) * (half + 40.0), 40.0, float(GameState.WORLD_W) - 40.0)
	var alt := clampf(cam_x - float(side) * (half + 40.0), 40.0, float(GameState.WORLD_W) - 40.0)
	# The world clamp can pull the spawn inside the view at the map edges, so
	# take the other side whenever it is the one that is really off-screen.
	if (absf(x - cam_x) < half and absf(alt - cam_x) >= half) \
			or (absf(x - player.position.x) < 200.0 \
				and absf(alt - player.position.x) > absf(x - player.position.x)):
		return alt
	return x


## variant < 0 means "let the current mode / round / time decide".
func spawn_enemy(variant := -1, health_mult := 1.0, damage_mult := 1.0, speed_mult := 1.0) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	fighters.add_child(enemy)
	if variant < 0:
		variant = _pick_variant()
	enemy.apply_variant(variant)
	enemy.position = _avoid_obstacles(
		Vector2(_spawn_x(), randf_range(GameState.lane_min_y, GameState.lane_max_y)),
		FIGHTER_FOOTPRINT)
	if health_mult != 1.0 or damage_mult != 1.0 or speed_mult != 1.0:
		enemy.apply_scaling(health_mult, damage_mult, speed_mult)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.health_changed.connect(_on_enemy_health_changed)
	enemies_alive += 1
	_update_info()
	return enemy


func _spawn_boss() -> Boss:
	var new_boss := BOSS_SCENE.instantiate() as Boss
	fighters.add_child(new_boss)
	new_boss.position = _avoid_obstacles(
		Vector2(_spawn_x(), randf_range(GameState.lane_min_y, GameState.lane_max_y)),
		FIGHTER_FOOTPRINT)
	if hardcore:
		new_boss.apply_scaling(_health_mult(), _damage_mult(), _speed_mult())
	new_boss.died.connect(_on_enemy_died.bind(new_boss))
	enemies_alive += 1
	boss = new_boss
	hud.show_boss(new_boss)
	return new_boss


func _on_spawn_timeout() -> void:
	if round_over or GameState.mode != GameState.Mode.SURVIVAL:
		return
	if enemies_alive >= MAX_ALIVE:
		return
	spawn_enemy(_pick_variant())


# --- enemy variants ----------------------------------------------------

## Chance table for the current mode, round and (in Survival) elapsed time.
## max_tanks = 0 means "no tanks in this phase".
func variant_mix() -> Dictionary:
	if GameState.mode == GameState.Mode.SURVIVAL:
		if elapsed < SURVIVAL_RUNNER_AFTER:
			return {"runner": 0.0, "tank": 0.0, "max_tanks": 0}
		if elapsed < SURVIVAL_TANK_AFTER:
			return {"runner": SURVIVAL_RUNNER_EARLY, "tank": 0.0, "max_tanks": 0}
		return {
			"runner": SURVIVAL_RUNNER_LATE,
			"tank": SURVIVAL_TANK_LATE,
			"max_tanks": SURVIVAL_MAX_TANKS}
	if hardcore:
		if current_round <= 1:
			return {"runner": HARDCORE_R1_RUNNER, "tank": 0.0, "max_tanks": 0}
		if current_round == 2:
			return {
				"runner": HARDCORE_R2_RUNNER,
				"tank": HARDCORE_R2_TANK,
				"max_tanks": HARDCORE_MAX_TANKS}
		return {
			"runner": HARDCORE_R3_RUNNER,
			"tank": HARDCORE_R3_TANK,
			"max_tanks": HARDCORE_MAX_TANKS}
	if current_round < ROUNDS_RUNNER_FROM:
		return {"runner": 0.0, "tank": 0.0, "max_tanks": 0}
	if current_round < ROUNDS_TANK_FROM:
		return {"runner": ROUNDS_RUNNER_CHANCE, "tank": 0.0, "max_tanks": 0}
	return {
		"runner": ROUNDS_RUNNER_CHANCE,
		"tank": ROUNDS_TANK_CHANCE,
		"max_tanks": ROUNDS_MAX_TANKS}


## Rolls the variant for the next spawn. One roll partitions the spawn into
## tank / runner / grunt shares; when the tank cap is already reached that
## tank slice becomes a grunt instead.
func _pick_variant() -> int:
	var mix := variant_mix()
	var tank_chance := float(mix["tank"])
	var runner_chance := float(mix["runner"])
	var roll := randf()
	if tank_chance > 0.0 and roll < tank_chance:
		if int(mix["max_tanks"]) > 0 and alive_tanks() < int(mix["max_tanks"]):
			return Enemy.Variant.TANK
		return Enemy.Variant.GRUNT
	if roll < tank_chance + runner_chance:
		return Enemy.Variant.RUNNER
	return Enemy.Variant.GRUNT


func alive_tanks() -> int:
	var count := 0
	for child in fighters.get_children():
		var enemy := child as Enemy
		if enemy != null and enemy.variant == Enemy.Variant.TANK and enemy.state != Fighter.State.DEAD:
			count += 1
	return count


func alive_variants() -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for child in fighters.get_children():
		var enemy := child as Enemy
		if enemy != null and enemy.state != Fighter.State.DEAD:
			counts[enemy.variant] += 1
	return counts


func _on_enemy_health_changed(current: int, maximum: int) -> void:
	hud.show_target(current, maximum)


# --- props / food ------------------------------------------------------

func _prop_x() -> float:
	var x := randf_range(60.0, float(GameState.WORLD_W) - 60.0)
	for _i in 12:
		if absf(x - player.position.x) >= 150.0:
			return x
		x = randf_range(60.0, float(GameState.WORLD_W) - 60.0)
	return x


func _place_barrels(count: int) -> void:
	if GameState.mode == GameState.Mode.HARDCORE:
		return
	for _i in count:
		var barrel := BARREL_SCENE.instantiate() as Area2D
		barrel.position = _avoid_obstacles(
			Vector2(_prop_x(), randf_range(GameState.lane_min_y, GameState.lane_max_y)),
			BARREL_FOOTPRINT)
		barrel.set("on_break", _on_barrel_broken)
		fighters.add_child(barrel)
		_barrels.append(barrel)


func _on_barrel_broken(pos: Vector2) -> void:
	_drop_food(pos)


func _drop_food(pos: Vector2, forced_type := -1) -> void:
	if GameState.mode == GameState.Mode.HARDCORE:
		return
	if _food.size() >= MAX_FOOD:
		var oldest: Node = _food.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var pickup := PICKUP_SCENE.instantiate() as Area2D
	var kind := forced_type
	if kind < 0:
		var roll := randf()
		kind = 0 if roll < 0.5 else (1 if roll < 0.85 else 2)
	pickup.set("food_type", kind)
	pickup.position = _avoid_obstacles(Vector2(
		clampf(pos.x, 20.0, float(GameState.WORLD_W) - 20.0),
		clampf(pos.y, GameState.lane_min_y, GameState.lane_max_y)), FOOD_FOOTPRINT)
	_food.append(pickup)
	pickup.tree_exited.connect(_forget_food.bind(pickup))
	# Drops can happen inside a physics callback, so add the Area2D deferred.
	fighters.add_child.call_deferred(pickup)


func _forget_food(pickup: Node) -> void:
	_food.erase(pickup)


func _on_player_hit_landed(_attacker: Fighter, _target: Fighter, _damage: int, _attack_name: String, _hit_pos: Vector2) -> void:
	if player.combo_count >= _next_burst:
		_next_burst = ((player.combo_count / BURST_COMBO) + 1) * BURST_COMBO
		_combo_burst.call_deferred()
	if player.combo_count >= 2:
		hud.show_combo(player.combo_count)


## Every BURST_COMBO hits the player pays the combo off with a shockwave that
## knocks back and damages everything close by.
func _combo_burst() -> void:
	if round_over or end_done or not is_instance_valid(player):
		return
	hud.show_banner("K.O. BURST!", 1.0)
	Fx.play("boss_ko")
	Fx.hitstop(Fx.HITSTOP_LIGHT)
	Fx.shake(Fx.SHAKE_KILL, 0.3)
	Fx.spark(player.global_position, true)
	for child in fighters.get_children():
		var enemy := child as Enemy
		if enemy == null or enemy.state == Fighter.State.DEAD:
			continue
		if enemy.global_position.distance_to(player.global_position) > BURST_RADIUS:
			continue
		var dir := int(signf(enemy.global_position.x - player.global_position.x))
		if dir == 0:
			dir = player.facing
		enemy.take_hit(BURST_DAMAGE, dir, BURST_KNOCKBACK, false, true, player)


func _on_player_hurt(_damage: int, _was_fatal: bool) -> void:
	hud.hide_combo()


func _on_player_rage_changed(active: bool) -> void:
	hud.show_rage(active)


# --- rounds / hardcore ------------------------------------------------

func _next_round() -> void:
	if round_over:
		return
	current_round += 1
	_boss_round = GameState.mode != GameState.Mode.SURVIVAL \
		and current_round >= GameState.total_rounds
	var banner := "ROUND %d / %d" % [current_round, GameState.total_rounds]
	if _boss_round:
		banner = "FINAL ROUND" if hardcore else "FINAL ROUND - BOSS"
	hud.show_banner(banner, ROUND_BANNER_TIME)
	_update_info()
	await get_tree().create_timer(ROUND_BANNER_TIME, false).timeout
	if not is_inside_tree() or round_over:
		return
	_place_barrels(ROUND_BARRELS)
	if _boss_round:
		Fx.play("boss_intro")
		_spawn_boss_round()
	else:
		round_pending = _enemies_in_round(current_round)
		while round_pending > 0 and enemies_alive < _max_alive():
			round_pending -= 1
			_spawn_round_enemy()
	_update_info()


func _spawn_boss_round() -> void:
	var normal := _enemies_in_round(current_round)
	var escorts := ceili(float(normal) / 2.0)
	_spawn_boss()
	for _i in escorts:
		_spawn_round_enemy()
	round_pending = 0


func _enemies_in_round(r: int) -> int:
	return (3 + 2 * r) if hardcore else (2 + r)


func _max_alive() -> int:
	return HARDCORE_MAX_ALIVE if hardcore else ROUNDS_MAX_ALIVE


func _health_mult() -> float:
	return 1.0 + HARDCORE_HEALTH_STEP * float(current_round - 1)


func _damage_mult() -> float:
	return 1.0 + HARDCORE_DAMAGE_STEP * float(current_round - 1)


func _speed_mult() -> float:
	return 1.0 + HARDCORE_SPEED_STEP * float(current_round - 1)


func _spawn_round_enemy() -> Enemy:
	var hm := 1.0
	var dm := 1.0
	var sm := 1.0
	if hardcore:
		hm = _health_mult()
		dm = _damage_mult()
		sm = _speed_mult()
	var enemy := spawn_enemy(_pick_variant(), hm, dm, sm)
	if hardcore:
		enemy.cooldown_scale = 1.0 - HARDCORE_COOLDOWN_STEP * float(current_round - 1)
		var red := 1.0 - 0.06 * float(current_round - 1)
		enemy.set_round_tint(Color(1.0, red, red))
	return enemy


func _on_enemy_died(enemy: Enemy) -> void:
	kills += 1
	enemies_alive = maxi(enemies_alive - 1, 0)
	if boss == enemy:
		boss = null
		hud.hide_boss()
	if enemies_alive <= 0:
		hud.hide_target()
	_disable_combat(enemy)
	if enemy is Boss:
		if GameState.mode == GameState.Mode.ROUNDS:
			_drop_food(enemy.position, 2)
	elif GameState.mode != GameState.Mode.HARDCORE and randf() < DROP_APPLE_CHANCE:
		_drop_food(enemy.position, 0)
	get_tree().create_timer(CORPSE_TIME, false).timeout.connect(_free_corpse.bind(enemy))
	_update_info()
	if round_over or GameState.mode == GameState.Mode.SURVIVAL:
		return
	_advance_wave()


## Untyped on purpose: the timer can fire after the enemy was freed.
func _free_corpse(enemy) -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()


func _advance_wave() -> void:
	if round_over or wave_busy:
		return
	wave_busy = true
	while not round_over and round_pending > 0 and enemies_alive < _max_alive():
		await get_tree().create_timer(ENEMY_SPAWN_DELAY, false).timeout
		if not is_inside_tree() or round_over:
			break
		if round_pending > 0 and enemies_alive < _max_alive():
			round_pending -= 1
			_spawn_round_enemy()
	wave_busy = false
	if not is_inside_tree() or round_over:
		return
	if round_pending == 0 and enemies_alive == 0:
		_round_cleared()


func _round_cleared() -> void:
	if round_over:
		return
	round_over = true
	Fx.play("round_clear")
	hud.show_banner("ROUND CLEAR", ROUND_BANNER_TIME)
	if current_round >= GameState.total_rounds:
		await get_tree().create_timer(ROUND_BANNER_TIME, false).timeout
		if not is_inside_tree():
			return
		_win()
		return
	if not hardcore:
		player.health = mini(player.health + ROUND_HEAL, player.max_health)
		player.health_changed.emit(player.health, player.max_health)
	await get_tree().create_timer(ROUND_BREAK, false).timeout
	if not is_inside_tree():
		return
	round_over = false
	await _next_round()


# --- end states (exactly one of these may fire) -----------------------

func _win() -> void:
	if end_done:
		return
	end_done = true
	round_over = true
	pause_menu.blocked = true
	spawn_timer.stop()
	hud.hide_target()
	hud.hide_boss()
	hud.show_result("YOU WIN")
	Fx.play("win")
	await get_tree().create_timer(WIN_HOLD, false).timeout
	if not is_inside_tree():
		return
	_finish_run("win")


func _on_player_died() -> void:
	if end_done:
		return
	end_done = true
	round_over = true
	pause_menu.blocked = true
	spawn_timer.stop()
	hud.hide_combo()
	hud.show_ko()
	await get_tree().create_timer(KO_HOLD, false).timeout
	if not is_inside_tree():
		return
	if GameState.mode == GameState.Mode.SURVIVAL:
		hud.show_result("GAME OVER")
		await get_tree().create_timer(GAME_OVER_HOLD, false).timeout
	else:
		hud.show_result("YOU LOSE")
		await get_tree().create_timer(LOSE_HOLD, false).timeout
	if not is_inside_tree():
		return
	_finish_run("lose")


## Collects the run's stats, stores the score and opens the results screen.
func _build_result(outcome: String) -> Dictionary:
	var cleared := 0
	if GameState.mode != GameState.Mode.SURVIVAL:
		if outcome == "win":
			cleared = int(GameState.total_rounds)
		else:
			cleared = maxi(current_round - 1, 0)
	return {
		"mode": int(GameState.mode),
		"stage": int(GameState.stage),
		"total_rounds": int(GameState.total_rounds),
		"outcome": outcome,
		"kills": kills,
		"seconds": run_seconds,
		"max_combo": max_combo,
		"rounds_cleared": cleared,
		"round_reached": maxi(current_round, 1),
		"player_health_left": maxi(player.health, 0),
	}


func _finish_run(outcome: String) -> void:
	if not is_inside_tree():
		return
	GameState.submit_result(_build_result(outcome))
	GameState.goto_scene(GameState.RESULTS_SCENE)


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _update_info() -> void:
	if GameState.mode == GameState.Mode.SURVIVAL:
		hud.set_info("SURVIVAL  Kills: %d  Time: %s" % [kills, _format_time(elapsed)])
	elif GameState.mode == GameState.Mode.HARDCORE:
		hud.set_info("HARDCORE  ROUND %d/%d  Enemies left: %d" % [
			current_round, GameState.total_rounds, enemies_alive + round_pending])
	else:
		hud.set_info("ROUND %d/%d  Enemies left: %d" % [
			current_round, GameState.total_rounds, enemies_alive + round_pending])


# A corpse must neither be hit nor hit back.
func _disable_combat(fighter: Fighter) -> void:
	for path in ["Hurtbox/CollisionShape2D", "Hitbox/CollisionShape2D"]:
		var shape: CollisionShape2D = fighter.get_node_or_null(path)
		if shape != null:
			shape.set_deferred("disabled", true)
