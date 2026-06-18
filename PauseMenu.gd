extends CanvasLayer

@onready var panel: Panel = find_child("Panel") as Panel
@onready var main_view: Control = find_child("MainView") as Control
@onready var confirm_view: Control = find_child("ConfirmView") as Control

@onready var volume_slider: HSlider = find_child("VolumeSlider") as HSlider
@onready var mute_check: CheckButton = find_child("MuteCheck") as CheckButton
@onready var fullscreen_check: CheckButton = find_child("FullscreenCheck") as CheckButton

@onready var resume_button: Button = find_child("ResumeButton") as Button
@onready var exit_button: Button = find_child("ExitButton") as Button

@onready var confirm_label: Label = find_child("ConfirmLabel") as Label
@onready var save_exit_button: Button = find_child("SaveExitButton") as Button
@onready var exit_no_save_button: Button = find_child("ExitNoSaveButton") as Button
@onready var cancel_exit_button: Button = find_child("CancelExitButton") as Button

const COL_BG := Color(0.06, 0.07, 0.11, 0.97)
const COL_BORDER := Color(0.35, 0.40, 0.55)
const MASTER_BUS := 0


func _ready() -> void:
	visible = false
	_style_panel()
	_style_buttons()

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

	if is_instance_valid(exit_button):
		exit_button.text = "🚪  Exit to Desktop"
		exit_button.pressed.connect(_on_exit_pressed)

	if is_instance_valid(save_exit_button):
		save_exit_button.text = "💾  Save & Exit"
		save_exit_button.pressed.connect(_on_save_and_exit_pressed)

	if is_instance_valid(exit_no_save_button):
		exit_no_save_button.text = "⚠️  Exit Without Saving"
		exit_no_save_button.pressed.connect(func(): get_tree().quit())

	if is_instance_valid(cancel_exit_button):
		cancel_exit_button.text = "Cancel"
		cancel_exit_button.pressed.connect(_show_main_view)

	if is_instance_valid(confirm_view):
		confirm_view.visible = false


func _style_panel() -> void:
	if not is_instance_valid(panel): return
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = COL_BORDER
	panel.add_theme_stylebox_override("panel", s)


func _style_buttons() -> void:
	for btn in [resume_button, exit_button, save_exit_button, exit_no_save_button, cancel_exit_button]:
		if not is_instance_valid(btn): continue
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 42)


func _other_menu_is_open() -> bool:
	for n in ["EquipmentMenu", "RoadmapPopup", "SavePopup"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node.visible:
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.is_echo():
		if visible:
			close_menu()
			get_viewport().set_input_as_handled()
			return
		if _other_menu_is_open() or QuestManager.is_in_combat:
			return
		open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	Engine.time_scale = 0.0
	_show_main_view()


func close_menu() -> void:
	visible = false
	Engine.time_scale = 1.0


func _show_main_view() -> void:
	if is_instance_valid(main_view): main_view.visible = true
	if is_instance_valid(confirm_view): confirm_view.visible = false


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
		if is_instance_valid(confirm_view): confirm_view.visible = true
		if is_instance_valid(confirm_label):
			confirm_label.text = "Unsaved progress will be lost. Exit anyway?"
	else:
		get_tree().quit()


func _on_save_and_exit_pressed() -> void:
	QuestManager.save_game()
	get_tree().quit()
