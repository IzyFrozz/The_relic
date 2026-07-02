extends CanvasLayer

# ── Main Menu ──────────────────────────────────────────────────────────────
# Entire UI is built in code (same pattern as LoseUI/WinUI) so it's fully
# resolution-independent — no matter the window size/aspect ratio, everything
# stays centred and correctly sized instead of relying on fixed offsets that
# only look right at one resolution.

const MASTER_BUS := 0
const COL_BG      := Color(0.05, 0.06, 0.10, 1.0)
const COL_CARD_BG := Color(0.07, 0.08, 0.12, 0.98)
const COL_BORDER  := Color(0.35, 0.40, 0.60, 1.0)
const COL_GOLD    := Color(1.00, 0.85, 0.30, 1.0)

var main_view:     VBoxContainer
var load_view:      VBoxContainer
var settings_view:  VBoxContainer
var customize_view: VBoxContainer

var name_input:    LineEdit
var width_slider:  HSlider
var height_slider: HSlider
var preview_sprite: TextureRect
var card_panel:    Panel

const PLAYER_TEX_PATH := "res://Asset/sprites/characters/player.png"

var load_slot_buttons: Array = []
var load_status_label: Label

var volume_slider: HSlider
var mute_check:    CheckButton
var fullscreen_check: CheckButton

func _ready() -> void:
	for c in get_children():
		c.queue_free()
	_build()

# ── Build ─────────────────────────────────────────────────────────────────
func _build() -> void:
	# Solid opaque background — this is the very first screen, nothing
	# should ever show through it regardless of resolution.
	var bg = ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var centre_root = Control.new()
	centre_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre_root)

	var card = Panel.new()
	card.custom_minimum_size = Vector2(600, 700)
	card_panel = card
	_style_panel(card, COL_CARD_BG, COL_BORDER)
	centre_root.add_child(card)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.set_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical   = Control.GROW_DIRECTION_BOTH

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 34)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	# ── Placeholder art banner — swap for real key art later ────────────────
	var art_panel = Panel.new()
	art_panel.custom_minimum_size = Vector2(0, 150)
	art_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art_style = StyleBoxFlat.new()
	art_style.bg_color = Color(0.13, 0.14, 0.20, 1.0)
	art_style.set_corner_radius_all(10); art_style.set_border_width_all(2)
	art_style.border_color = Color(0.30, 0.33, 0.48)
	art_panel.add_theme_stylebox_override("panel", art_style)
	vbox.add_child(art_panel)
	var art_label = Label.new()
	art_label.text = "🖼️\nArtwork Placeholder"
	art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	art_label.add_theme_font_size_override("font_size", 16)
	art_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.62))
	art_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_panel.add_child(art_label)

	# ── Title ────────────────────────────────────────────────────────────────
	var title = Label.new()
	title.text = "⚔️  THE RELIC"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", COL_GOLD)
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "A JRPG Adventure"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.60, 0.62, 0.75))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# ── Views container — only one of these three is visible at a time ─────
	main_view = VBoxContainer.new()
	main_view.add_theme_constant_override("separation", 12)
	main_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(main_view)
	_build_main_view()

	load_view = VBoxContainer.new()
	load_view.visible = false
	load_view.add_theme_constant_override("separation", 12)
	load_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(load_view)
	_build_load_view()

	settings_view = VBoxContainer.new()
	settings_view.visible = false
	settings_view.add_theme_constant_override("separation", 14)
	settings_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(settings_view)
	_build_settings_view()

	customize_view = VBoxContainer.new()
	customize_view.visible = false
	customize_view.add_theme_constant_override("separation", 12)
	customize_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(customize_view)
	_build_customize_view()

# ── Main view ────────────────────────────────────────────────────────────────
func _build_main_view() -> void:
	var start_btn = Button.new()
	start_btn.text = "▶  Start New Game"
	_style_btn(start_btn, Color(0.07, 0.18, 0.07), Color(0.20, 0.62, 0.20))
	start_btn.pressed.connect(func(): _show_view("customize"))
	main_view.add_child(start_btn)

	var load_btn = Button.new()
	load_btn.text = "📂  Load Game"
	_style_btn(load_btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
	load_btn.pressed.connect(func(): _show_view("load"))
	main_view.add_child(load_btn)

	var settings_btn = Button.new()
	settings_btn.text = "⚙️  Settings"
	_style_btn(settings_btn, Color(0.14, 0.12, 0.05), Color(0.62, 0.52, 0.20))
	settings_btn.pressed.connect(func(): _show_view("settings"))
	main_view.add_child(settings_btn)

	var exit_btn = Button.new()
	exit_btn.text = "🚪  Exit Game"
	_style_btn(exit_btn, Color(0.22, 0.07, 0.07), Color(0.65, 0.20, 0.20))
	exit_btn.pressed.connect(func(): get_tree().quit())
	main_view.add_child(exit_btn)

# ── Load view ────────────────────────────────────────────────────────────────
func _build_load_view() -> void:
	load_status_label = Label.new()
	load_status_label.text = "Choose a slot to load:"
	load_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	load_view.add_child(load_status_label)

	load_slot_buttons.clear()
	for i in range(3):
		var slot = i + 1
		var btn = Button.new()
		_style_btn(btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
		btn.pressed.connect(func(): _on_load_slot_pressed(slot))
		load_view.add_child(btn)
		load_slot_buttons.append(btn)

	var back_btn = Button.new()
	back_btn.text = "↩  Back"
	_style_btn(back_btn, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back_btn.pressed.connect(func(): _show_view("main"))
	load_view.add_child(back_btn)

# ── Settings view ──────────────────────────────────────────────────────────
func _build_settings_view() -> void:
	var audio_lbl = Label.new()
	audio_lbl.text = "🔊  Audio"
	settings_view.add_child(audio_lbl)

	volume_slider = HSlider.new()
	volume_slider.custom_minimum_size = Vector2(0, 24)
	volume_slider.min_value = 0.0; volume_slider.max_value = 1.0; volume_slider.step = 0.01
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS))
	volume_slider.value_changed.connect(func(v): AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(v)))
	settings_view.add_child(volume_slider)

	mute_check = CheckButton.new()
	mute_check.text = "Mute"
	mute_check.button_pressed = AudioServer.is_bus_mute(MASTER_BUS)
	mute_check.toggled.connect(func(p): AudioServer.set_bus_mute(MASTER_BUS, p))
	settings_view.add_child(mute_check)

	var display_lbl = Label.new()
	display_lbl.text = "🖥️  Display"
	settings_view.add_child(display_lbl)

	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(func(p):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if p else DisplayServer.WINDOW_MODE_WINDOWED))
	settings_view.add_child(fullscreen_check)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_view.add_child(spacer)

	var back_btn = Button.new()
	back_btn.text = "↩  Back"
	_style_btn(back_btn, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back_btn.pressed.connect(func(): _show_view("main"))
	settings_view.add_child(back_btn)

# ── Character creation ───────────────────────────────────────────────────────
func _build_customize_view() -> void:
	var title = Label.new()
	title.text = "🧙  Create Your Hero"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_GOLD)
	customize_view.add_child(title)

	# ── Live character preview ──
	var preview_box = Panel.new()
	preview_box.custom_minimum_size = Vector2(0, 116)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.10, 0.12, 0.18, 1.0)
	pstyle.set_corner_radius_all(8); pstyle.set_border_width_all(2)
	pstyle.border_color = Color(0.30, 0.33, 0.48)
	preview_box.add_theme_stylebox_override("panel", pstyle)
	customize_view.add_child(preview_box)

	var preview_center = CenterContainer.new()
	preview_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_box.add_child(preview_center)

	preview_sprite = TextureRect.new()
	var atlas = AtlasTexture.new()
	atlas.atlas = load(PLAYER_TEX_PATH)
	atlas.region = Rect2(0, 144, 48, 48)   # a front-facing idle frame
	preview_sprite.texture = atlas
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels
	# STRETCH_SCALE so the size (driven by the sliders) distorts the sprite,
	# previewing the exact width/height build the player picked.
	preview_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	preview_center.add_child(preview_sprite)

	var name_cap = Label.new()
	name_cap.text = "Name  (permanent for this run)"
	name_cap.add_theme_color_override("font_color", Color(0.8, 0.82, 0.92))
	customize_view.add_child(name_cap)

	name_input = LineEdit.new()
	name_input.placeholder_text = "Enter your hero's name…"
	name_input.text = "Hero"
	name_input.max_length = 16
	name_input.custom_minimum_size = Vector2(0, 44)
	customize_view.add_child(name_input)

	var build_cap = Label.new()
	build_cap.text = "Build"
	build_cap.add_theme_color_override("font_color", Color(0.8, 0.82, 0.92))
	customize_view.add_child(build_cap)

	width_slider  = _build_stat_slider("Width", customize_view)
	height_slider = _build_stat_slider("Height", customize_view)

	var confirm = Button.new()
	confirm.text = "▶  Begin Adventure"
	_style_btn(confirm, Color(0.07, 0.18, 0.07), Color(0.20, 0.62, 0.20))
	confirm.pressed.connect(_on_confirm_customize)
	customize_view.add_child(confirm)

	var back = Button.new()
	back.text = "↩  Back"
	_style_btn(back, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back.pressed.connect(func(): _show_view("main"))
	customize_view.add_child(back)

	_update_preview()

func _build_stat_slider(caption: String, parent: Node) -> HSlider:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap = Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(70, 0)
	cap.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	row.add_child(cap)
	var slider = HSlider.new()
	# Subtle stretch — noticeable but never too distorted.
	slider.min_value = 0.9; slider.max_value = 1.1; slider.step = 0.02; slider.value = 1.0
	slider.custom_minimum_size = Vector2(0, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(_v): _update_preview())
	row.add_child(slider)
	parent.add_child(row)
	return slider

func _update_preview() -> void:
	if not is_instance_valid(preview_sprite):
		return
	var w = width_slider.value if is_instance_valid(width_slider) else 1.0
	var h = height_slider.value if is_instance_valid(height_slider) else 1.0
	# Size-driven (not scale) so the container lays it out reliably.
	preview_sprite.custom_minimum_size = Vector2(48.0 * w, 48.0 * h) * 1.9

func _on_confirm_customize() -> void:
	QuestManager.reset_to_defaults()
	var nm = name_input.text.strip_edges()
	QuestManager.player_name = nm if nm != "" else "Hero"
	QuestManager.player_scale_x = width_slider.value
	QuestManager.player_scale_y = height_slider.value
	QuestManager.play_time_seconds = 0.0
	QuestManager.is_in_combat = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://main.tscn")

# ── View switching ───────────────────────────────────────────────────────────
func _show_view(which: String) -> void:
	main_view.visible     = which == "main"
	load_view.visible     = which == "load"
	settings_view.visible = which == "settings"
	customize_view.visible = which == "customize"
	# The customize view has more content — grow the card so nothing spills out.
	if is_instance_valid(card_panel):
		card_panel.custom_minimum_size.y = 880 if which == "customize" else 700
	if which == "customize":
		_update_preview()
	if which == "load":
		_refresh_load_slots()
		load_status_label.text = "Choose a slot to load:"
		load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))

func _refresh_load_slots() -> void:
	for i in range(3):
		var slot = i + 1
		var btn = load_slot_buttons[i] as Button
		if not is_instance_valid(btn): continue
		var info = QuestManager.get_slot_info(slot)
		if info.get("exists", false):
			btn.text = "Slot %d — Level %d" % [slot, info.get("level", 1)]
			btn.disabled = false
		else:
			btn.text = "Slot %d — Empty" % slot
			btn.disabled = true

# ── Actions ──────────────────────────────────────────────────────────────────
func _on_start_new_pressed() -> void:
	QuestManager.reset_to_defaults()
	QuestManager.play_time_seconds = 0.0
	QuestManager.is_in_combat = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://main.tscn")

func _on_load_slot_pressed(slot: int) -> void:
	if QuestManager.load_game(slot):
		Engine.time_scale = 1.0
		QuestManager.is_in_combat = false
		get_tree().change_scene_to_file("res://main.tscn")
	else:
		load_status_label.text = "⚠️  Slot %d is empty!" % slot
		load_status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))

# ── Style helpers ──────────────────────────────────────────────────────────
func _style_panel(p: Panel, bg: Color, border: Color) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(14); s.set_border_width_all(2)
	s.border_color = border
	p.add_theme_stylebox_override("panel", s)

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 54)
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(7); s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 20; s.content_margin_right  = 20
	s.content_margin_top  = 12; s.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = bg.lightened(0.16)
	btn.add_theme_stylebox_override("hover", sh)
	var sd = s.duplicate(); sd.bg_color = bg.darkened(0.35); sd.border_color = border.darkened(0.4)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
