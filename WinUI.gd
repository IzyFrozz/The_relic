extends CanvasLayer

func _ready() -> void:
	visible = false
	for c in get_children():
		c.queue_free()
	_build()

func _build() -> void:
	# Full-screen solid black overlay — fully opaque so nothing behind
	# (the overworld's own background colour) bleeds through and tints it.
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var centre_root = Control.new()
	centre_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre_root)

	var card = Panel.new()
	card.custom_minimum_size = Vector2(560, 420)
	_style_panel(card, Color(0.04, 0.08, 0.04, 0.97), Color(0.15, 0.55, 0.15))
	centre_root.add_child(card)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.set_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical   = Control.GROW_DIRECTION_BOTH

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	card.add_child(vbox)

	var icon_lbl = Label.new()
	icon_lbl.text = "🏆"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 52)
	vbox.add_child(icon_lbl)

	var title = Label.new()
	title.text = "VICTORY!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.40, 0.95, 0.35))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "The enemy has fallen. The relic grows stronger."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.62, 0.72, 0.62))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	# XP earned display
	var xp_lbl = Label.new()
	xp_lbl.name = "XPEarnedLabel"
	xp_lbl.text = ""
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_lbl.add_theme_font_size_override("font_size", 18)
	xp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(xp_lbl)

	vbox.add_child(HSeparator.new())

	var play_again_btn = Button.new()
	play_again_btn.text = "🔄  Continue Playing"
	play_again_btn.focus_mode = Control.FOCUS_NONE
	play_again_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(play_again_btn, Color(0.07, 0.18, 0.07), Color(0.20, 0.62, 0.20))
	play_again_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(play_again_btn)

	var exit_btn = Button.new()
	exit_btn.text = "🚪  Exit Game"
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(exit_btn, Color(0.08, 0.10, 0.22), Color(0.20, 0.30, 0.65))
	exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(exit_btn)

func _style_panel(p: Panel, bg: Color, border: Color) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(14); s.set_border_width_all(2)
	s.border_color = border
	p.add_theme_stylebox_override("panel", s)

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(7); s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 24; s.content_margin_right  = 24
	s.content_margin_top  = 14; s.content_margin_bottom = 14
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = bg.lightened(0.16)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))

# Call this after enemy dies so XP earned shows on screen
func show_win_screen(xp_earned: int = 0) -> void:
	visible = true
	var xp_lbl = find_child("XPEarnedLabel", true, false) as Label
	if is_instance_valid(xp_lbl) and xp_earned > 0:
		xp_lbl.text = "✨  +%d XP earned" % xp_earned

func _on_continue_pressed() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().quit()
