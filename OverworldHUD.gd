extends CanvasLayer

var level_label:    Label       = null
var max_hp_label:   Label       = null
var xp_bar:         ProgressBar = null
var xp_text:        Label       = null
var roadmap_button: Button      = null
var roadmap_popup:  CanvasLayer = null

# Quest objective banner (built in code, top-centre).
# PanelContainer, NOT Panel — the two are unrelated classes and a Panel-typed
# assignment fails at runtime, not at parse time.
var quest_panel: PanelContainer = null
var quest_label: RichTextLabel = null
var key_icon:    TextureRect = null
const KEY_TEX_PATH := "res://Asset/Meta data assets files/Visuals/OBJECTS/items/key.png"

# Left-side panel buttons + Tab navigation.
var quest_button: Button = null
var quest_log: Control = null
var quest_log_text: RichTextLabel = null
var quest_page_title: Label = null       # header showing the current page name
var quest_accept_box: VBoxContainer = null   # holds per-quest Accept buttons (Rumors page)
var _quest_page: int = 0                 # 0 Main · 1 Available · 2 Active · 3 Rumors · 4 Completed
const QUEST_PAGES := ["Main Quest", "Available", "Active", "Rumors", "Completed"]
var _side_buttons: Array = []
var _sel_index: int = -1

# Themed bottom-left stat panel (replaces the plain LV/HP labels).
var stat_panel: Panel = null
var stat_lv: RichTextLabel = null
var stat_hp: RichTextLabel = null

const BTN_SIZE   := Vector2(150, 46)   # shared size for every overworld button
const COL_GOLD   := Color(1.00, 0.85, 0.30, 1.0)
const COL_BORDER := Color(0.28, 0.33, 0.52, 1.0)
const COL_PANEL  := Color(0.08, 0.09, 0.13, 0.90)
# Text column for the objective banner; longer lines wrap instead of bleeding.
const TRACKER_TEXT_W := 420.0
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
			xp_container.offset_top = -58;   xp_container.offset_bottom = -18
			xp_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
			xp_container.grow_vertical = Control.GROW_DIRECTION_BEGIN

	if is_instance_valid(xp_text):
		xp_text.add_theme_font_size_override("font_size", 13)
		xp_text.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
		xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(roadmap_button):
		roadmap_button.focus_mode = Control.FOCUS_NONE
		roadmap_button.custom_minimum_size = BTN_SIZE
		roadmap_button.add_theme_stylebox_override("normal", _s(Color(0.12, 0.14, 0.20), COL_BORDER, 7))
		roadmap_button.add_theme_stylebox_override("hover",  _s(Color(0.20, 0.22, 0.32), COL_GOLD,   7))
		roadmap_button.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
		roadmap_button.add_theme_font_size_override("font_size", 15)
		IconDB.decorate_button(roadmap_button, "📜", "Roadmap", 26)
		roadmap_button.pressed.connect(_on_roadmap_pressed)
		# Dock the button column tight to the top-left corner, unscaled, so every
		# overworld button shares BTN_SIZE.
		var container = roadmap_button.get_parent()
		if container is Control:
			container.scale = Vector2(1, 1)
			container.anchor_top = 0.0; container.anchor_bottom = 0.0
			container.anchor_left = 0.0; container.anchor_right = 0.0
			container.offset_left = 14; container.offset_right = 14 + BTN_SIZE.x
			container.offset_top = 14; container.offset_bottom = 14 + BTN_SIZE.y * 2 + 30
			container.grow_vertical = Control.GROW_DIRECTION_END
			container.add_theme_constant_override("separation", 8)

	_build_quest_button()
	_build_quest_log()
	_build_stat_panel()
	_side_buttons = [roadmap_button, quest_button]

	# Live-refresh the quest log whenever side-quest state changes (accept,
	# progress, completion, unlock) — but only while it's open.
	if not QuestManager.side_quests_changed.is_connected(_on_side_quests_changed):
		QuestManager.side_quests_changed.connect(_on_side_quests_changed)

func _on_side_quests_changed() -> void:
	if is_instance_valid(quest_log) and quest_log.visible:
		_refresh_quest_log()

# ── Quest objective banner ─────────────────────────────────────────────────────
func _build_quest_tracker() -> void:
	# Same shape as the Toast, and for the same reason: this was a fixed 420-wide
	# Panel holding a non-wrapping label, so any objective line longer than that
	# ran out past the border. PanelContainer + wrapping label means the box grows
	# downward for a long objective instead of bleeding sideways.
	quest_panel = PanelContainer.new()
	quest_panel.anchor_left = 0.5; quest_panel.anchor_right = 0.5
	quest_panel.anchor_top = 0.0;  quest_panel.anchor_bottom = 0.0
	quest_panel.offset_left  = -(TRACKER_TEXT_W * 0.5 + 14)
	quest_panel.offset_right =  (TRACKER_TEXT_W * 0.5 + 14)
	quest_panel.offset_top = 72;    quest_panel.offset_bottom = 72   # grows down
	quest_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	quest_panel.grow_vertical   = Control.GROW_DIRECTION_END
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_theme_stylebox_override("panel", _s(COL_PANEL, COL_GOLD, 9))
	add_child(quest_panel)

	var pad = MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 9)
	pad.add_theme_constant_override("margin_bottom", 9)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(pad)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(hb)

	key_icon = TextureRect.new()
	key_icon.texture = load(KEY_TEX_PATH)
	key_icon.custom_minimum_size = Vector2(22, 22)
	key_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	key_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_icon.visible = false
	hb.add_child(key_icon)

	quest_label = RichTextLabel.new()
	quest_label.bbcode_enabled = true
	quest_label.fit_content = true
	quest_label.scroll_active = false
	# Wraps rather than overflowing; expands to whatever width the key icon leaves.
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quest_label.add_theme_font_size_override("normal_font_size", 15)
	quest_label.add_theme_color_override("default_color", Color(0.95, 0.92, 0.80))
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
	# [center] because the label now fills the column rather than hugging its text.
	quest_label.text = "[center]%s[/center]" % IconDB.iconify(t, 18)
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
	visible = not (in_combat or end_active or QuestManager.is_fishing)

	# Keep the global "a Q/E popup is open" flag in sync so overworld interact
	# handlers can ignore E/Q while the quest log is up (see QuestManager).
	QuestManager.ui_arrow_nav_open = is_instance_valid(quest_log) and quest_log.visible

	# Timer increments on QuestManager so it survives scene reloads / win / lose
	if not in_combat and not end_active and Engine.time_scale > 0.0:
		QuestManager.play_time_seconds += delta

	if visible:
		_refresh()

func _refresh() -> void:
	if is_instance_valid(level_label):
		level_label.text = "LV. %d" % QuestManager.player_level
	if is_instance_valid(max_hp_label):
		max_hp_label.text = "%d HP" % QuestManager.MAX_HEALTH
	if is_instance_valid(xp_bar):
		xp_bar.max_value = QuestManager.xp_required
		xp_bar.value     = QuestManager.current_xp
	if is_instance_valid(xp_text):
		xp_text.text = "XP  %d / %d" % [QuestManager.current_xp, QuestManager.xp_required]
	if is_instance_valid(stat_lv):
		stat_lv.text = IconDB.iconify("⭐  LV. %d" % QuestManager.player_level, 22)
	if is_instance_valid(stat_hp):
		stat_hp.text = IconDB.iconify("❤️  %d HP" % QuestManager.MAX_HEALTH, 20)
	# NOTE: the quest log is refreshed on open, on page change, and via the
	# side_quests_changed signal — NOT every frame (it builds Accept buttons).

# ── Bottom-left stat panel ─────────────────────────────────────────────────────
func _build_stat_panel() -> void:
	# Hide the old plain labels; show a themed panel instead.
	if is_instance_valid(level_label):  level_label.visible = false
	if is_instance_valid(max_hp_label): max_hp_label.visible = false

	stat_panel = Panel.new()
	stat_panel.anchor_left = 0.0; stat_panel.anchor_right = 0.0
	stat_panel.anchor_top = 1.0;  stat_panel.anchor_bottom = 1.0
	stat_panel.offset_left = 16;  stat_panel.offset_right = 196
	stat_panel.offset_top = -104; stat_panel.offset_bottom = -18
	stat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stat_panel.add_theme_stylebox_override("panel", _s(COL_PANEL, COL_BORDER, 9))
	add_child(stat_panel)

	var vb = VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_panel.add_child(vb)

	stat_lv = RichTextLabel.new()
	stat_lv.bbcode_enabled = true; stat_lv.fit_content = true; stat_lv.scroll_active = false
	stat_lv.autowrap_mode = TextServer.AUTOWRAP_OFF
	stat_lv.add_theme_font_size_override("normal_font_size", 22)
	stat_lv.add_theme_color_override("default_color", COL_GOLD)
	vb.add_child(stat_lv)

	stat_hp = RichTextLabel.new()
	stat_hp.bbcode_enabled = true; stat_hp.fit_content = true; stat_hp.scroll_active = false
	stat_hp.autowrap_mode = TextServer.AUTOWRAP_OFF
	stat_hp.add_theme_font_size_override("normal_font_size", 18)
	stat_hp.add_theme_color_override("default_color", Color(0.96, 0.48, 0.48))
	vb.add_child(stat_hp)

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
	# Close the Quest log so only one side panel is open at a time.
	if is_instance_valid(quest_log):
		quest_log.visible = false
	if is_instance_valid(roadmap_popup):
		roadmap_popup.visible = true
		SFX.play(SFX.ui_open)
		if roadmap_popup.has_method("refresh_display"):
			roadmap_popup.refresh_display()

# ── Quest button (sits directly under Roadmap, same look) ───────────────────────
func _build_quest_button() -> void:
	if not is_instance_valid(roadmap_button):
		return
	quest_button = Button.new()
	quest_button.focus_mode = Control.FOCUS_NONE
	quest_button.custom_minimum_size = BTN_SIZE
	quest_button.add_theme_stylebox_override("normal", _s(Color(0.12, 0.14, 0.20), COL_BORDER, 7))
	quest_button.add_theme_stylebox_override("hover",  _s(Color(0.20, 0.22, 0.32), COL_GOLD,   7))
	quest_button.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	quest_button.add_theme_font_size_override("font_size", 15)
	IconDB.decorate_button(quest_button, "🗒️", "Quest", 26)
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
	if not is_instance_valid(quest_log):
		return
	# Toggle, and close the Roadmap so only one side panel is open at a time.
	if quest_log.visible:
		quest_log.visible = false
		return
	_close_roadmap()
	_refresh_quest_log()
	quest_log.visible = true

func _close_roadmap() -> void:
	if not is_instance_valid(roadmap_popup):
		roadmap_popup = get_tree().root.find_child("RoadmapPopup", true, false) as CanvasLayer
	if is_instance_valid(roadmap_popup) and roadmap_popup.visible:
		roadmap_popup.visible = false
		SFX.play(SFX.ui_close)

# ── Quest log popup ─────────────────────────────────────────────────────────────
func _build_quest_log() -> void:
	# Non-blocking left drawer (like the Roadmap): no dim, docked below the
	# Roadmap/Quest buttons so it never overlaps them, and the player can keep
	# moving while it's open. Esc (handled in _input) closes it.
	quest_log = Control.new()
	quest_log.name = "QuestLogPanel"
	quest_log.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quest_log.visible = false
	quest_log.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks pass through except on the panel
	add_child(quest_log)

	var panel = Panel.new()
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top = 0.0;  panel.anchor_bottom = 1.0
	panel.offset_left = 14;  panel.offset_right = 474
	panel.offset_top = 172;  panel.offset_bottom = -118   # stop above the stat panel
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
	title.text = "Quest Log"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	vb.add_child(title)

	# ── Page navigation:  ◀   Page Name   ▶   (cycles Main/Active/Rumors/Done) ──
	var nav = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 10)
	var prev = _make_nav_btn("Q ◀")
	prev.pressed.connect(func(): _cycle_quest_page(-1))
	nav.add_child(prev)
	quest_page_title = Label.new()
	quest_page_title.custom_minimum_size = Vector2(220, 0)
	quest_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quest_page_title.add_theme_font_size_override("font_size", 17)
	quest_page_title.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	nav.add_child(quest_page_title)
	var next = _make_nav_btn("▶ E")
	next.pressed.connect(func(): _cycle_quest_page(1))
	nav.add_child(next)
	vb.add_child(nav)
	vb.add_child(HSeparator.new())

	# Scrollable body so long side-quest lists never overflow the drawer.
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	quest_log_text = RichTextLabel.new()
	quest_log_text.bbcode_enabled = true
	quest_log_text.fit_content = true
	quest_log_text.scroll_active = false
	quest_log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_log_text.add_theme_font_size_override("normal_font_size", 15)
	body.add_child(quest_log_text)

	# Accept buttons for the Rumors page live here (rebuilt on each refresh).
	quest_accept_box = VBoxContainer.new()
	quest_accept_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_accept_box.add_theme_constant_override("separation", 8)
	body.add_child(quest_accept_box)

	var close = Button.new()
	close.text = "✖  Close  (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 40)
	close.add_theme_stylebox_override("normal", _s(Color(0.20, 0.08, 0.08), Color(0.6, 0.2, 0.2), 6))
	close.add_theme_stylebox_override("hover",  _s(Color(0.32, 0.12, 0.12), Color(0.9, 0.35, 0.35), 6))
	close.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	close.pressed.connect(func(): quest_log.visible = false)
	vb.add_child(close)

func _make_nav_btn(txt: String) -> Button:
	var b = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 34)
	b.add_theme_stylebox_override("normal", _s(Color(0.14, 0.16, 0.24), COL_BORDER, 6))
	b.add_theme_stylebox_override("hover",  _s(Color(0.22, 0.25, 0.36), COL_GOLD, 6))
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	return b

func _cycle_quest_page(dir: int) -> void:
	SFX.play(SFX.ui_tab)
	_quest_page = (_quest_page + dir + QUEST_PAGES.size()) % QUEST_PAGES.size()
	_refresh_quest_log()

func _refresh_quest_log() -> void:
	if not is_instance_valid(quest_log_text):
		return
	# Clear any accept buttons from a previous refresh.
	if is_instance_valid(quest_accept_box):
		for c in quest_accept_box.get_children():
			c.queue_free()
	# Badge each page title with a count so the player sees there's more to see.
	# The Active badge doubles as the "X/3" quest-slot indicator.
	var avail_n  = QuestManager.side_quest_ids_in_state("available").size()
	var active_n = QuestManager.active_quest_count()
	var rumor_n  = QuestManager.side_quest_ids_in_state("rumour").size()
	var done_n   = QuestManager.side_quest_ids_in_state("done").size()
	var counts = ["",
		"  (%d)" % avail_n,
		"  (%d/%d)" % [active_n, QuestManager.MAX_ACTIVE_QUESTS],
		"  (%d)" % rumor_n,
		"  (%d)" % done_n]
	if is_instance_valid(quest_page_title):
		quest_page_title.text = "◈  %s%s" % [QUEST_PAGES[_quest_page], counts[_quest_page]]
	var body_bb := ""
	match _quest_page:
		0: body_bb = _main_quest_bbcode()
		1: body_bb = _available_bbcode()
		2: body_bb = _side_list_bbcode("active")
		3: body_bb = _rumors_bbcode()
		4: body_bb = _side_list_bbcode("done")
	quest_log_text.text = IconDB.iconify(body_bb, 18)

func _main_quest_bbcode() -> String:
	var qm = QuestManager
	var steps = [
		["Seek out and talk to the Street Kid", qm.quest_accepted],
		["Collect %d coins   (%d / %d)" % [qm.COINS_NEEDED, mini(qm.coins_collected, qm.COINS_NEEDED), qm.COINS_NEEDED],
			qm.has_key or qm.chest_unlocked or qm.game_won],
		["Trade the coins to the Street Kid for the key", qm.has_key or qm.chest_unlocked or qm.game_won],
		["Open the ancient chest to claim the relic", qm.chest_unlocked or qm.game_won],
		["Return the relic to the Street Kid", qm.game_won],
	]
	var out = "[b][color=#FFD84D]The Village Relic[/color][/b]\n"
	out += "[color=#9aa]A dragon sealed the village relic in an ancient chest. Help the Street Kid get it back.[/color]\n\n"
	for step in steps:
		if step[1]:
			out += "  [color=#44FF88]✓[/color]  [color=#8a8f9c]%s[/color]\n" % step[0]
		else:
			out += "  [color=#FFD84D]➤[/color]  [b]%s[/b]\n" % step[0]
			break
	if qm.game_won:
		out += "\n[color=#44FF88]Quest complete — the village is saved![/color]\n"
	return out

# Shared renderer for the Active and Completed side-quest pages.
func _side_list_bbcode(state: String) -> String:
	var ids = QuestManager.side_quest_ids_in_state(state)
	if ids.is_empty():
		if state == "active":
			return "[color=#9aa]No active side quests.\n\nCheck the [b]Available[/b] page (◀) to start one.[/color]"
		return "[color=#9aa]No completed side quests yet.[/color]"
	var out = ""
	for id in ids:
		var d = SideQuestDB.get_def(id)
		var prog = QuestManager.side_quest_progress.get(id, 0)
		if state == "done":
			out += "[color=#44FF88]✓[/color]  [b]%s %s[/b]\n" % [d.get("emoji", "•"), d.get("title", id)]
			out += "     [color=#7a8f7a]Reward claimed: %s[/color]\n\n" % SideQuestDB.reward_text(id)
		else:
			out += "[color=#FFD84D]➤[/color]  [b]%s %s[/b]   [color=#8fb4ff]%s[/color]\n" % [
				d.get("emoji", "•"), d.get("title", id), SideQuestDB.progress_text(id, prog)]
			out += "     [color=#9aa]%s[/color]\n" % d.get("how", "")
			out += "     [color=#c9a24d]Reward: %s[/color]\n\n" % SideQuestDB.reward_text(id)
	return out

const SideQuestDB = preload("res://SideQuestDB.gd")

# Available page: revealed, startable quests. Each gets an "Activate" button,
# subject to the MAX_ACTIVE_QUESTS cap (buttons disable and a note shows when
# the log is full).
func _available_bbcode() -> String:
	var ids = QuestManager.side_quest_ids_in_state("available")
	var active_n = QuestManager.active_quest_count()
	var cap = QuestManager.MAX_ACTIVE_QUESTS
	var at_cap = active_n >= cap
	var out = ""
	if ids.is_empty():
		out = "[color=#9aa]Nothing ready to start.\n\nChase down [b]Rumors[/b] (▶) to reveal new quests.[/color]"
	else:
		out = "[color=#c9a24d]Ready to take on — %d / %d quest slots used:[/color]\n" % [active_n, cap]
		if at_cap:
			out += "[color=#e07a5a]⚠ Quest log full — finish an active quest before starting another.[/color]\n"
		# One Activate button per available quest (full details), below the text.
		if is_instance_valid(quest_accept_box):
			for id in ids:
				var d = SideQuestDB.get_def(id)
				var card = Button.new()
				card.focus_mode = Control.FOCUS_NONE
				card.custom_minimum_size = Vector2(0, 66)
				card.clip_text = true
				card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				card.disabled = at_cap
				card.add_theme_stylebox_override("normal",   _s(Color(0.12, 0.13, 0.20), COL_GOLD, 8))
				card.add_theme_stylebox_override("hover",    _s(Color(0.20, 0.22, 0.32), COL_GOLD, 8))
				card.add_theme_stylebox_override("disabled", _s(Color(0.10, 0.10, 0.13), Color(0.3, 0.3, 0.35), 8))
				card.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
				card.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
				card.add_theme_font_size_override("font_size", 14)
				card.text = "%s  %s   ·   Reward: %s\n%s\n%s" % [
					d.get("emoji", "📜"), d.get("title", id), SideQuestDB.reward_text(id),
					d.get("how", ""), ("🔒 Log full" if at_cap else "▶ Activate")]
				var qid := String(id)
				card.pressed.connect(func():
					QuestManager.accept_side_quest(qid)   # available → active (enforces cap)
					_quest_page = 2   # jump to Active so they see it start tracking
					_refresh_quest_log())
				quest_accept_box.add_child(card)
	return out

# Rumors page: vague hints only, no buttons. The player must chase the hint
# down in the world (fight / collect / talk) to reveal the quest, at which point
# it moves to the Available page. Item-reward rumors flag their prize.
func _rumors_bbcode() -> String:
	var ids = QuestManager.side_quest_ids_in_state("rumour")
	if ids.is_empty():
		return "[color=#9aa]No rumors circulating.\n\nExplore, fight and talk to folk to stir up more.[/color]"
	var out = "[color=#8a8f9c]Whispers around the village — chase one down to reveal a quest:[/color]\n\n"
	for id in ids:
		var d = SideQuestDB.get_def(id)
		var reward_note = ""
		if d.get("reward", {}).has("item"):
			var meta = QuestManager.ITEM_META.get(d["reward"]["item"], {})
			reward_note = "   [color=#c9a24d](rumoured reward: %s %s)[/color]" % [meta.get("emoji", "🎁"), meta.get("label", "a special item")]
		out += "  🔎  [i]\"%s\"[/i]%s\n" % [SideQuestDB.teaser(id), reward_note]
		out += "        [color=#8fb4ff]↳ %s[/color]\n\n" % SideQuestDB.rumour_hint(id)
	return out

# ── Tab navigation between the left panels ──────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Close the quest log on Esc before anything else claims the key.
	if event.keycode == KEY_ESCAPE and is_instance_valid(quest_log) and quest_log.visible:
		quest_log.visible = false
		get_viewport().set_input_as_handled()
		return
	# Q / E mirror the ◀ ▶ page arrows while the quest log is open.
	if is_instance_valid(quest_log) and quest_log.visible:
		if event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			_cycle_quest_page(-1)
			return
		if event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			_cycle_quest_page(1)
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
