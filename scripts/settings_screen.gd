extends CanvasLayer
## One Settings screen with an Audio and a Controls tab.
##
## Opened as a scene from the main menu (Back returns to the menu) or added on
## top of the pause menu as an overlay (Back returns to the still-paused pause
## menu). Works while the tree is paused.

signal closed

enum Tab { AUDIO, CONTROLS }

const BUTTON_BG := Color(0.12, 0.1, 0.16, 0.85)
const BUTTON_BORDER := Color(0.45, 0.35, 0.6, 1)
const FOCUS_BG := Color(0.28, 0.22, 0.38, 0.95)
const FOCUS_BORDER := Color(1, 0.85, 0.35, 1)

## True when this screen sits on top of the pause menu instead of being the
## current scene. Set by the pause menu right after instantiate().
var overlay := false

var _tab: int = Tab.AUDIO
var _capturing := false
var _capture_action := ""
var _capture_slot := -1
var _message_left := 0.0
var _syncing := false

var _slot_buttons: Dictionary = {}
var _focus_rows: Array = []
var _preview_timer: Timer = null

@onready var audio_tab: Button = $LayoutRoot/Tabs/AudioTab
@onready var controls_tab: Button = $LayoutRoot/Tabs/ControlsTab
@onready var audio_page: Control = $LayoutRoot/AudioPage
@onready var controls_page: Control = $LayoutRoot/ControlsPage
@onready var volume_slider: HSlider = $LayoutRoot/AudioPage/VolumeRow/VolumeSlider
@onready var volume_label: Label = $LayoutRoot/AudioPage/VolumeRow/VolumeLabel
@onready var music_slider: HSlider = $LayoutRoot/AudioPage/MusicRow/MusicSlider
@onready var music_label: Label = $LayoutRoot/AudioPage/MusicRow/MusicLabel
@onready var rows_box: VBoxContainer = $LayoutRoot/ControlsPage/Rows
@onready var reset_button: Button = $LayoutRoot/Footer/ResetButton
@onready var back_button: Button = $LayoutRoot/Footer/BackButton
@onready var message_label: Label = $LayoutRoot/Message


func _ready() -> void:
	_build_controls_rows()
	_setup_preview_timer()
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_changed)
	volume_slider.drag_ended.connect(_on_slider_released)
	music_slider.drag_ended.connect(_on_slider_released)
	audio_tab.pressed.connect(_on_audio_tab_pressed)
	controls_tab.pressed.connect(_on_controls_tab_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_sync_audio()
	_refresh_bindings()
	_set_tab(Tab.AUDIO)
	audio_tab.call_deferred("grab_focus")


# --- audio tab ---------------------------------------------------------

func _setup_preview_timer() -> void:
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.35
	_preview_timer.timeout.connect(_play_preview)
	add_child(_preview_timer)


func _play_preview() -> void:
	Fx.play("punch_hit")


func _sync_audio() -> void:
	_syncing = true
	volume_slider.value = Settings.master_volume
	music_slider.value = Settings.music_volume
	_syncing = false
	_update_audio_labels()


func _update_audio_labels() -> void:
	var master_pct := roundi(Settings.master_volume * 100.0)
	volume_label.text = "Volume 0%" if master_pct <= 0 else "Volume %d%%" % master_pct
	var music_pct := roundi(Settings.music_volume * 100.0)
	music_label.text = "Music volume 0%" if music_pct <= 0 else "Music %d%%" % music_pct


func _on_volume_changed(value: float) -> void:
	if _syncing:
		return
	Settings.set_master_volume(value)
	_update_audio_labels()
	_preview_timer.start()


func _on_music_changed(value: float) -> void:
	if _syncing:
		return
	Settings.set_music_volume(value)
	_update_audio_labels()
	_preview_timer.start()


func _on_slider_released(_value_changed: bool) -> void:
	_preview_timer.stop()
	_play_preview()


func _on_audio_tab_pressed() -> void:
	_set_tab(Tab.AUDIO)


func _on_controls_tab_pressed() -> void:
	_set_tab(Tab.CONTROLS)


# --- tabs / focus ------------------------------------------------------

func _set_tab(tab: int) -> void:
	_tab = tab
	audio_page.visible = tab == Tab.AUDIO
	controls_page.visible = tab == Tab.CONTROLS
	audio_tab.modulate = Color(1, 1, 1, 1) if tab == Tab.AUDIO else Color(1, 1, 1, 0.6)
	controls_tab.modulate = Color(1, 1, 1, 1) if tab == Tab.CONTROLS else Color(1, 1, 1, 0.6)
	_rebuild_focus_chain()
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree():
		(audio_tab if tab == Tab.AUDIO else controls_tab).grab_focus()


func _rebuild_focus_chain() -> void:
	var rows: Array = [[audio_tab, controls_tab]]
	if _tab == Tab.AUDIO:
		rows.append([volume_slider])
		rows.append([music_slider])
	else:
		for action in Settings.CONTROL_ACTIONS:
			var row: Array = []
			if _slot_buttons.has("%s|0" % action):
				row.append(_slot_buttons["%s|0" % action])
			if _slot_buttons.has("%s|1" % action):
				row.append(_slot_buttons["%s|1" % action])
			if _slot_buttons.has("%s|2" % action):
				row.append(_slot_buttons["%s|2" % action])
			if not row.is_empty():
				rows.append(row)
	rows.append([reset_button, back_button])
	_focus_rows = rows
	_apply_focus_neighbors(rows)


func _apply_focus_neighbors(rows: Array) -> void:
	for r in rows.size():
		var row: Array = rows[r]
		var prev_row: Array = rows[(r - 1 + rows.size()) % rows.size()]
		var next_row: Array = rows[(r + 1) % rows.size()]
		for i in row.size():
			var control: Control = row[i]
			var left: Control = row[(i - 1 + row.size()) % row.size()]
			var right: Control = row[(i + 1) % row.size()]
			var up: Control = prev_row[mini(i, prev_row.size() - 1)]
			var down: Control = next_row[mini(i, next_row.size() - 1)]
			control.focus_neighbor_left = control.get_path_to(left)
			control.focus_neighbor_right = control.get_path_to(right)
			control.focus_neighbor_top = control.get_path_to(up)
			control.focus_neighbor_bottom = control.get_path_to(down)


# --- controls tab ------------------------------------------------------

func _build_controls_rows() -> void:
	for action in Settings.CONTROL_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = Settings.action_label(action)
		name_label.custom_minimum_size = Vector2(112, 13)
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		row.add_child(_make_slot_button(action, 0))
		row.add_child(_make_slot_button(action, 1))
		if Settings.PAD_ACTIONS.has(action):
			row.add_child(_make_slot_button(action, 2))
		else:
			var fixed := Label.new()
			fixed.text = "Stick / D-pad"
			fixed.custom_minimum_size = Vector2(110, 13)
			fixed.add_theme_font_size_override("font_size", 8)
			fixed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(fixed)
		rows_box.add_child(row)


func _make_slot_button(action: String, slot: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(96 if slot < 2 else 110, 13)
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_stylebox_override("normal", _button_style())
	button.add_theme_stylebox_override("hover", _button_style())
	button.add_theme_stylebox_override("pressed", _button_style())
	button.add_theme_stylebox_override("focus", _focus_style())
	button.set_meta("action", action)
	button.set_meta("slot", slot)
	button.pressed.connect(_on_slot_pressed.bind(action, slot))
	_slot_buttons["%s|%d" % [action, slot]] = button
	return button


func _button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BUTTON_BG
	style.set_border_width_all(1)
	style.border_color = BUTTON_BORDER
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FOCUS_BG
	style.set_border_width_all(2)
	style.border_color = FOCUS_BORDER
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _refresh_bindings() -> void:
	for action in Settings.CONTROL_ACTIONS:
		for slot in 2:
			var key := "%s|%d" % [action, slot]
			if _slot_buttons.has(key):
				(_slot_buttons[key] as Button).text = Settings.key_display(
					int(Settings.binding_keys(action)[slot]))
		var pad_key := "%s|2" % action
		if _slot_buttons.has(pad_key):
			(_slot_buttons[pad_key] as Button).text = Settings.pad_display(
				Settings.binding_pad(action))
	if _capturing:
		var capturing: Button = _slot_buttons["%s|%d" % [_capture_action, _capture_slot]]
		capturing.text = "Press a button..." if _capture_slot == 2 else "Press a key..."


# --- rebinding ---------------------------------------------------------

func _on_slot_pressed(action: String, slot: int) -> void:
	_start_capture(action, slot)


func _start_capture(action: String, slot: int) -> void:
	if _capturing:
		_end_capture()
	_capturing = true
	_capture_action = action
	_capture_slot = slot
	_refresh_bindings()


func _end_capture() -> void:
	_capturing = false
	_capture_action = ""
	_capture_slot = -1
	_refresh_bindings()


func _cancel_capture() -> void:
	_end_capture()
	_show_message("Cancelled", 1.2)


func _commit_key(code: int) -> void:
	var action := _capture_action
	var slot := _capture_slot
	_end_capture()
	var message := Settings.set_binding(action, slot, code)
	_refresh_bindings()
	if message != "":
		_show_message(message, 2.0)


func _commit_pad(button_index: int) -> void:
	var action := _capture_action
	_end_capture()
	var message := Settings.set_binding(action, 2, button_index)
	_refresh_bindings()
	if message != "":
		_show_message(message, 2.0)


func _clear_slot(action: String, slot: int) -> void:
	var message := Settings.clear_binding(action, slot)
	_refresh_bindings()
	if message != "":
		_show_message(message, 2.0)


func _on_reset_pressed() -> void:
	Settings.reset_controls()
	_refresh_bindings()
	_sync_audio()
	_show_message("Controls reset to defaults", 2.0)


func _show_message(text: String, seconds: float) -> void:
	message_label.text = text
	_message_left = seconds


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message_label.text = ""
			_message_left = 0.0


# --- input -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _capturing:
		_handle_capture(event)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
		return
	# The pause action must never toggle the pause menu behind this screen.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_set_tab(Tab.AUDIO)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_set_tab(Tab.CONTROLS)
			get_viewport().set_input_as_handled()
			return
	var focus := get_viewport().gui_get_focus_owner()
	var on_tab := focus != null and (focus == audio_tab or focus == controls_tab)
	if on_tab and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		_set_tab(Tab.CONTROLS if _tab == Tab.AUDIO else Tab.AUDIO)
		(audio_tab if _tab == Tab.AUDIO else controls_tab).grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var edit_key := int(event.keycode)
		if edit_key == 0:
			edit_key = int(event.physical_keycode)
		if edit_key == KEY_BACKSPACE or edit_key == KEY_DELETE:
			var slot := _focused_slot()
			if slot != "":
				_clear_slot(slot.get_slice("|", 0), int(slot.get_slice("|", 1)))
				get_viewport().set_input_as_handled()


func _focused_slot() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus.has_meta("action"):
		return ""
	return "%s|%d" % [String(focus.get_meta("action")), int(focus.get_meta("slot"))]


func _handle_capture(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if not event.pressed or event.echo:
			return
		var code := int(event.physical_keycode)
		if code == 0:
			code = int(event.keycode)
		if code == 0 or Settings.is_modifier_key(code):
			return
		if code == KEY_ESCAPE:
			_cancel_capture()
			return
		if code == KEY_BACKSPACE or code == KEY_DELETE:
			_clear_slot(_capture_action, _capture_slot)
			_end_capture()
			return
		if _capture_slot == 2:
			return
		_commit_key(code)
		return
	if event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		if not event.pressed:
			return
		if event.button_index == JOY_BUTTON_B:
			_cancel_capture()
			return
		if _capture_slot != 2:
			return
		_commit_pad(event.button_index)


# --- closing -----------------------------------------------------------

func _on_back_pressed() -> void:
	_close()


func _close() -> void:
	if _capturing:
		_end_capture()
	if overlay:
		closed.emit()
		queue_free()
		return
	GameState.menu_focus_hint = "settings"
	GameState.goto_scene(GameState.MENU_SCENE)
