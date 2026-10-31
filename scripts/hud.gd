class_name GameHud
extends CanvasLayer

@onready var player_bar: ProgressBar = $PlayerBar
@onready var target_bar: ProgressBar = $TargetBar
@onready var info_label: Label = $InfoLabel
@onready var banner: Label = $Banner
@onready var message: Label = $Message
@onready var combo_label: Label = $ComboLabel
@onready var boss_bar: ProgressBar = $BossBar
@onready var boss_label: Label = $BossLabel
@onready var rage_label: Label = $RageLabel

var _banner_token := 0
var _combo_token := 0


func bind_player(fighter: Fighter) -> void:
	_watch(player_bar, fighter)


func show_target(current: int, maximum: int) -> void:
	target_bar.max_value = maxi(maximum, 1)
	target_bar.value = current
	target_bar.visible = true


func hide_target() -> void:
	target_bar.visible = false


func set_info(text: String) -> void:
	# Called every frame; skip identical text so the label does not re-layout.
	if info_label.text == text:
		return
	info_label.text = text


func show_rage(active: bool) -> void:
	rage_label.visible = active


func show_banner(text: String, seconds: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_token += 1
	var token := _banner_token
	get_tree().create_timer(seconds, false).timeout.connect(_hide_banner.bind(token))


func _hide_banner(token: int) -> void:
	if token == _banner_token:
		banner.visible = false


func show_combo(count: int) -> void:
	if count < 2:
		return
	combo_label.text = "x%d COMBO" % count
	combo_label.visible = true
	_combo_token += 1
	var token := _combo_token
	get_tree().create_timer(1.0, false).timeout.connect(_hide_combo.bind(token))


func _hide_combo(token: int) -> void:
	if token == _combo_token:
		combo_label.visible = false


func hide_combo() -> void:
	_combo_token += 1
	combo_label.visible = false


func show_boss(boss: Fighter) -> void:
	boss_bar.max_value = maxi(boss.max_health, 1)
	boss_bar.value = boss.health
	boss_bar.visible = true
	boss_label.visible = true
	boss.health_changed.connect(_on_boss_health)


func _on_boss_health(current: int, maximum: int) -> void:
	boss_bar.max_value = maxi(maximum, 1)
	boss_bar.value = current


func hide_boss() -> void:
	boss_bar.visible = false
	boss_label.visible = false


func show_ko() -> void:
	message.text = "K.O."
	message.visible = true


func show_result(text: String) -> void:
	message.text = text
	message.visible = true


func hide_message() -> void:
	message.visible = false


# Fill the bar right away; Fighter only emits health_changed when damage is taken.
func _watch(bar: ProgressBar, fighter: Fighter) -> void:
	bar.max_value = fighter.max_health
	bar.value = fighter.health
	fighter.health_changed.connect(func(current: int, maximum: int) -> void:
		bar.max_value = maxi(maximum, 1)
		bar.value = current)
