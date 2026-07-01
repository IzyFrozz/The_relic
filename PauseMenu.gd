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

var pause_timer_label: Label = null

# ── Keybinds (built in code) ──
var keybind_button: Button = null
var keybind_view: VBoxContainer = null
var keybind_rows: Dictionary = {}
var _rebinding_action: String = ""

const COL_BG := Color(0.06, 0.07, 0.11, 0.97)
const COL_BORDER := Color(0.35, 0.40, 0.55)
const MASTER_BUS := 0

var combat_panel: Panel = null
var flee_button: Button = null
var combat_resume_button: Button = null

var _prev_in_combat: bool = false

# Captures whatever position/anchors the editor authored for the menu button
# in the overworld (including any per-scene instance override, e.g. the
# offset_top=41/offset_bottom=77 override set in main.tscn). Combat mode
# temporarily moves the button to top-centre; leaving combat restores
# exactly these captured values instead of a hardcoded guess.
var _overworld_anchor_left: float = 1.0
var _overworld_anchor_right: float = 1.0
var _overworld_anchor_top: float = 0.0
var _overworld_anchor_bottom: float = 0.0
var _overworld_offset_left: float = -110.0
var _overworld_offset_right: float = -10.0
var _overworld_offset_top: float = 10.0
var _overworld_offset_bottom: float = 46.0
var _overworld_grow_horizontal: int = Control.GROW_DIRECTION_BEGIN
var _captured_overworld_position: bool = false

# ── Ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if is_instance_valid(panel):
		panel.visible = false
	_style_panel()
	_style_buttons()
	_style_menu_button()
	_build_combat_overlay()
	_build_pause_timer_label()
	_capture_overworld_menu_position()

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
		exit_button.text = "🏠  Main Menu"
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
		exit_anyway_button.text = "⚠️  Leave Anyway"
		exit_anyway_button.pressed.connect(_go_to_main_menu)

	if is_instance_valid(cancel_exit_button):
		cancel_exit_button.text = "Cancel"
		cancel_exit_button.pressed.connect(_show_main_view)

	if is_instance_valid(menu_button):
		menu_button.text = "☰  Menu"
		menu_button.focus_mode = Control.FOCUS_NONE
		menu_button.pressed.connect(_on_menu_button_pressed)

	_build_keybinds_ui()

func _capture_overworld_menu_position() -> void:
	if not is_instance_valid(menu_button) or _captured_overworld_position:
		return
	_overworld_anchor_left      = menu_button.anchor_left
	_overworld_anchor_right     = menu_button.anchor_right
	_overworld_anchor_top       = menu_button.anchor_top
	_overworld_anchor_bottom    = menu_button.anchor_bottom
	_overworld_offset_left      = menu_button.offset_left
	_overworld_offset_right     = menu_button.offset_right
	_overworld_offset_top       = menu_button.offset_top
	_overworld_offset_bottom    = menu_button.offset_bottom
	_overworld_grow_horizontal  = menu_button.grow_horizontal
	_captured_overworld_position = true

func _process(_delta: float) -> void:
	var in_combat = QuestManager.is_in_combat
	if in_combat != _prev_in_combat:
		_prev_in_combat = in_combat
		_reposition_menu_button(in_combat)
	if is_instance_valid(pause_timer_label) and pause_timer_label.visible:
		pause_timer_label.text = "⏱  " + _fmt_time(QuestManager.play_time_seconds)

# ── Play timer (moved here from OverworldHUD, top-right of the pause popup) ──
func _build_pause_timer_label() -> void:
	if not is_instance_valid(panel): return
	pause_timer_label = Label.new()
	pause_timer_label.name = "PauseTimerLabel"
	pause_timer_label.add_theme_font_size_override("font_size", 14)
	pause_timer_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.95, 1.0))
	pause_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_timer_label.anchor_left   = 1.0
	pause_timer_label.anchor_right  = 1.0
	pause_timer_label.anchor_top    = 0.0
	pause_timer_label.anchor_bottom = 0.0
	pause_timer_label.offset_left   = -170.0
	pause_timer_label.offset_right  = -18.0
	pause_timer_label.offset_top    = 16.0
	pause_timer_label.offset_bottom = 40.0
	pause_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.add_child(pause_timer_label)

# Same time format as the old OverworldHUD timer (H:MM:SS once past an hour).
func _fmt_time(sec: float) -> String:
	var t = int(sec)
	var h = t / 3600; var m = (t % 3600) / 60; var s = t % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%02d:%02d" % [m, s]

func _reposition_menu_button(in_combat: bool) -> void:
	if not is_instance_valid(menu_button): return
	if in_combat:
		menu_button.anchor_left   = 0.5
		menu_button.anchor_right  = 0.5
		menu_button.anchor_top    = 0.0
		menu_button.anchor_bottom = 0.0
		menu_button.offset_left   = -60.0
		menu_button.offset_right  =  60.0
		menu_button.offset_top    =  10.0
		menu_button.offset_bottom =  46.0
		menu_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		# Restore the exact position the editor authored (including any
		# per-scene instance override), instead of a hardcoded guess.
		menu_button.anchor_left   = _overworld_anchor_left
		menu_button.anchor_right  = _overworld_anchor_right
		menu_button.anchor_top    = _overworld_anchor_top
		menu_button.anchor_bottom = _overworld_anchor_bottom
		menu_button.offset_left   = _overworld_offset_left
		menu_button.offset_right  = _overworld_offset_right
		menu_button.offset_top    = _overworld_offset_top
		menu_button.offset_bottom = _overworld_offset_bottom
		menu_button.grow_horizontal = _overworld_grow_horizontal

# ── Combat overlay ────────────────────────────────────────────────────────────
func _build_combat_overlay() -> void:
	combat_panel = Panel.new()
	combat_panel.name = "CombatMenuPanel"
	combat_panel.visible = false
	combat_panel.z_index = 200

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.13, 0.97)
	s.set_corner_radius_all(12); s.set_border_width_all(2)
	s.border_color = Color(0.55, 0.25, 0.25)
	combat_panel.add_theme_stylebox_override("panel", s)
	combat_panel.custom_minimum_size = Vector2(420, 280)
	add_child(combat_panel)
	get_tree().process_frame.connect(_center_combat_panel, CONNECT_ONE_SHOT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	combat_panel.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 22)

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
			DisplayServer.WINDOW_MODE_WINDOWED if is_fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
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
	flee_style.set_corner_radius_all(6); flee_style.set_border_width_all(1)
	flee_style.border_color = Color(0.70, 0.25, 0.25)
	flee_button.add_theme_stylebox_override("normal", flee_style)
	flee_button.pressed.connect(_on_flee_pressed)
	btn_hbox.add_child(flee_button)

func _center_combat_panel() -> void:
	if not is_instance_valid(combat_panel): return
	var vp = get_viewport()
	if not is_instance_valid(vp): return
	var vp_size    = vp.get_visible_rect().size
	var panel_size = combat_panel.get_combined_minimum_size()
	combat_panel.set_position((vp_size - panel_size) * 0.5)
	combat_panel.set_size(panel_size)

func _open_combat_menu() -> void:
	if is_instance_valid(combat_panel):
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

# ── Styling ───────────────────────────────────────────────────────────────────
func _style_panel() -> void:
	if not is_instance_valid(panel): return
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(12); s.set_border_width_all(2)
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
	s.set_corner_radius_all(8); s.set_border_width_all(1)
	s.border_color = COL_BORDER
	menu_button.add_theme_stylebox_override("normal", s)

# ── Helpers ───────────────────────────────────────────────────────────────────
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

func _combat_ui_popup_is_open() -> bool:
	var combat_ui = get_tree().root.find_child("CombatUI", true, false)
	if is_instance_valid(combat_ui) and "popup_overlay" in combat_ui:
		var overlay = combat_ui.popup_overlay
		if is_instance_valid(overlay) and overlay.visible:
			return true
	return false

func _is_panel_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func _is_combat_menu_open() -> bool:
	return is_instance_valid(combat_panel) and combat_panel.visible

func is_open() -> bool:
	return _is_panel_open() or _is_combat_menu_open()

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# While rebinding, the very next key press becomes the new binding (Esc cancels).
	if _rebinding_action != "" and event is InputEventKey and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		if event.keycode != KEY_ESCAPE:
			var kc = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			KeybindManager.rebind(_rebinding_action, kc)
		_rebinding_action = ""
		_refresh_keybind_labels()
		return

	if get_viewport().is_input_handled():
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.is_echo():
		if _combat_ui_popup_is_open():
			return
		if _is_combat_menu_open():
			_close_combat_menu()
			get_viewport().set_input_as_handled()
			return
		if _is_panel_open():
			if is_instance_valid(keybind_view) and keybind_view.visible:
				_show_main_view(); get_viewport().set_input_as_handled(); return
			if is_instance_valid(confirm_view) and confirm_view.visible:
				_show_main_view(); get_viewport().set_input_as_handled(); return
			if is_instance_valid(load_view) and load_view.visible:
				_show_main_view(); get_viewport().set_input_as_handled(); return
			close_menu(); get_viewport().set_input_as_handled(); return
		if QuestManager.is_in_combat:
			_open_combat_menu(); get_viewport().set_input_as_handled(); return
		if _other_menu_is_open(): return
		open_menu(); get_viewport().set_input_as_handled()

func _on_menu_button_pressed() -> void:
	if _combat_ui_popup_is_open(): return
	if _is_combat_menu_open(): _close_combat_menu(); return
	if _is_panel_open():       close_menu();          return
	if QuestManager.is_in_combat: _open_combat_menu(); return
	if not _other_menu_is_open(): open_menu()

func open_menu() -> void:
	if is_instance_valid(panel): panel.visible = true
	Engine.time_scale = 0.0
	_show_main_view()

func close_menu() -> void:
	if is_instance_valid(panel): panel.visible = false
	Engine.time_scale = 1.0

func _show_main_view() -> void:
	if is_instance_valid(main_view):    main_view.visible    = true
	if is_instance_valid(load_view):    load_view.visible    = false
	if is_instance_valid(confirm_view): confirm_view.visible = false
	if is_instance_valid(keybind_view): keybind_view.visible = false

func _show_load_view() -> void:
	if is_instance_valid(main_view):    main_view.visible    = false
	if is_instance_valid(load_view):    load_view.visible    = true
	if is_instance_valid(confirm_view): confirm_view.visible = false
	if is_instance_valid(keybind_view): keybind_view.visible = false
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
		if is_instance_valid(main_view):    main_view.visible    = false
		if is_instance_valid(load_view):    load_view.visible    = false
		if is_instance_valid(confirm_view): confirm_view.visible = true
		if is_instance_valid(confirm_label):
			confirm_label.text = "Unsaved progress will be lost!\nVisit the Elder NPC to save before returning to the Main Menu."
	else:
		_go_to_main_menu()

# Returning to the Main Menu instead of quitting the whole application —
# resets time scale/combat state first so nothing carries over stale.
func _go_to_main_menu() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

# ── Keybinds view ───────────────────────────────────────────────────────────────
func _build_keybinds_ui() -> void:
	# Insert the "Keybinds" button between Load Game and Main Menu.
	if is_instance_valid(load_button) and is_instance_valid(load_button.get_parent()):
		keybind_button = Button.new()
		keybind_button.text = "⌨  Keybinds"
		keybind_button.focus_mode = Control.FOCUS_NONE
		keybind_button.custom_minimum_size = Vector2(0, 42)
		keybind_button.pressed.connect(_show_keybind_view)
		var p = load_button.get_parent()
		p.add_child(keybind_button)
		p.move_child(keybind_button, load_button.get_index() + 1)

	var host: Node = main_view.get_parent() if is_instance_valid(main_view) else panel
	if not is_instance_valid(host):
		return
	keybind_view = VBoxContainer.new()
	keybind_view.name = "KeybindView"
	keybind_view.visible = false
	keybind_view.add_theme_constant_override("separation", 8)
	keybind_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	host.add_child(keybind_view)

	var title = Label.new()
	title.text = "⌨  Rebind Keys"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	keybind_view.add_child(title)

	var hint = Label.new()
	hint.text = "Click a key, then press the new key. Saved automatically."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.84))
	keybind_view.add_child(hint)

	keybind_rows = {}
	for action in KeybindManager.action_ids():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_lbl = Label.new()
		name_lbl.text = KeybindManager.label_for(action)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		row.add_child(name_lbl)
		var key_btn = Button.new()
		key_btn.focus_mode = Control.FOCUS_NONE
		key_btn.custom_minimum_size = Vector2(170, 34)
		key_btn.text = KeybindManager.key_display(action)
		var a: String = action
		var b: Button = key_btn
		key_btn.pressed.connect(func(): _begin_rebind(a, b))
		row.add_child(key_btn)
		keybind_view.add_child(row)
		keybind_rows[action] = key_btn

	var reset_btn = Button.new()
	reset_btn.text = "↺  Reset to Defaults"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(0, 40)
	reset_btn.pressed.connect(func():
		KeybindManager.reset_defaults()
		_refresh_keybind_labels())
	keybind_view.add_child(reset_btn)

	var back_btn = Button.new()
	back_btn.text = "↩  Back"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.custom_minimum_size = Vector2(0, 40)
	back_btn.pressed.connect(_show_main_view)
	keybind_view.add_child(back_btn)

func _show_keybind_view() -> void:
	if is_instance_valid(main_view):    main_view.visible    = false
	if is_instance_valid(load_view):    load_view.visible    = false
	if is_instance_valid(confirm_view): confirm_view.visible = false
	if is_instance_valid(keybind_view): keybind_view.visible = true
	_rebinding_action = ""
	_refresh_keybind_labels()

func _begin_rebind(action: String, btn: Button) -> void:
	_refresh_keybind_labels()   # clear any other "Press a key…" prompt
	_rebinding_action = action
	if is_instance_valid(btn):
		btn.text = "Press a key…"

func _refresh_keybind_labels() -> void:
	for a in keybind_rows.keys():
		if is_instance_valid(keybind_rows[a]):
			keybind_rows[a].text = KeybindManager.key_display(a)
