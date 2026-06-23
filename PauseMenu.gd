extends CanvasLayer

@onready var panel: Panel = find_child("Panel") as Panel
@onready var main_view: Control = find_child("MainView") as Control
@onready var load_view: Control = find_child("LoadView") as Control
@onready var confirm_view: Control = find_child("ConfirmView") as Control

@onready var volume_slider: HSlider = find_child("VolumeSlider") as HSlider
@onready var mute_check: CheckButton = find_child("MuteCheck") as CheckButton
@onready var fullscreen_check: CheckButton = find_child("FullscreenCheck") as CheckButton

@onready var resume_button: Button = find_child("ResumeButton") as Button
@onready var load_button: Button = find_child("LoadButton") as Button
@onready var exit_button: Button = find_child("ExitButton") as Button

@onready var load_slot1_button: Button = find_child("LoadSlot1Button") as Button
@onready var load_slot2_button: Button = find_child("LoadSlot2Button") as Button
@onready var load_slot3_button: Button = find_child("LoadSlot3Button") as Button
@onready var load_back_button: Button = find_child("LoadBackButton") as Button
@onready var load_status_label: Label = find_child("LoadStatusLabel") as Label

@onready var confirm_label: Label = find_child("ConfirmLabel") as Label
@onready var exit_anyway_button: Button = find_child("ExitAnywayButton") as Button
@onready var cancel_exit_button: Button = find_child("CancelExitButton") as Button

@onready var menu_button: Button = find_child("MenuButton") as Button

const COL_BG := Color(0.06, 0.07, 0.11, 0.97)
const COL_BORDER := Color(0.35, 0.40, 0.55)
const MASTER_BUS := 0

# ── In-combat mini overlay ──
var combat_panel: Panel = null
var flee_button: Button = null
var combat_resume_button: Button = null


func _ready() -> void:
	if is_instance_valid(panel):
		panel.visible = false
	_style_panel()
	_style_buttons()
	_style_menu_button()
	_build_combat_overlay()

	if is_instance_valid(volume_slider):
		volume_slider.min_value = 0.0
		volume_slider.max_value = 1.0
		volume_slider.step = 0.01
		volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS))
		volume_slider.value_changed.connect(_on_volume_changed)

	if is_instance_valid(mute_check):
		mute_check.text = "Mute"
		mute_check.button_pressed = AudioServer.is_bus_mute(MASTER_BUS)
		mute_check.toggled.connect(_on_mute_toggled)

	if is_instance_valid(fullscreen_check):
		fullscreen_check.text = "Fullscreen"
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	if is_instance_valid(resume_button):
		resume_button.text = "▶  Resume"
		resume_button.pressed.connect(close_menu)

	if is_instance_valid(load_button):
		load_button.text = "📂  Load Game"
		load_button.pressed.connect(_show_load_view)

	if is_instance_valid(exit_button):
		exit_button.text = "🚪  Exit to Desktop"
		exit_button.pressed.connect(_on_exit_pressed)

	for i in range(3):
		var btn = _load_slot_button(i + 1)
		if is_instance_valid(btn):
			var slot_num = i + 1
			btn.pressed.connect(func(): _on_load_slot_pressed(slot_num))

	if is_instance_valid(load_back_button):
		load_back_button.text = "↩  Back"
		load_back_button.pressed.connect(_show_main_view)

	if is_instance_valid(exit_anyway_button):
		exit_anyway_button.text = "⚠️  Exit Anyway"
		exit_anyway_button.pressed.connect(func(): get_tree().quit())

	if is_instance_valid(cancel_exit_button):
		cancel_exit_button.text = "Cancel"
		cancel_exit_button.pressed.connect(_show_main_view)

	if is_instance_valid(menu_button):
		menu_button.text = "☰  Menu"
		menu_button.focus_mode = Control.FOCUS_NONE
		menu_button.pressed.connect(_on_menu_button_pressed)


func _build_combat_overlay() -> void:
	combat_panel = Panel.new()
	combat_panel.name = "CombatMenuPanel"
	combat_panel.visible = false
	combat_panel.z_index = 200

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.13, 0.97)
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = Color(0.55, 0.25, 0.25)
	combat_panel.add_theme_stylebox_override("panel", s)
	combat_panel.custom_minimum_size = Vector2(420, 280)
	add_child(combat_panel)
	# Defer positioning so the panel has a layout size before we center it
	combat_panel.call_deferred("_notification", NOTIFICATION_RESIZED)
	get_tree().process_frame.connect(_center_combat_panel, CONNECT_ONE_SHOT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	combat_panel.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 22)

	var title = Label.new()
	title.text = "☰  COMBAT MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var hint = Label.new()
	hint.text = "You are in combat.\nToggle audio/display below.\nFlee to abandon this fight and reload."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hint)

	var audio_hbox = HBoxContainer.new()
	audio_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	audio_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(audio_hbox)

	var mute_btn = Button.new()
	mute_btn.text = "🔇  Toggle Mute"
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.custom_minimum_size = Vector2(140, 38)
	mute_btn.pressed.connect(func():
		var muted = not AudioServer.is_bus_mute(MASTER_BUS)
		AudioServer.set_bus_mute(MASTER_BUS, muted)
		mute_btn.text = "🔊  Unmute" if muted else "🔇  Toggle Mute"
	)
	audio_hbox.add_child(mute_btn)

	var fs_btn = Button.new()
	fs_btn.text = "🖥️  Fullscreen"
	fs_btn.focus_mode = Control.FOCUS_NONE
	fs_btn.custom_minimum_size = Vector2(140, 38)
	fs_btn.pressed.connect(func():
		var is_fs = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if is_fs else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
	)
	audio_hbox.add_child(fs_btn)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	combat_resume_button = Button.new()
	combat_resume_button.text = "▶  Keep Fighting"
	combat_resume_button.focus_mode = Control.FOCUS_NONE
	combat_resume_button.custom_minimum_size = Vector2(150, 44)
	combat_resume_button.add_theme_font_size_override("font_size", 14)
	combat_resume_button.pressed.connect(_close_combat_menu)
	btn_hbox.add_child(combat_resume_button)

	flee_button = Button.new()
	flee_button.text = "🏃  Flee & Restart"
	flee_button.focus_mode = Control.FOCUS_NONE
	flee_button.custom_minimum_size = Vector2(150, 44)
	flee_button.add_theme_font_size_override("font_size", 14)
	var flee_style = StyleBoxFlat.new()
	flee_style.bg_color = Color(0.28, 0.10, 0.10)
	flee_style.set_corner_radius_all(6)
	flee_style.set_border_width_all(1)
	flee_style.border_color = Color(0.70, 0.25, 0.25)
	flee_button.add_theme_stylebox_override("normal", flee_style)
	flee_button.pressed.connect(_on_flee_pressed)
	btn_hbox.add_child(flee_button)


func _center_combat_panel() -> void:
	if not is_instance_valid(combat_panel): return
	var vp = get_viewport()
	if not is_instance_valid(vp): return
	var vp_size = vp.get_visible_rect().size
	var panel_size = combat_panel.get_combined_minimum_size()
	combat_panel.set_position((vp_size - panel_size) * 0.5)
	combat_panel.set_size(panel_size)

func _open_combat_menu() -> void:
	if is_instance_valid(combat_panel):
		# Re-center every time in case window was resized
		_center_combat_panel()
		combat_panel.visible = true


func _close_combat_menu() -> void:
	if is_instance_valid(combat_panel):
		combat_panel.visible = false


func _on_flee_pressed() -> void:
	_close_combat_menu()
	var combat_ui = get_tree().root.find_child("CombatUI", true, false)
	if is_instance_valid(combat_ui):
		if is_instance_valid(combat_ui.current_enemy):
			combat_ui.current_enemy.is_in_combat = false
		combat_ui.visible = false
	QuestManager.is_in_combat = false
	Engine.time_scale = 1.0
	if QuestManager.load_game(QuestManager.last_used_slot):
		get_tree().reload_current_scene()
	else:
		get_tree().reload_current_scene()


func _style_panel() -> void:
	if not is_instance_valid(panel): return
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = COL_BORDER
	panel.add_theme_stylebox_override("panel", s)


func _style_buttons() -> void:
	var all_buttons = [resume_button, load_button, exit_button,
		load_slot1_button, load_slot2_button, load_slot3_button, load_back_button,
		exit_anyway_button, cancel_exit_button]
	for btn in all_buttons:
		if not is_instance_valid(btn): continue
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 42)


func _style_menu_button() -> void:
	if not is_instance_valid(menu_button): return
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.11, 0.16, 0.9)
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = COL_BORDER
	menu_button.add_theme_stylebox_override("normal", s)


func _load_slot_button(slot: int) -> Button:
	match slot:
		1: return load_slot1_button
		2: return load_slot2_button
		3: return load_slot3_button
	return null


func _other_menu_is_open() -> bool:
	for n in ["EquipmentMenu", "RoadmapPopup", "SavePopup"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node.visible:
			return true
	return false


func _is_panel_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func _is_combat_menu_open() -> bool:
	return is_instance_valid(combat_panel) and combat_panel.visible

func is_open() -> bool:
	return _is_panel_open() or _is_combat_menu_open()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.is_echo():
		if _is_combat_menu_open():
			_close_combat_menu()
			get_viewport().set_input_as_handled()
			return
		if _is_panel_open():
			close_menu()
			get_viewport().set_input_as_handled()
			return
		if QuestManager.is_in_combat:
			_open_combat_menu()
			get_viewport().set_input_as_handled()
			return
		if _other_menu_is_open():
			return
		open_menu()
		get_viewport().set_input_as_handled()


func _on_menu_button_pressed() -> void:
	if _is_combat_menu_open():
		_close_combat_menu()
		return
	if _is_panel_open():
		close_menu()
		return
	if QuestManager.is_in_combat:
		_open_combat_menu()
		return
	if not _other_menu_is_open():
		open_menu()


func open_menu() -> void:
	if is_instance_valid(panel): panel.visible = true
	Engine.time_scale = 0.0
	_show_main_view()


func close_menu() -> void:
	if is_instance_valid(panel): panel.visible = false
	Engine.time_scale = 1.0


func _show_main_view() -> void:
	if is_instance_valid(main_view): main_view.visible = true
	if is_instance_valid(load_view): load_view.visible = false
	if is_instance_valid(confirm_view): confirm_view.visible = false


func _show_load_view() -> void:
	if is_instance_valid(main_view): main_view.visible = false
	if is_instance_valid(load_view): load_view.visible = true
	if is_instance_valid(confirm_view): confirm_view.visible = false
	_refresh_load_slot_labels()
	if is_instance_valid(load_status_label):
		load_status_label.text = "Choose a slot to load:"
		load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))


func _refresh_load_slot_labels() -> void:
	for i in range(3):
		var slot = i + 1
		var btn = _load_slot_button(slot)
		if not is_instance_valid(btn): continue
		var info = QuestManager.get_slot_info(slot)
		if info.get("exists", false):
			btn.text = "Slot %d — Level %d" % [slot, info.get("level", 1)]
			btn.disabled = false
		else:
			btn.text = "Slot %d — Empty" % slot
			btn.disabled = true


func _on_load_slot_pressed(slot: int) -> void:
	if QuestManager.load_game(slot):
		close_menu()
		get_tree().reload_current_scene()
	elif is_instance_valid(load_status_label):
		load_status_label.text = "⚠️  Slot %d is empty!" % slot
		load_status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(value))


func _on_mute_toggled(pressed: bool) -> void:
	AudioServer.set_bus_mute(MASTER_BUS, pressed)


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_exit_pressed() -> void:
	if QuestManager.has_unsaved_progress:
		if is_instance_valid(main_view): main_view.visible = false
		if is_instance_valid(load_view): load_view.visible = false
		if is_instance_valid(confirm_view): confirm_view.visible = true
		if is_instance_valid(confirm_label):
			confirm_label.text = "Unsaved progress will be lost!\nVisit the Elder NPC to save before exiting."
	else:
		get_tree().quit()
