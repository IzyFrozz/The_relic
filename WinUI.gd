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

	# A CenterContainer → PanelContainer → MarginContainer chain, so the card sizes
	# itself to its CONTENT. The old version was a fixed 560x420 Panel with a
	# full-rect VBox inside: the content needs ~480px of height, so the buttons
	# overflowed and drew outside the card's own border.
	var centre_root = CenterContainer.new()
	centre_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre_root)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)   # width only — height follows content
	_style_panel(card, Color(0.04, 0.08, 0.04, 0.97), Color(0.15, 0.55, 0.15))
	centre_root.add_child(card)

	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Real pixel icon rather than an OS emoji glyph. Hidden if the art is missing,
	# so a gap never shows as an empty box.
	var icon_tr = TextureRect.new()
	icon_tr.texture = IconDB.tex("trophy")
	icon_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_tr.custom_minimum_size = Vector2(64, 64)
	icon_tr.visible = icon_tr.texture != null
	vbox.add_child(icon_tr)

	var title = Label.new()
	title.text = "VICTORY!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.40, 0.95, 0.35))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "The relic is safe in the village's hands. Your legend is complete — but the roads still call."
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
	play_again_btn.text = "Continue Playing"
	play_again_btn.focus_mode = Control.FOCUS_NONE
	play_again_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(play_again_btn, Color(0.07, 0.18, 0.07), Color(0.20, 0.62, 0.20))
	play_again_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(play_again_btn)

	var exit_btn = Button.new()
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(340, 58)
	_style_btn(exit_btn, Color(0.08, 0.10, 0.22), Color(0.20, 0.30, 0.65))
	IconDB.decorate_button(exit_btn, "🏠", "Main Menu")
	exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(exit_btn)

# Control, not Panel: the card is a PanelContainer now, and PanelContainer is a
# sibling of Panel rather than a subclass. Both take the "panel" stylebox.
func _style_panel(p: Control, bg: Color, border: Color) -> void:
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
	# Clear the overworld out of the way FIRST. Callers set Engine.time_scale = 0
	# right after this, which freezes any tween still in flight — the relic turn-in
	# left its dialogue box frozen fully-opaque across the card.
	DialogueManager.force_close()
	PromptHUD.visible = false
	visible = true
	SFX.play_victory_music()
	var xp_lbl = find_child("XPEarnedLabel", true, false) as Label
	if is_instance_valid(xp_lbl) and xp_earned > 0:
		xp_lbl.text = "+%d XP earned" % xp_earned

func _on_continue_pressed() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	Engine.time_scale = 1.0
	QuestManager.is_in_combat = false
	get_tree().change_scene_to_file("res://main_menu.tscn")
