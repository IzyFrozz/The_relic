extends CanvasLayer

var level_label:    Label       = null
var max_hp_label:   Label       = null
var xp_bar:         ProgressBar = null
var xp_text:        Label       = null
var roadmap_button: Button      = null
var roadmap_popup:  CanvasLayer = null

# Quest objective banner (built in code, top-centre).
var quest_panel: Panel = null
var quest_label: Label = null
var key_icon:    TextureRect = null
const KEY_TEX_PATH := "res://Asset/Meta data assets files/Visuals/OBJECTS/items/key.png"

# Left-side panel buttons + Tab navigation.
var quest_button: Button = null
var quest_log: Control = null
var quest_log_text: RichTextLabel = null
var _side_buttons: Array = []
var _sel_index: int = -1

const COL_GOLD   := Color(1.00, 0.85, 0.30, 1.0)
const COL_BORDER := Color(0.28, 0.33, 0.52, 1.0)
const COL_PANEL  := Color(0.08, 0.09, 0.13, 0.90)
const COL_XP_BG  := Color(0.13, 0.14, 0.20, 1.0)
const COL_XP_FG  := Color(0.22, 0.52, 1.00, 1.0)

func _s(bg: Color, border: Color, r: int = 6) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(r); s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  = 5;  s.content_margin_bottom = 5
	return s

func _ready() -> void:
	level_label    = find_child("LevelLabel",    true, false) as Label
	max_hp_label   = find_child("MaxHPLabel",    true, false) as Label
	xp_bar         = find_child("XPBar",         true, false) as ProgressBar
	xp_text        = find_child("XPText",        true, false) as Label
	roadmap_button = find_child("RoadmapButton", true, false) as Button

	var left_panel = find_child("LeftStatPanel", true, false) as Panel
	if is_instance_valid(left_panel):
		left_panel.add_theme_stylebox_override("panel", _s(COL_PANEL, COL_BORDER, 8))

	if is_instance_valid(level_label):
		level_label.add_theme_font_size_override("font_size", 20)
		level_label.add_theme_color_override("font_color", COL_GOLD)
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(max_hp_label):
		max_hp_label.add_theme_font_size_override("font_size", 17)
		max_hp_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		max_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(xp_bar):
		var bg = StyleBoxFlat.new(); bg.bg_color = COL_XP_BG; bg.set_corner_radius_all(4)
		xp_bar.add_theme_stylebox_override("background", bg)
		var fill = StyleBoxFlat.new(); fill.bg_color = COL_XP_FG; fill.set_corner_radius_all(4)
		xp_bar.add_theme_stylebox_override("fill", fill)
		xp_bar.custom_minimum_size = Vector2(500, 16)
		xp_bar.show_percentage = false
		# The XP bar sat full-width at the very top (a stray "0%"). Move it down
		# to the bottom-centre, out of the quest banner's way.
		var xp_container = xp_bar.get_parent()
		if xp_container is Control:
			xp_container.anchor_left = 0.5; xp_container.anchor_right = 0.5
			xp_container.anchor_top = 1.0;  xp_container.anchor_bottom = 1.0
			xp_container.offset_left = -260; xp_container.offset_right = 260
			xp_container.offset_top = -86;   xp_container.offset_bottom = -42
			xp_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
			xp_container.grow_vertical = Control.GROW_DIRECTION_BEGIN

	if is_instance_valid(xp_text):
		xp_text.add_theme_font_size_override("font_size", 13)
		xp_text.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
		xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(roadmap_button):
		roadmap_button.text = "📜  Roadmap"
		roadmap_button.focus_mode = Control.FOCUS_NONE
		roadmap_button.custom_minimum_size = Vector2(140, 44)
		roadmap_button.add_theme_stylebox_override("normal", _s(Color(0.12, 0.14, 0.20), COL_BORDER, 7))
		roadmap_button.add_theme_stylebox_override("hover",  _s(Color(0.20, 0.22, 0.32), COL_GOLD,   7))
		roadmap_button.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
		roadmap_button.add_theme_font_size_override("font_size", 14)
		roadmap_button.pressed.connect(_on_roadmap_pressed)

	_build_quest_tracker()
	_build_quest_button()
	_build_quest_log()
	_side_buttons = [roadmap_button, quest_button]

# ── Quest objective banner ─────────────────────────────────────────────────────
func _build_quest_tracker() -> void:
	quest_panel = Panel.new()
	quest_panel.anchor_left = 0.5; quest_panel.anchor_right = 0.5
	quest_panel.anchor_top = 0.0;  quest_panel.anchor_bottom = 0.0
	quest_panel.offset_left = -210; quest_panel.offset_right = 210
	quest_panel.offset_top = 72;    quest_panel.offset_bottom = 112
	quest_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_theme_stylebox_override("panel", _s(COL_PANEL, COL_GOLD, 9))
	add_child(quest_panel)

	var hb = HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(hb)

	key_icon = TextureRect.new()
	key_icon.texture = load(KEY_TEX_PATH)
	key_icon.custom_minimum_size = Vector2(22, 22)
	key_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	key_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_icon.visible = false
	hb.add_child(key_icon)

	quest_label = Label.new()
	quest_label.add_theme_font_size_override("font_size", 15)
	quest_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80))
	quest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(quest_label)

func _refresh_quest_tracker() -> void:
	if not is_instance_valid(quest_label):
		return
	var show_key := false
	var t := ""
	if QuestManager.game_won:
		t = "✔  Relic delivered — the village is saved!"
	elif QuestManager.has_relic:
		t = "🏺  Return the Relic to the Street Kid"
	elif QuestManager.has_key:
		t = "Open the ancient chest";  show_key = true
	elif QuestManager.quest_accepted:
		t = "🪙  Coins  %d / %d   →  bring to the Street Kid" % [QuestManager.coins_collected, QuestManager.COINS_NEEDED]
	else:
		t = "❔  Seek out the Street Kid near the village"
	quest_label.text = t
	if is_instance_valid(key_icon):
		key_icon.visible = show_key

# ── Play timer ────────────────────────────────────────────────────────────────
# The visual timer display now lives in PauseMenu (top-right of the pause
# popup) instead of the overworld HUD. This script still owns incrementing
# QuestManager.play_time_seconds every frame since that's persistent game
# state that needs to survive scene reloads / win / lose regardless of where
# it's displayed.

func _process(delta: float) -> void:
	var in_combat  = QuestManager.is_in_combat
	var end_active = _is_end_screen_active()
	visible = not (in_combat or end_active)

	# Timer increments on QuestManager so it survives scene reloads / win / lose
	if not in_combat and not end_active and Engine.time_scale > 0.0:
		QuestManager.play_time_seconds += delta

	if visible:
		_refresh()

func _refresh() -> void:
	if is_instance_valid(level_label):
		level_label.text = "⭐  LV. %d" % QuestManager.player_level
	if is_instance_valid(max_hp_label):
		max_hp_label.text = "❤️  %d HP" % QuestManager.MAX_HEALTH
	if is_instance_valid(xp_bar):
		xp_bar.max_value = QuestManager.xp_required
		xp_bar.value     = QuestManager.current_xp
	if is_instance_valid(xp_text):
		xp_text.text = "XP  %d / %d" % [QuestManager.current_xp, QuestManager.xp_required]
	_refresh_quest_tracker()

func _fmt(sec: float) -> String:
	var t = int(sec)
	var h = t / 3600; var m = (t % 3600) / 60; var s = t % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%02d:%02d" % [m, s]

func _is_end_screen_active() -> bool:
	for n in ["LoseUI", "WinUI"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node.visible: return true
	return false

func _on_roadmap_pressed() -> void:
	if not is_instance_valid(roadmap_popup):
		roadmap_popup = get_tree().root.find_child("RoadmapPopup", true, false) as CanvasLayer
	if is_instance_valid(roadmap_popup):
		roadmap_popup.visible = true
		if roadmap_popup.has_method("refresh_display"):
			roadmap_popup.refresh_display()

# ── Quest button (sits directly under Roadmap, same look) ───────────────────────
func _build_quest_button() -> void:
	if not is_instance_valid(roadmap_button):
		return
	quest_button = Button.new()
	quest_button.text = "🗒️  Quest"
	quest_button.focus_mode = Control.FOCUS_NONE
	quest_button.custom_minimum_size = Vector2(140, 44)
	quest_button.add_theme_stylebox_override("normal", _s(Color(0.12, 0.14, 0.20), COL_BORDER, 7))
	quest_button.add_theme_stylebox_override("hover",  _s(Color(0.20, 0.22, 0.32), COL_GOLD,   7))
	quest_button.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	quest_button.add_theme_font_size_override("font_size", 14)
	quest_button.pressed.connect(_on_quest_pressed)
	# Add it into Roadmap's own VBoxContainer so it flows directly below it,
	# with matching width/alignment/scale — no manual offsets to get wrong.
	var container = roadmap_button.get_parent()
	if is_instance_valid(container):
		container.add_child(quest_button)
		container.move_child(quest_button, roadmap_button.get_index() + 1)
	else:
		add_child(quest_button)

func _on_quest_pressed() -> void:
	_refresh_quest_log()
	if is_instance_valid(quest_log):
		quest_log.visible = true

# ── Quest log popup ─────────────────────────────────────────────────────────────
func _build_quest_log() -> void:
	quest_log = Control.new()
	quest_log.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quest_log.visible = false
	quest_log.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(quest_log)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quest_log.add_child(dim)

	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(620, 460)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	ps.set_corner_radius_all(12); ps.set_border_width_all(2)
	ps.border_color = Color(0.35, 0.40, 0.60)
	ps.content_margin_left = 22; ps.content_margin_right = 22
	ps.content_margin_top = 18;  ps.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", ps)
	quest_log.add_child(panel)

	var vb = VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title = Label.new()
	title.text = "🗒️  Quest Log"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	quest_log_text = RichTextLabel.new()
	quest_log_text.bbcode_enabled = true
	quest_log_text.fit_content = true
	quest_log_text.scroll_active = false
	quest_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_log_text.add_theme_font_size_override("normal_font_size", 15)
	vb.add_child(quest_log_text)

	var close = Button.new()
	close.text = "✖  Close  (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 40)
	close.add_theme_stylebox_override("normal", _s(Color(0.20, 0.08, 0.08), Color(0.6, 0.2, 0.2), 6))
	close.add_theme_stylebox_override("hover",  _s(Color(0.32, 0.12, 0.12), Color(0.9, 0.35, 0.35), 6))
	close.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	close.pressed.connect(func(): quest_log.visible = false)
	vb.add_child(close)

func _refresh_quest_log() -> void:
	if not is_instance_valid(quest_log_text):
		return
	var qm = QuestManager
	var out = "[b][color=#FFD84D]The Village Relic[/color][/b]\n"
	out += "[color=#9aa]A dragon sealed the village relic in an ancient chest. Help the Street Kid get it back.[/color]\n\n"
	out += _step("Talk to the Street Kid to accept the quest", qm.quest_accepted)
	out += _step("Collect %d coins  (%d / %d)" % [qm.COINS_NEEDED, mini(qm.coins_collected, qm.COINS_NEEDED), qm.COINS_NEEDED],
			qm.has_key or qm.chest_unlocked or qm.game_won)
	out += _step("Trade the coins to the Street Kid for the key", qm.has_key or qm.chest_unlocked or qm.game_won)
	out += _step("Open the ancient chest to claim the relic", qm.chest_unlocked or qm.game_won)
	out += _step("Return the relic to the Street Kid", qm.game_won)
	quest_log_text.text = out

func _step(text: String, done: bool) -> String:
	if done:
		return "  [color=#44FF88]✓[/color]  [color=#8a8f9c]%s[/color]\n" % text
	return "  [color=#FFAA44]▢[/color]  %s\n" % text

# ── Tab navigation between the left panels ──────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Close the quest log on Esc before anything else claims the key.
	if event.keycode == KEY_ESCAPE and is_instance_valid(quest_log) and quest_log.visible:
		quest_log.visible = false
		get_viewport().set_input_as_handled()
		return
	if not _can_navigate():
		return
	match event.keycode:
		KEY_TAB:
			get_viewport().set_input_as_handled()
			_cycle_selection()
		KEY_ENTER, KEY_KP_ENTER:
			if _sel_index >= 0:
				get_viewport().set_input_as_handled()
				_activate_selection()

func _can_navigate() -> bool:
	if QuestManager.is_in_combat or DialogueManager.is_active:
		return false
	if _is_end_screen_active():
		return false
	if is_instance_valid(quest_log) and quest_log.visible:
		return false
	if not is_instance_valid(roadmap_popup):
		roadmap_popup = get_tree().root.find_child("RoadmapPopup", true, false) as CanvasLayer
	if is_instance_valid(roadmap_popup) and roadmap_popup.visible:
		return false
	var pause = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause) and pause.has_method("is_open") and pause.is_open():
		return false
	return true

func _cycle_selection() -> void:
	if _side_buttons.is_empty():
		return
	_sel_index = (_sel_index + 1) % _side_buttons.size()
	_update_selection_highlight()

func _activate_selection() -> void:
	if _sel_index < 0 or _sel_index >= _side_buttons.size():
		return
	var btn = _side_buttons[_sel_index]
	if btn == roadmap_button:
		_on_roadmap_pressed()
	elif btn == quest_button:
		_on_quest_pressed()

func _update_selection_highlight() -> void:
	for i in range(_side_buttons.size()):
		var b = _side_buttons[i]
		if not is_instance_valid(b):
			continue
		if i == _sel_index:
			b.add_theme_stylebox_override("normal", _s(Color(0.24, 0.26, 0.13), COL_GOLD, 7))
		else:
			b.add_theme_stylebox_override("normal", _s(Color(0.12, 0.14, 0.20), COL_BORDER, 7))
