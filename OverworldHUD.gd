extends CanvasLayer

var level_label:    Label       = null
var max_hp_label:   Label       = null
var xp_bar:         ProgressBar = null
var xp_text:        Label       = null
var roadmap_button: Button      = null
var roadmap_popup:  CanvasLayer = null
var timer_label:    Label       = null

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
	timer_label    = find_child("TimerLabel",    true, false) as Label

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

	# Build timer label if not already in scene
	if not is_instance_valid(timer_label):
		var root = Control.new()
		root.name = "HUDTimerRoot"
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		timer_label = Label.new()
		timer_label.name = "TimerLabel"
		root.add_child(timer_label)

	if is_instance_valid(timer_label):
		timer_label.add_theme_font_size_override("font_size", 15)
		timer_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.95, 1.0))
		timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		timer_label.offset_left   = -170
		timer_label.offset_right  = -10
		timer_label.offset_top    = 10
		timer_label.offset_bottom = 34

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
	if is_instance_valid(timer_label):
		timer_label.text = "⏱  " + _fmt(QuestManager.play_time_seconds)

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
