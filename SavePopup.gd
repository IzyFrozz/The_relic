extends CanvasLayer

@onready var panel: Panel = find_child("Panel") as Panel
@onready var status_label: Label = find_child("StatusLabel") as Label
@onready var slot1_button: Button = find_child("Slot1Button") as Button
@onready var slot2_button: Button = find_child("Slot2Button") as Button
@onready var slot3_button: Button = find_child("Slot3Button") as Button
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

	for i in range(3):
		var btn = _slot_button(i + 1)
		if is_instance_valid(btn):
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(0, 46)
			var slot_num = i + 1
			btn.pressed.connect(func(): _on_slot_pressed(slot_num))

	if is_instance_valid(back_button):
		back_button.text = "↩  Back Out"
		back_button.focus_mode = Control.FOCUS_NONE
		back_button.custom_minimum_size = Vector2(0, 42)
		back_button.pressed.connect(_on_back_pressed)

	if is_instance_valid(status_label):
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _slot_button(slot: int) -> Button:
	match slot:
		1: return slot1_button
		2: return slot2_button
		3: return slot3_button
	return null


func _refresh_slot_labels() -> void:
	for i in range(3):
		var slot = i + 1
		var btn = _slot_button(slot)
		if not is_instance_valid(btn): continue
		var info = QuestManager.get_slot_info(slot)
		if info.get("exists", false):
			btn.text = "💾  Slot %d — Level %d (Overwrite)" % [slot, info.get("level", 1)]
		else:
			btn.text = "💾  Slot %d — Empty" % slot


func open_popup() -> void:
	visible = true
	_refresh_slot_labels()
	if is_instance_valid(status_label):
		status_label.text = "Choose a slot to save your progress:"
		status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))


func _on_slot_pressed(slot: int) -> void:
	QuestManager.save_game(slot)
	if is_instance_valid(status_label):
		status_label.text = "✅  Saved to Slot %d!" % slot
		status_label.add_theme_color_override("font_color", COL_GREEN)
	_refresh_slot_labels()
	await get_tree().create_timer(0.9).timeout
	visible = false


func _on_back_pressed() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
