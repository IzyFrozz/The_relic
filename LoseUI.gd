extends CanvasLayer

func _ready() -> void:
	visible = false
	# Remove hardcoded scene children — we build at runtime so any resolution works
	for c in get_children():
		c.queue_free()
	_build()

# ── Build full UI in code (resolution-independent) ───────────────────────────
func _build() -> void:
	# Full-screen semi-transparent black overlay
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Centre root — anchors so it always centres regardless of resolution
	var centre_root = Control.new()
	centre_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre_root)

	# Card panel
	var card = Panel.new()
	card.custom_minimum_size = Vector2(560, 400)
	_style_panel(card, Color(0.07, 0.04, 0.04, 0.97), Color(0.55, 0.14, 0.14))
	centre_root.add_child(card)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.set_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical   = Control.GROW_DIRECTION_BOTH

	# Content VBox inside card
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	card.add_child(vbox)

	# Icon
	var icon_lbl = Label.new()
	icon_lbl.text = "💀"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 52)
	vbox.add_child(icon_lbl)

	# Title
	var title = Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.22, 0.22))
	vbox.add_child(title)

	# Subtitle
	var sub = Label.new()
	sub.text = "Your progress is safe with the Elder."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.60, 0.60, 0.72))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# Restart button
	var restart_btn = Button.new()
	restart_btn.text = "🔄  Restart From Last Save"
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(restart_btn, Color(0.08, 0.20, 0.08), Color(0.22, 0.62, 0.22))
	restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_btn)

	# Exit button
	var exit_btn = Button.new()
	exit_btn.text = "🚪  Exit Game"
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(exit_btn, Color(0.22, 0.07, 0.07), Color(0.65, 0.20, 0.20))
	exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(exit_btn)

# ── Style helpers ─────────────────────────────────────────────────────────────
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

# ── Public API ────────────────────────────────────────────────────────────────
func show_death_screen() -> void:
	visible = true

# ── Button handlers ───────────────────────────────────────────────────────────
func _on_restart_pressed() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	if not QuestManager.load_game(QuestManager.last_used_slot):
		QuestManager.reset_to_defaults()
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	get_tree().quit()
