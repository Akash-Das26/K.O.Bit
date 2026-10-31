extends Node2D
## Headless gameplay smoke test.
##
##   godot --headless --path . res://tests/smoke_test.tscn
##
## Exits 0 when every check passes. The real score file is backed up and
## restored, so running the tests never changes stored best scores.

const MAIN_GAME := preload("res://scenes/main_game.tscn")
const RESULTS := preload("res://scenes/results.tscn")
const SCORES_PATH := "user://scores.cfg"
const BURST_COMBO := 10

var checks := 0
var failures := 0

var _had_scores := false
var _scores_backup := PackedByteArray()


func _ready() -> void:
	_backup_scores()
	await get_tree().process_frame
	await _run()
	_restore_scores()
	print("==== SMOKE TEST: %d checks, %d failed ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func ok(condition: bool, label: String, extra := "") -> void:
	checks += 1
	if condition:
		print("PASS  %s %s" % [label, extra])
	else:
		failures += 1
		print("FAIL  %s %s" % [label, extra])


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _clear_enemies(game: Node) -> void:
	for child in game.fighters.get_children():
		if child is Enemy:
			child.queue_free()
	await get_tree().process_frame


func _run() -> void:
	GameState.mode = GameState.Mode.SURVIVAL
	GameState.total_rounds = 0
	GameState.select_stage(GameState.Stage.STREET)
	var game := MAIN_GAME.instantiate()
	get_tree().root.add_child(game)
	await wait(0.3)
	game.spawn_timer.stop()
	var player: Fighter = game.player

	ok(game.hud != null and game.pause_menu != null, "game scene wired")
	ok(game.stage_holder.get_child_count() > 0, "stage loaded")
	var music := Music.stream as AudioStreamWAV
	ok(music != null and music.loop_end > 0, "background music loops")

	# --- player attacks -------------------------------------------------
	_clear_enemies(game)
	player.position = Vector2(300, 200)
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	var enemy: Enemy = game.spawn_enemy(Enemy.Variant.GRUNT)
	enemy.position = Vector2(330, 200)
	enemy.health = 60
	enemy.max_health = 60
	player.face(1)
	await wait(0.1)
	player.press_jab()
	await wait(0.25)
	ok(enemy.health < 60, "jab connects", str(enemy.health))

	enemy.position = Vector2(334, 200)
	enemy.health = 60
	player.position = Vector2(300, 200)
	player.state = Fighter.State.IDLE
	player.face(1)
	player.height = 25.0
	player.height_velocity = 0.0
	player.start_dive_kick()
	await wait(0.5)
	ok(enemy.health < 60, "dive kick connects", str(enemy.health))
	ok(player.height == 0.0, "dive kick lands", str(player.height))

	# --- enemy attack and facing ---------------------------------------
	_clear_enemies(game)
	player.position = Vector2(300, 200)
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	player.height = 0.0
	player.height_velocity = 0.0
	player.state = Fighter.State.IDLE
	var attacker: Enemy = game.spawn_enemy(Enemy.Variant.GRUNT)
	attacker.position = Vector2(324, 200)
	attacker.cooldown = 0.0
	await wait(2.6)
	ok(player.health < player.max_health, "enemy punch connects", str(player.health))

	attacker.position = player.position
	attacker.target = player
	attacker.facing = 1
	attacker.hitbox.position.x = 20.0
	attacker.think(0.016)
	ok(attacker.facing == 1, "perfectly aligned target keeps facing", str(attacker.facing))
	ok(is_equal_approx(attacker.hitbox.position.x, 20.0), "hitbox offset survives alignment",
		str(attacker.hitbox.position.x))

	# --- props, food and obstacles -------------------------------------
	_clear_enemies(game)
	player.position = Vector2(300, 200)
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	var barrels := get_tree().get_nodes_in_group("props")
	ok(barrels.size() >= 2, "barrels spawned", str(barrels.size()))
	if barrels.size() > 0:
		var barrel = barrels[0]
		barrel.take_prop_hit(1, 1, player)
		ok(not barrel.broken, "barrel survives one hit")
		barrel.take_prop_hit(1, 1, player)
		ok(barrel.broken and not barrel.obstacle.solid, "barrel breaks and stops blocking")

	player.health = 40
	player.health_changed.emit(40, player.max_health)
	game._drop_food(player.position, 0)
	await wait(0.25)
	var pickups := get_tree().get_nodes_in_group("pickups")
	ok(pickups.size() > 0, "food drops", str(pickups.size()))
	if pickups.size() > 0:
		var food = pickups[pickups.size() - 1]
		food.position = player.position
		await wait(0.35)
		ok(player.health > 40, "food heals the player", str(player.health))

	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	game._drop_food(Vector2(300, 200), 0)
	await wait(0.25)
	pickups = get_tree().get_nodes_in_group("pickups")
	if pickups.size() > 0:
		var full_health_food = pickups[pickups.size() - 1]
		full_health_food.position = player.position
		await wait(0.35)
		ok(is_instance_valid(full_health_food), "full-health player leaves food on the ground")

	player.position = Vector2(380, 220)
	Input.action_press("player_move_right")
	await wait(1.4)
	Input.action_release("player_move_right")
	ok(player.position.x <= 398.0, "solid prop blocks movement", str(player.position.x))

	# --- rage mode -----------------------------------------------------
	player.health = 25
	player.health_changed.emit(25, player.max_health)
	ok(player.is_raging, "rage turns on at low health")
	ok(is_equal_approx(player.damage_mult, 1.5), "rage boosts damage", str(player.damage_mult))
	ok(game.hud.rage_label.visible, "hud shows rage")
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	ok(not player.is_raging and is_equal_approx(player.damage_mult, 1.0), "rage ends when healed")
	ok(not game.hud.rage_label.visible, "hud hides rage")

	# --- 10-hit combo burst --------------------------------------------
	_clear_enemies(game)
	player.position = Vector2(300, 200)
	player.state = Fighter.State.IDLE
	var near: Enemy = game.spawn_enemy(Enemy.Variant.GRUNT)
	near.position = Vector2(350, 200)
	near.health = 60
	near.max_health = 60
	var far: Enemy = game.spawn_enemy(Enemy.Variant.GRUNT)
	far.position = Vector2(540, 200)
	far.health = 60
	far.max_health = 60
	player.combo_count = BURST_COMBO
	game._on_player_hit_landed(player, near, 1, "jab", Vector2.ZERO)
	await wait(0.4)
	ok(near.health <= 45, "10-hit combo burst damages nearby enemies", str(near.health))
	ok(far.health == 60, "combo burst respects its radius", str(far.health))

	# --- pause menu and settings overlay -------------------------------
	game.pause_menu._toggle()
	ok(get_tree().paused, "pause menu pauses")
	game.pause_menu._on_resume_pressed()
	ok(not get_tree().paused, "resume unpauses")
	game.pause_menu._toggle()
	game.pause_menu._on_settings_pressed()
	await get_tree().process_frame
	ok(game.pause_menu.blocked, "settings overlay blocks the pause menu")
	var settings_screen = game.pause_menu._settings_screen
	if settings_screen != null:
		settings_screen._close()
		await get_tree().process_frame
	ok(not game.pause_menu.blocked, "settings overlay closes cleanly")
	game.pause_menu._on_resume_pressed()

	# --- results screen and rank ---------------------------------------
	GameState.mode = GameState.Mode.ROUNDS
	GameState.total_rounds = 3
	GameState.last_result = {
		"mode": GameState.Mode.ROUNDS,
		"stage": int(GameState.Stage.STREET),
		"total_rounds": 3,
		"outcome": "win",
		"kills": 20,
		"seconds": 90.0,
		"max_combo": 8,
		"rounds_cleared": 3,
		"round_reached": 3,
		"player_health_left": 40,
		"new_best": {},
	}
	var results = RESULTS.instantiate()
	add_child(results)
	await wait(1.0)
	var title := results.get_node("LayoutRoot/Title") as Label
	ok(title != null and title.text == "VICTORY", "results title", title.text if title != null else "")
	var rank_label: Label = results._labels["rank"]["value"]
	ok(String(rank_label.text) == "S", "strong run earns an S rank", rank_label.text)
	results.queue_free()
	await get_tree().process_frame

	# --- score persistence ---------------------------------------------
	ok(GameState.save_survival(5, 10.0), "survival score saves")
	ok(not GameState.save_survival(4, 99.0), "worse survival run rejected")
	ok(int(GameState.get_best_survival()["kills"]) == 5, "survival score reads back")
	ok(GameState.save_rounds(3, 40.0), "rounds score saves")
	ok(not GameState.save_rounds(3, 41.0), "slower rounds run rejected")

	# --- stage switching -----------------------------------------------
	GameState.select_stage(GameState.Stage.DESERT)
	game._load_stage()
	await wait(0.3)
	var obstacles := 0
	for child in game.fighters.get_children():
		if child is Obstacle:
			obstacles += 1
	ok(obstacles > 0, "desert obstacles load into the lane", str(obstacles))
	ok(is_equal_approx(GameState.lane_min_y, GameState.LANE_MIN_Y_DESERT),
		"desert lane applied", str(GameState.lane_min_y))

	game.queue_free()
	await get_tree().process_frame


# --- score file guard ---------------------------------------------------

func _backup_scores() -> void:
	_had_scores = FileAccess.file_exists(SCORES_PATH)
	if _had_scores:
		_scores_backup = FileAccess.get_file_as_bytes(SCORES_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCORES_PATH))


func _restore_scores() -> void:
	var global := ProjectSettings.globalize_path(SCORES_PATH)
	if _had_scores:
		var file := FileAccess.open(SCORES_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_scores_backup)
			file.close()
	elif FileAccess.file_exists(SCORES_PATH):
		DirAccess.remove_absolute(global)
