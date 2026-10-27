extends Node
## Combat feedback (flash, spark, shake, hitstop, sound). Autoloaded as "Fx".

const HITSTOP_LIGHT := 0.05
const HITSTOP_HEAVY := 0.09
const HITSTOP_KILL := 0.16
const SHAKE_HEAVY := 2.0
const SHAKE_KILL := 4.0
const SHAKE_PLAYER_HIT := 2.0
const FLASH_SECONDS := 0.08
const SOUND_ENABLED := true

const HITSTOP_SCALE := 0.05
const POOL_SIZE := 8

const FLASH_SHADER: Shader = preload("res://shaders/flash.gdshader")
const AUDIO_DIR := "res://assets/audio/"

const SOUND_FILES := {
	"whoosh": "683101__florianreichelt__quick-woosh.mp3",
	"jump": "mixkit-arcade-retro-jump-223.wav",
	"jab_hit": "mixkit-small-hit-in-a-game-2072.wav",
	"punch_hit": "mixkit-boxing-punch-2051.wav",
	"kick_hit": "mixkit-martial-arts-punch-2052.wav",
	"heavy_hit": "mixkit-martial-arts-fast-punch-2047.wav",
	"player_hurt": "mixkit-boxer-getting-hit-2055.wav",
	"enemy_ko": "mixkit-boxer-getting-hit-2055.wav",
	"boss_ko": "738129__samaury20__explosion.wav",
	"player_ko": "mixkit-player-losing-or-failing-2042.wav",
	"food_pickup": "picking-food-item.wav",
	"heal": "mixkit-video-game-health-recharge-2837.wav",
	"round_clear": "mixkit-completion-of-a-level-2063.wav",
	"win": "mixkit-game-level-completed-2059.wav",
	"boss_intro": "mixkit-final-level-bonus-2061.wav",
	"jump_kick": "mixkit-quick-jump-arcade-game-239.wav",
	"dive_kick": "mixkit-player-jumping-in-a-video-game-2043.wav",
}

const SOUND_DB := {
	"whoosh": -8.0,
	"jump": -4.0,
	"jab_hit": -9.0,
	"punch_hit": -6.0,
	"kick_hit": -6.0,
	"heavy_hit": -5.0,
	"player_hurt": -4.0,
	"enemy_ko": -3.0,
	"boss_ko": -2.0,
	"player_ko": -2.0,
	"food_pickup": -2.0,
	"heal": -4.0,
	"round_clear": -2.0,
	"win": -2.0,
	"boss_intro": -2.0,
	"jump_kick": -5.0,
	"dive_kick": -5.0,
}

## Call counters, handy for headless proof runs.
var stats := {"flash": 0, "spark": 0, "sound": 0, "shake": 0, "hitstop": 0}

var _flashes: Array[Dictionary] = []
var _shake_cam: Camera2D = null
var _shake_strength := 0.0
var _shake_total := 0.0
var _shake_start := 0
var _shake_end := 0
var _hitstop_end := 0
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _warned: Dictionary = {}
var _spark_tex: Texture2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)


func _process(_delta: float) -> void:
	# Feedback runs on wall-clock deadlines so a hitstop can never stretch it.
	var now := Time.get_ticks_usec()
	if _hitstop_end > 0 and now >= _hitstop_end:
		_hitstop_end = 0
		Engine.time_scale = 1.0
	_update_flashes(now)
	_update_shake(now)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- hitstop -----------------------------------------------------------

func hitstop(seconds := HITSTOP_LIGHT) -> void:
	stats["hitstop"] = int(stats["hitstop"]) + 1
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	if deadline <= _hitstop_end:
		return
	_hitstop_end = deadline
	Engine.time_scale = HITSTOP_SCALE


func is_hitstopping() -> bool:
	return _hitstop_end > 0 and Time.get_ticks_usec() < _hitstop_end


## Force runtime back to normal; used by pause/menu/scene changes.
func reset_hitstop() -> void:
	_hitstop_end = 0
	Engine.time_scale = 1.0


# --- shake -------------------------------------------------------------

func shake(strength := 2.0, seconds := 0.12) -> void:
	stats["shake"] = int(stats["shake"]) + 1
	var now := Time.get_ticks_usec()
	if _shake_end > now:
		var active := _shake_strength * float(_shake_end - now) / float(maxi(_shake_end - _shake_start, 1))
		if strength < active:
			return
	_shake_strength = strength
	_shake_total = maxf(seconds, 0.01)
	_shake_start = now
	_shake_end = now + int(_shake_total * 1000000.0)
	if _shake_cam == null or not is_instance_valid(_shake_cam):
		_shake_cam = get_tree().get_first_node_in_group("shake_camera") as Camera2D


func _update_shake(now: int) -> void:
	if _shake_end <= 0:
		return
	if _shake_cam == null or not is_instance_valid(_shake_cam):
		_shake_cam = get_tree().get_first_node_in_group("shake_camera") as Camera2D
		if _shake_cam == null:
			_shake_end = 0
			return
	if now >= _shake_end:
		_shake_cam.offset = Vector2.ZERO
		_shake_cam = null
		_shake_strength = 0.0
		_shake_end = 0
		return
	var ratio := float(_shake_end - now) / float(maxi(_shake_end - _shake_start, 1))
	var amp := _shake_strength * ratio
	_shake_cam.offset = Vector2(
		roundf(randf_range(-amp, amp)),
		roundf(randf_range(-amp, amp)))


func shake_offset() -> Vector2:
	if _shake_cam != null and is_instance_valid(_shake_cam):
		return _shake_cam.offset
	return Vector2.ZERO


# --- flash -------------------------------------------------------------

func flash(fighter: Fighter, seconds := FLASH_SECONDS) -> void:
	if not is_instance_valid(fighter):
		return
	var sprite := fighter.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = FLASH_SHADER
		sprite.material = mat
	stats["flash"] = int(stats["flash"]) + 1
	mat.set_shader_parameter("flash_amount", 1.0)
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	for entry in _flashes:
		if entry["mat"] == mat:
			entry["deadline"] = maxi(int(entry["deadline"]), deadline)
			return
	_flashes.append({"mat": mat, "deadline": deadline})


func _update_flashes(now: int) -> void:
	if _flashes.is_empty():
		return
	var keep: Array[Dictionary] = []
	for entry in _flashes:
		var mat: ShaderMaterial = entry["mat"]
		if not is_instance_valid(mat):
			continue
		if now >= int(entry["deadline"]):
			mat.set_shader_parameter("flash_amount", 0.0)
		else:
			mat.set_shader_parameter("flash_amount", 1.0)
			keep.append(entry)
	_flashes = keep


func flash_amount(fighter: Fighter) -> float:
	if not is_instance_valid(fighter):
		return 0.0
	var sprite := fighter.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		return 0.0
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		return 0.0
	return float(mat.get_shader_parameter("flash_amount"))


# --- spark -------------------------------------------------------------

func spark(pos: Vector2, heavy: bool) -> void:
	stats["spark"] = int(stats["spark"]) + 1
	var burst := CPUParticles2D.new()
	burst.amount = 12 if heavy else 6
	burst.lifetime = 0.2
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.direction = Vector2.RIGHT
	burst.spread = 180.0
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 130.0
	burst.gravity = Vector2(0, 260)
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 2.0
	burst.color = Color(1.0, 1.0, 0.0) if heavy else Color(1.0, 1.0, 1.0)
	burst.texture = _spark_texture()
	burst.z_index = 100
	burst.position = pos
	burst.process_mode = Node.PROCESS_MODE_ALWAYS
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(burst)
	burst.finished.connect(burst.queue_free)
	burst.emitting = true


func _spark_texture() -> Texture2D:
	if _spark_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


# --- sound -------------------------------------------------------------

func play(sound_name: String) -> void:
	if not SOUND_ENABLED:
		return
	var stream := _stream_for(sound_name)
	if stream == null:
		if not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Fx.play: unknown sound \"%s\"" % sound_name)
		return
	stats["sound"] = int(stats["sound"]) + 1
	var player := _free_player()
	player.stream = stream
	player.pitch_scale = randf_range(0.95, 1.05)
	player.volume_db = float(SOUND_DB.get(sound_name, -6.0))
	player.play()


func _stream_for(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name] as AudioStream
	if not SOUND_FILES.has(sound_name):
		return null
	var path: String = AUDIO_DIR + String(SOUND_FILES[sound_name])
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	_streams[sound_name] = stream
	return stream


func _free_player() -> AudioStreamPlayer:
	for _i in POOL_SIZE:
		var player := _pool[_next_player]
		_next_player = (_next_player + 1) % POOL_SIZE
		if not player.playing:
			return player
	# All busy: steal the next one in the round-robin.
	return _pool[_next_player]


func playing_sounds() -> Array:
	var out := []
	for player in _pool:
		if player.playing and player.stream != null:
			out.append(player.stream.resource_path)
	return out


func sound_stream_path(sound_name: String) -> String:
	var stream := _stream_for(sound_name)
	if stream == null:
		return ""
	return stream.resource_path
