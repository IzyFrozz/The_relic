extends CanvasLayer

# ── Main Menu ──────────────────────────────────────────────────────────────
# Entire UI is built in code (same pattern as LoseUI/WinUI) so it's fully
# resolution-independent — no matter the window size/aspect ratio, everything
# stays centred and correctly sized instead of relying on fixed offsets that
# only look right at one resolution.

const MASTER_BUS := 0
const CARD_MARGIN_Y := 40.0   # gap between the card and the top/bottom of the window
const COL_BG      := Color(0.05, 0.06, 0.10, 1.0)
const COL_CARD_BG := Color(0.07, 0.08, 0.12, 0.98)
const COL_BORDER  := Color(0.35, 0.40, 0.60, 1.0)
const COL_GOLD    := Color(1.00, 0.85, 0.30, 1.0)

var main_view:     VBoxContainer
var load_view:      VBoxContainer
var settings_view:  VBoxContainer   # hub: Audio / Display / Controls
var audio_view:     VBoxContainer
var display_view:   VBoxContainer
var controls_view:  VBoxContainer
var customize_view: VBoxContainer
var _current_view: String = "main"   # drives Esc's "step back one screen"

var name_input:    LineEdit
var width_slider:  HSlider
var height_slider: HSlider
var preview_sprites: Array[Sprite2D] = []   # 4 direction previews (down/up/left/right), inside a SubViewport
var card_panel:    Panel
var hair_picker:  ColorPickerButton
var shirt_picker: ColorPickerButton
var pants_picker: ColorPickerButton
var shoes_picker: ColorPickerButton
var skin_picker:  ColorPickerButton
var _preview_mat:  ShaderMaterial

const PLAYER_TEX_PATH := "res://Asset/sprites/characters/player.png"
const PlayerSkin = preload("res://PlayerSkin.gd")

var load_slot_buttons: Array = []
var load_status_label: Label
var _delete_armed_slot: int = 0   # which session's Delete is armed for confirm (0 = none)
# The "load_view" doubles as the SESSION picker. Mode is "new" (pick an empty
# session for a freshly-created character) or "load" (pick an occupied session
# to browse its saves).
var _session_mode: String = "load"
var _selected_session: int = 0    # session chosen in load mode, for the save picker

# Save-slot picker (a chosen session's 3 checkpoints, load mode only).
var saveselect_view: VBoxContainer
var saveselect_buttons: Array = []
var saveselect_status: Label

var volume_slider: HSlider
var mute_check:    CheckButton
var fullscreen_check: CheckButton

# Keybind rebinding (shares KeybindManager with the in-game pause menu, so a
# rebind set here in the main menu carries into the game and persists).
var keybind_rows: Dictionary = {}
var _rebinding_action: String = ""

const CURSOR_TEX := preload("res://Asset/UI Elements/Cursors/Cursor_01.png")

func _ready() -> void:
	# Swap the OS pointer for the pack's themed cursor. set_custom_mouse_cursor is
	# global and persists across every scene, so setting it once at the menu (the
	# game's boot scene) themes the cursor for the whole session.
	Input.set_custom_mouse_cursor(CURSOR_TEX, Input.CURSOR_ARROW, Vector2(3, 2))
	for c in get_children():
		c.queue_free()
	_build()
	SFX.play_menu_music()

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

	# The card is ANCHORED to the viewport with a fixed margin rather than sized to
	# its content. The tall screens (Create Your Hero, Controls) need far more room
	# than a 1080p window has, and growing the card to fit simply pushed the bottom
	# of the content off the screen — the content scrolls inside the card instead.
	var card = Panel.new()
	card.custom_minimum_size = Vector2(600, 0)
	card_panel = card
	_style_panel(card, COL_CARD_BG, COL_BORDER)
	centre_root.add_child(card)
	# Horizontally centred at a fixed 600 wide; vertically it spans the window
	# minus a margin, so the card is always exactly as tall as there is room for.
	card.anchor_left = 0.5;  card.anchor_right  = 0.5
	card.anchor_top  = 0.0;  card.anchor_bottom = 1.0
	card.offset_left = -300; card.offset_right  = 300
	card.offset_top  = CARD_MARGIN_Y
	card.offset_bottom = -CARD_MARGIN_Y
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 34)
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
	art_label.text = "Artwork Placeholder"
	art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	art_label.add_theme_font_size_override("font_size", 16)
	art_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.62))
	art_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_panel.add_child(art_label)

	# ── Title ────────────────────────────────────────────────────────────────
	var title = RichTextLabel.new()
	title.bbcode_enabled = true; title.fit_content = true; title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("normal_font_size", 40)
	title.add_theme_color_override("default_color", COL_GOLD)
	title.text = IconDB.iconify("⚔️  THE RELIC", 42)
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "A JRPG Adventure"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.60, 0.62, 0.75))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# Every view lives inside this scroll, so a screen taller than the window
	# scrolls instead of spilling past the card's bottom edge.
	var views_scroll = ScrollContainer.new()
	views_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	views_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(views_scroll)
	var views_holder = VBoxContainer.new()
	views_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views_scroll.add_child(views_holder)

	# ── Views container — only one of these three is visible at a time ─────
	main_view = VBoxContainer.new()
	main_view.add_theme_constant_override("separation", 12)
	main_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(main_view)
	_build_main_view()

	load_view = VBoxContainer.new()
	load_view.visible = false
	load_view.add_theme_constant_override("separation", 12)
	load_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(load_view)
	_build_load_view()

	settings_view = VBoxContainer.new()
	settings_view.visible = false
	settings_view.add_theme_constant_override("separation", 14)
	settings_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(settings_view)
	_build_settings_view()

	# Each settings section is its own screen with its own Back button, so nothing
	# spills off the bottom of the card.
	audio_view = VBoxContainer.new()
	audio_view.visible = false
	audio_view.add_theme_constant_override("separation", 14)
	audio_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(audio_view)
	_build_audio_view()

	display_view = VBoxContainer.new()
	display_view.visible = false
	display_view.add_theme_constant_override("separation", 14)
	display_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(display_view)
	_build_display_view()

	controls_view = VBoxContainer.new()
	controls_view.visible = false
	controls_view.add_theme_constant_override("separation", 10)
	controls_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(controls_view)
	_build_controls_view()

	customize_view = VBoxContainer.new()
	customize_view.visible = false
	customize_view.add_theme_constant_override("separation", 12)
	customize_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(customize_view)
	_build_customize_view()

	saveselect_view = VBoxContainer.new()
	saveselect_view.visible = false
	saveselect_view.add_theme_constant_override("separation", 12)
	saveselect_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views_holder.add_child(saveselect_view)
	_build_saveselect_view()

# ── Main view ────────────────────────────────────────────────────────────────
func _build_main_view() -> void:
	var start_btn = Button.new()
	start_btn.text = "▶  Start New Game"
	_style_btn(start_btn, Color(0.07, 0.18, 0.07), Color(0.20, 0.62, 0.20))
	start_btn.pressed.connect(func(): _show_view("customize"))
	main_view.add_child(start_btn)

	var load_btn = Button.new()
	_style_btn(load_btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
	IconDB.decorate_button(load_btn, "📂", "Load Game")
	load_btn.pressed.connect(func(): _session_mode = "load"; _show_view("session"))
	main_view.add_child(load_btn)

	var settings_btn = Button.new()
	_style_btn(settings_btn, Color(0.14, 0.12, 0.05), Color(0.62, 0.52, 0.20))
	IconDB.decorate_button(settings_btn, "⚙️", "Settings")
	settings_btn.pressed.connect(func(): _show_view("settings"))
	main_view.add_child(settings_btn)

	var exit_btn = Button.new()
	_style_btn(exit_btn, Color(0.22, 0.07, 0.07), Color(0.65, 0.20, 0.20))
	IconDB.decorate_button(exit_btn, "🚪", "Exit Game")
	exit_btn.pressed.connect(func(): get_tree().quit())
	main_view.add_child(exit_btn)

# ── Session picker (load_view) — used for both New Game and Load ──────────────
func _build_load_view() -> void:
	load_status_label = Label.new()
	load_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	load_view.add_child(load_status_label)

	load_slot_buttons.clear()
	for i in range(3):
		var session = i + 1
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		load_view.add_child(row)
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
		btn.pressed.connect(func(): _on_session_pressed(session))
		row.add_child(btn)
		load_slot_buttons.append(btn)
		# Per-session "delete" button (two-click confirm via the status line).
		var del = Button.new()
		del.text = "Delete"
		del.focus_mode = Control.FOCUS_NONE
		del.custom_minimum_size = Vector2(58, 0)
		_style_btn(del, Color(0.22, 0.09, 0.09), Color(0.70, 0.25, 0.25))
		del.pressed.connect(func(): _on_delete_session_pressed(session))
		row.add_child(del)

	var back_btn = Button.new()
	back_btn.text = "↩  Back"
	_style_btn(back_btn, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back_btn.pressed.connect(func(): _show_view("main"))
	load_view.add_child(back_btn)

func _refresh_session_slots() -> void:
	for i in range(3):
		var session = i + 1
		var btn = load_slot_buttons[i] as Button
		if not is_instance_valid(btn): continue
		var occupied := QuestManager.session_occupied(session)
		if occupied:
			btn.text = "Session %d — Lv. %d" % [session, QuestManager.session_level(session)]
			# New game needs an EMPTY session; load needs an OCCUPIED one.
			btn.disabled = _session_mode == "new"
		else:
			btn.text = "Session %d — Empty%s" % [session, "  (start here)" if _session_mode == "new" else ""]
			btn.disabled = _session_mode == "load"
		btn.modulate.a = 1.0 if not btn.disabled else 0.5

func _on_session_pressed(session: int) -> void:
	if _session_mode == "new":
		if QuestManager.session_occupied(session):
			return   # occupied sessions are disabled for new games (delete to free)
		QuestManager.start_new_session(session)   # character already set by customize
		QuestManager.play_time_seconds = 0.0
		QuestManager.is_in_combat = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://main.tscn")
	else:
		if not QuestManager.session_occupied(session):
			return
		_selected_session = session
		_show_view("saveselect")

func _on_delete_session_pressed(session: int) -> void:
	if not QuestManager.session_occupied(session):
		_delete_armed_slot = 0
		load_status_label.text = "Session %d is already empty." % session
		load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
		return
	if _delete_armed_slot != session:
		_delete_armed_slot = session
		load_status_label.text = "Delete ALL of Session %d's saves? Press Delete again to confirm." % session
		load_status_label.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4))
		return
	QuestManager.delete_session(session)
	_delete_armed_slot = 0
	_refresh_session_slots()
	load_status_label.text = "Session %d deleted." % session
	load_status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))

# ── Save-slot picker (a chosen session's 3 checkpoints) ───────────────────────
func _build_saveselect_view() -> void:
	saveselect_status = Label.new()
	saveselect_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saveselect_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	saveselect_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	saveselect_view.add_child(saveselect_status)

	saveselect_buttons.clear()
	for i in range(3):
		var slot = i + 1
		var btn = Button.new()
		_style_btn(btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
		btn.pressed.connect(func(): _on_saveselect_pressed(slot))
		saveselect_view.add_child(btn)
		saveselect_buttons.append(btn)

	var back_btn = Button.new()
	back_btn.text = "↩  Back to sessions"
	_style_btn(back_btn, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back_btn.pressed.connect(func(): _show_view("session"))
	saveselect_view.add_child(back_btn)

func _refresh_saveselect() -> void:
	saveselect_status.text = "Session %d — choose a save to load:" % _selected_session
	for i in range(3):
		var slot = i + 1
		var btn = saveselect_buttons[i] as Button
		if not is_instance_valid(btn): continue
		var info = QuestManager.save_slot_info(_selected_session, slot)
		if info.get("exists", false):
			btn.text = "Slot %d — Level %d" % [slot, info.get("level", 1)]
			btn.disabled = false
			btn.modulate.a = 1.0
		else:
			btn.text = "Slot %d — Empty" % slot
			btn.disabled = true
			btn.modulate.a = 0.5

func _on_saveselect_pressed(slot: int) -> void:
	if QuestManager.load_from(_selected_session, slot):
		Engine.time_scale = 1.0
		QuestManager.is_in_combat = false
		get_tree().change_scene_to_file("res://main.tscn")
	load_status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))

# ── Settings view ──────────────────────────────────────────────────────────
# One "Caption ▬▬▬ 80%" row wired to a mix bus via SFX (persists automatically).
# Takes an explicit parent — it must land in the Audio view, not the Settings hub.
func _add_audio_slider(parent: Node, caption: String, bus: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl = Label.new()
	lbl.text = caption
	lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(lbl)
	var s = HSlider.new()
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.min_value = 0.0; s.max_value = 1.0; s.step = 0.01
	# Seed from the live bus BEFORE connecting, so the handle shows the real level
	# and the connect doesn't fire a spurious save.
	s.value = SFX.get_bus_linear(bus)
	row.add_child(s)
	var pct = Label.new()
	pct.custom_minimum_size = Vector2(50, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % roundi(s.value * 100.0)
	row.add_child(pct)
	s.value_changed.connect(func(v):
		SFX.set_bus_linear(bus, v)
		pct.text = "%d%%" % roundi(v * 100.0))
	parent.add_child(row)

# A section heading inside one of the settings sub-views.
# RichTextLabel, not Label: only RichTextLabel can render the [img] tags that
# IconDB.iconify() produces. A plain Label falls back to the OS colour-emoji font,
# which is exactly the mismatched glyph this project is trying to be rid of.
func _section_title(parent: Node, text: String) -> void:
	var l = RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("normal_font_size", 22)
	l.add_theme_color_override("default_color", COL_GOLD)
	l.text = IconDB.iconify(text, 24)
	parent.add_child(l)

# "↩ Back" that returns to the settings hub (cancels any in-progress rebind).
func _add_back_to_settings(parent: Node) -> void:
	var b = Button.new()
	b.text = "↩  Back"
	_style_btn(b, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	b.pressed.connect(func():
		_rebinding_action = ""
		_refresh_keybind_labels()
		_show_view("settings"))
	parent.add_child(b)

# ── Settings hub: just picks a section (each opens its own screen) ──────────────
func _build_settings_view() -> void:
	_section_title(settings_view, "⚙️  Settings")

	var audio_btn = Button.new()
	_style_btn(audio_btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
	IconDB.decorate_button(audio_btn, "🔊", "Audio")
	audio_btn.pressed.connect(func(): _show_view("audio"))
	settings_view.add_child(audio_btn)

	var display_btn = Button.new()
	display_btn.text = "Display"
	_style_btn(display_btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
	display_btn.pressed.connect(func(): _show_view("display"))
	settings_view.add_child(display_btn)

	var controls_btn = Button.new()
	controls_btn.text = "⌨  Controls"
	_style_btn(controls_btn, Color(0.09, 0.12, 0.20), Color(0.30, 0.42, 0.75))
	controls_btn.pressed.connect(func(): _show_view("controls"))
	settings_view.add_child(controls_btn)

	settings_view.add_child(HSeparator.new())
	_add_difficulty_picker(settings_view)

	var back_btn = Button.new()
	back_btn.text = "↩  Back"
	_style_btn(back_btn, Color(0.12, 0.12, 0.14), Color(0.40, 0.40, 0.48))
	back_btn.pressed.connect(func(): _show_view("main"))
	settings_view.add_child(back_btn)

# ── Audio section ───────────────────────────────────────────────────────────────
func _build_audio_view() -> void:
	_section_title(audio_view, "🔊  Audio")

	var hint = Label.new()
	hint.text = "Set each channel's level. Saved automatically."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
	audio_view.add_child(hint)

	# One labelled slider per mix bus, driven by SFX (persists to user://audio.cfg).
	_add_audio_slider(audio_view, "Master", "Master")
	_add_audio_slider(audio_view, "Music",  "Music")
	_add_audio_slider(audio_view, "SFX",    "SFX")

	mute_check = CheckButton.new()
	mute_check.text = "Mute All"
	mute_check.button_pressed = SFX.is_master_muted()
	mute_check.toggled.connect(func(p): SFX.set_master_mute(p))
	audio_view.add_child(mute_check)

	_add_back_to_settings(audio_view)

# ── Display section ─────────────────────────────────────────────────────────────
func _build_display_view() -> void:
	_section_title(display_view, "Display")

	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(func(p):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if p else DisplayServer.WINDOW_MODE_WINDOWED))
	display_view.add_child(fullscreen_check)

	_add_back_to_settings(display_view)

# ── Controls section ────────────────────────────────────────────────────────────
func _build_controls_view() -> void:
	_section_title(controls_view, "⌨  Controls")

	var kb_hint = Label.new()
	kb_hint.text = "Click a key, then press the new key. Saved automatically."
	kb_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kb_hint.add_theme_font_size_override("font_size", 11)
	kb_hint.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
	controls_view.add_child(kb_hint)

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
		key_btn.custom_minimum_size = Vector2(150, 30)
		key_btn.text = KeybindManager.key_display(action)
		var a: String = action
		var b: Button = key_btn
		key_btn.pressed.connect(func(): _begin_rebind(a, b))
		row.add_child(key_btn)
		controls_view.add_child(row)
		keybind_rows[action] = key_btn

	var reset_btn = Button.new()
	reset_btn.text = "↺  Reset Keys to Defaults"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(0, 34)
	reset_btn.pressed.connect(func():
		KeybindManager.reset_defaults()
		_refresh_keybind_labels())
	controls_view.add_child(reset_btn)

	_add_back_to_settings(controls_view)

# ── Keybind rebinding ────────────────────────────────────────────────────────
func _begin_rebind(action: String, btn: Button) -> void:
	_refresh_keybind_labels()   # clear any other "Press a key…" prompt
	_rebinding_action = action
	if is_instance_valid(btn):
		btn.text = "Press a key…"

func _refresh_keybind_labels() -> void:
	for a in keybind_rows.keys():
		if is_instance_valid(keybind_rows[a]):
			keybind_rows[a].text = KeybindManager.key_display(a)

func _input(event: InputEvent) -> void:
	# While rebinding, the next key press IS the new binding (Esc cancels).
	if _rebinding_action != "":
		if event is InputEventKey and event.pressed and not event.is_echo():
			get_viewport().set_input_as_handled()
			var kc: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if event.keycode != KEY_ESCAPE:   # Esc cancels the rebind
				KeybindManager.rebind(_rebinding_action, kc)
				SFX.play(SFX.ui_rebind)
			_rebinding_action = ""
			_refresh_keybind_labels()
		return

	# Esc steps back one screen, so you're never stranded on a sub-view.
	if event is InputEventKey and event.pressed and not event.is_echo() \
			and event.keycode == KEY_ESCAPE:
		var back := {
			"audio": "settings", "display": "settings", "controls": "settings",
			"settings": "main", "session": "main", "customize": "main",
			"saveselect": "session",
		}
		if back.has(_current_view):
			get_viewport().set_input_as_handled()
			SFX.play(SFX.ui_cancel)
			_show_view(back[_current_view])

# ── Character creation ───────────────────────────────────────────────────────
func _build_customize_view() -> void:
	var title = RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("normal_font_size", 20)
	title.add_theme_color_override("default_color", COL_GOLD)
	title.text = IconDB.iconify("🧙  Create Your Hero", 24)
	customize_view.add_child(title)

	# ── Live character preview ──
	var preview_box = Panel.new()
	preview_box.custom_minimum_size = Vector2(0, 168)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.10, 0.12, 0.18, 1.0)
	pstyle.set_corner_radius_all(8); pstyle.set_border_width_all(2)
	pstyle.border_color = Color(0.30, 0.33, 0.48)
	preview_box.add_theme_stylebox_override("panel", pstyle)
	customize_view.add_child(preview_box)

	var preview_center = CenterContainer.new()
	preview_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_box.add_child(preview_center)

	# The recolor shader needs the group mask aligned to the sprite 1:1, which
	# only holds for Node2D sprites (sheet-normalized UV) — a TextureRect with an
	# AtlasTexture gives region-local UV and the mask misaligns (no recolor). So
	# the four direction previews are Sprite2D nodes rendered inside a SubViewport.
	const VW := 452
	const VH := 150
	var svc := SubViewportContainer.new()
	svc.stretch = false
	svc.custom_minimum_size = Vector2(VW, VH)
	preview_center.add_child(svc)
	var sv := SubViewport.new()
	sv.size = Vector2i(VW, VH)
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)

	# One shared recolor material drives all four direction previews at once.
	_preview_mat = PlayerSkin.make_material(PlayerSkin.DEF_HAIR, PlayerSkin.DEF_SHIRT, PlayerSkin.DEF_PANTS, PlayerSkin.DEF_SHOES, PlayerSkin.DEF_SKIN)
	var player_tex = load(PLAYER_TEX_PATH)
	# Down / Up / Left / Right idle frames (left = the side frame mirrored).
	var dirs = [
		{ "region": Rect2(0, 144, 48, 48), "flip": false },   # Down (front)
		{ "region": Rect2(0,  96, 48, 48), "flip": false },   # Up (back)
		{ "region": Rect2(0,  48, 48, 48), "flip": true  },   # Left (side, mirrored)
		{ "region": Rect2(0,  48, 48, 48), "flip": false },   # Right (side)
	]
	preview_sprites.clear()
	for i in dirs.size():
		var dcfg = dirs[i]
		var spr = Sprite2D.new()
		spr.texture = player_tex
		spr.region_enabled = true
		spr.region_rect = dcfg["region"]
		spr.flip_h = dcfg["flip"]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels
		spr.material = _preview_mat
		spr.position = Vector2(VW * (i + 0.5) / dirs.size(), VH * 0.5)
		sv.add_child(spr)
		preview_sprites.append(spr)

	_customize_section(customize_view, "Identity")
	var name_cap = Label.new()
	name_cap.text = "Name  (permanent for this run)"
	name_cap.add_theme_font_size_override("font_size", 12)
	name_cap.add_theme_color_override("font_color", Color(0.72, 0.75, 0.86))
	customize_view.add_child(name_cap)

	name_input = LineEdit.new()
	name_input.placeholder_text = "Enter your hero's name…"
	name_input.text = "Hero"
	name_input.max_length = 16
	name_input.custom_minimum_size = Vector2(0, 44)
	customize_view.add_child(name_input)

	_customize_section(customize_view, "Build")

	width_slider  = _build_stat_slider("Width", customize_view)
	height_slider = _build_stat_slider("Height", customize_view)

	_customize_section(customize_view, "Colours")

	# All five groups on a single row.
	var colors_row = HBoxContainer.new()
	colors_row.alignment = BoxContainer.ALIGNMENT_CENTER
	colors_row.add_theme_constant_override("separation", 10)
	hair_picker  = _add_color_picker(colors_row, "Hair",  PlayerSkin.DEF_HAIR)
	shirt_picker = _add_color_picker(colors_row, "Shirt", PlayerSkin.DEF_SHIRT)
	pants_picker = _add_color_picker(colors_row, "Pants", PlayerSkin.DEF_PANTS)
	shoes_picker = _add_color_picker(colors_row, "Shoes", PlayerSkin.DEF_SHOES)
	skin_picker  = _add_color_picker(colors_row, "Skin",  PlayerSkin.DEF_SKIN)
	customize_view.add_child(colors_row)

	_customize_section(customize_view, "Difficulty")
	_add_difficulty_picker(customize_view)
	customize_view.add_child(HSeparator.new())

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
	_update_colors()

# ── Difficulty picker ────────────────────────────────────────────────────────
# Shared by the character-creation screen and the Settings hub, so both places
# stay in step and there's only one description of what the modes mean.
# NOT cleared per call — the picker exists in BOTH views, and every copy has to
# repaint when the mode changes, or the other screen shows a stale selection.
var _difficulty_buttons: Array = []
var _difficulty_blurbs: Array = []

func _add_difficulty_picker(parent: Node) -> void:
	var cap = Label.new()
	cap.text = "Difficulty"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(0.72, 0.76, 0.88))
	parent.add_child(cap)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	for spec in [
		{ "mode": QuestManager.Difficulty.NORMAL, "text": "Normal" },
		{ "mode": QuestManager.Difficulty.RELIC,  "text": "Chosen by the Relic" },
	]:
		var b = Button.new()
		b.text = str(spec["text"])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 44)
		var mode: int = int(spec["mode"])
		b.pressed.connect(func(): _set_difficulty(mode))
		row.add_child(b)
		_difficulty_buttons.append({ "btn": b, "mode": mode })

	var blurb = Label.new()
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(420, 0)
	blurb.add_theme_font_size_override("font_size", 11)
	parent.add_child(blurb)
	_difficulty_blurbs.append(blurb)

	_refresh_difficulty_picker()

func _set_difficulty(mode: int) -> void:
	QuestManager.difficulty = mode
	# The XP bar must re-price immediately, or the HUD keeps showing the old
	# requirement until the next level-up.
	QuestManager.xp_required = QuestManager.xp_required_for(QuestManager.player_level)
	QuestManager.has_unsaved_progress = true
	_refresh_difficulty_picker()

func _refresh_difficulty_picker() -> void:
	for entry in _difficulty_buttons:
		var b: Button = entry["btn"]
		if not is_instance_valid(b):
			continue
		var on: bool = QuestManager.difficulty == int(entry["mode"])
		if on:
			_style_btn(b, Color(0.16, 0.11, 0.04), COL_GOLD)
			b.add_theme_color_override("font_color", COL_GOLD)
		else:
			_style_btn(b, Color(0.10, 0.11, 0.16), Color(0.32, 0.34, 0.46))
			b.add_theme_color_override("font_color", Color(0.72, 0.75, 0.86))
	var hard := QuestManager.is_relic_difficulty()
	for bl in _difficulty_blurbs:
		if not is_instance_valid(bl):
			continue
		if hard:
			bl.text = "Every foe carries a threat trait, the late tiers field deeper loadouts, levels cost 25% more XP and fishing pays 12% less."
			bl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
		else:
			bl.text = "The adventure as it was written. A fair fight."
			bl.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))

# One consistent section heading for the creation screen, with a rule above it so
# the groups read as distinct blocks instead of one long column of controls.
func _customize_section(parent: Node, text: String, first: bool = false) -> void:
	if not first:
		parent.add_child(HSeparator.new())
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	parent.add_child(lbl)

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
	var w = width_slider.value if is_instance_valid(width_slider) else 1.0
	var h = height_slider.value if is_instance_valid(height_slider) else 1.0
	# Size-driven (not scale) so the container lays it out reliably. Bigger
	# scale now that four directions share the row.
	for spr in preview_sprites:
		if is_instance_valid(spr):
			spr.scale = Vector2(w, h) * 2.2

func _add_color_picker(row: HBoxContainer, caption: String, def: Color) -> ColorPickerButton:
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var lbl = Label.new()
	lbl.text = caption
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	vb.add_child(lbl)
	var btn = ColorPickerButton.new()
	btn.custom_minimum_size = Vector2(62, 34)
	btn.color = def
	btn.edit_alpha = false
	btn.color_changed.connect(func(_c): _update_colors())
	vb.add_child(btn)
	row.add_child(vb)
	return btn

func _update_colors() -> void:
	if is_instance_valid(_preview_mat) and is_instance_valid(hair_picker):
		PlayerSkin.apply_colors(_preview_mat, hair_picker.color, shirt_picker.color, pants_picker.color, shoes_picker.color, skin_picker.color)

func _on_confirm_customize() -> void:
	# Build the character now, then go pick which SESSION to start it in.
	QuestManager.reset_to_defaults()
	var nm = name_input.text.strip_edges()
	QuestManager.player_name = nm if nm != "" else "Hero"
	QuestManager.player_scale_x = width_slider.value
	QuestManager.player_scale_y = height_slider.value
	QuestManager.hair_color = hair_picker.color
	QuestManager.shirt_color = shirt_picker.color
	QuestManager.pants_color = pants_picker.color
	QuestManager.shoes_color = shoes_picker.color
	QuestManager.skin_color = skin_picker.color
	QuestManager.play_time_seconds = 0.0
	QuestManager.is_in_combat = false
	Engine.time_scale = 1.0
	_session_mode = "new"
	_show_view("session")

# ── View switching ───────────────────────────────────────────────────────────
func _show_view(which: String) -> void:
	_current_view = which
	main_view.visible      = which == "main"
	load_view.visible      = which == "session"
	settings_view.visible  = which == "settings"
	audio_view.visible     = which == "audio"
	display_view.visible   = which == "display"
	controls_view.visible  = which == "controls"
	customize_view.visible = which == "customize"
	saveselect_view.visible = which == "saveselect"
	# Cancel any in-progress key rebind when leaving the controls view.
	_rebinding_action = ""
	if which == "controls":
		_refresh_keybind_labels()
	# The picker exists on two screens — resync whichever one is being shown.
	if which == "settings" or which == "customize":
		_refresh_difficulty_picker()
	# NOTE: the card no longer resizes per view — it fills the window height and
	# the views scroll inside it, so nothing can spill past its edge.
	if which == "customize":
		_update_preview()
	if which == "session":
		_delete_armed_slot = 0
		_refresh_session_slots()
		if _session_mode == "new":
			load_status_label.text = "Pick a session for your new character.\n(Delete removes a full session to make room.)"
		else:
			load_status_label.text = "Choose a session to load.\n(Delete removes a session.)"
		load_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	if which == "saveselect":
		_refresh_saveselect()

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
