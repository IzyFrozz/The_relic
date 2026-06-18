extends CanvasLayer

@onready var panel: Panel = find_child("Panel") as Panel
@onready var status_label: Label = find_child("StatusLabel") as Label
@onready var save_button: Button = find_child("SaveButton") as Button
@onready var back_button: Button = find_child("BackButton") as Button

const COL_BG := Color(0.07, 0.08, 0.12, 0.97)
const COL_BORDER := Color(0.35, 0.55, 0.95)
const COL_GREEN := Color(0.45, 0.85, 0.45)


func _ready() -> void:
	visible = false

	if is_instance_valid(panel):
		var s = StyleBoxFlat.new()
		s.bg_color = COL_BG
		s.set_corner_radius_all(12)
		s.set_border_width_all(2)
		s.border_color = COL_BORDER
		panel.add_theme_stylebox_override("panel", s)

	if is_instance_valid(save_button):
		save_button.text = "💾  Save Game"
		save_button.focus_mode = Control.FOCUS_NONE
		save_button.pressed.connect(_on_save_pressed)

	if is_instance_valid(back_button):
		back_button.text = "↩  Back Out"
		back_button.focus_mode = Control.FOCUS_NONE
		back_button.pressed.connect(_on_back_pressed)

	if is_instance_valid(status_label):
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func open_popup() -> void:
	visible = true
	if is_instance_valid(status_label):
		status_label.text = "Would you like to save your progress?"
		status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))


func _on_save_pressed() -> void:
	QuestManager.save_game()
	if is_instance_valid(status_label):
		status_label.text = "✅  Game Saved!"
		status_label.add_theme_color_override("font_color", COL_GREEN)
	await get_tree().create_timer(0.9).timeout
	visible = false


func _on_back_pressed() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
