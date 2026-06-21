extends CanvasLayer

func _ready() -> void:
	visible = false

	var restart_btn = get_node_or_null("Panel/ColorRect/RestartButton") as Button
	var exit_btn    = get_node_or_null("Panel/ColorRect/ExitButton") as Button
	var title       = get_node_or_null("Panel/ColorRect/Label") as Label

	if is_instance_valid(title):
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color(0.49, 0.837, 0.0, 1.0))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		#title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if is_instance_valid(restart_btn):
		restart_btn.text = "🔄  Play Again"
		_style_btn(restart_btn, Color(0.08, 0.18, 0.08), Color(0.20, 0.60, 0.20))
		restart_btn.pressed.connect(_on_restart_pressed)

	if is_instance_valid(exit_btn):
		exit_btn.text = "🚪  Exit Game"
		_style_btn(exit_btn, Color(0.08, 0.12, 0.22), Color(0.20, 0.35, 0.65))
		exit_btn.pressed.connect(_on_exit_pressed)

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 20; s.content_margin_right = 20
	s.content_margin_top = 12;  s.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate()
	sh.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(220, 52)

func _on_restart_pressed() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	if not QuestManager.load_game(QuestManager.last_used_slot):
		QuestManager.reset_to_defaults()
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().quit()
