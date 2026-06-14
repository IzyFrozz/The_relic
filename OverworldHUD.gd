extends CanvasLayer

var max_hp_label: Label = null
var level_label: Label = null
var xp_bar: ProgressBar = null
var xp_text: Label = null
var roadmap_button: Button = null
var roadmap_popup: CanvasLayer = null

func _ready() -> void:
	max_hp_label = find_child("MaxHPLabel", true, false) as Label
	level_label = find_child("LevelLabel", true, false) as Label
	xp_bar = find_child("XPBar", true, false) as ProgressBar
	xp_text = find_child("XPText", true, false) as Label
	roadmap_button = find_child("RoadmapButton", true, false) as Button

	if is_instance_valid(roadmap_button):
		roadmap_button.pressed.connect(_on_roadmap_pressed)

func _process(_delta: float) -> void:
	# Hide during combat, death screen, win screen
	var should_hide = QuestManager.is_in_combat or _is_end_screen_active()
	visible = not should_hide
	if visible:
		_refresh()

func _refresh() -> void:
	if is_instance_valid(level_label):
		level_label.text = "LV. %d" % QuestManager.player_level
	if is_instance_valid(max_hp_label):
		max_hp_label.text = "Max HP: %d" % QuestManager.MAX_HEALTH
	if is_instance_valid(xp_bar):
		xp_bar.max_value = QuestManager.xp_required
		xp_bar.value = QuestManager.current_xp
	if is_instance_valid(xp_text):
		xp_text.text = "%d / %d XP" % [QuestManager.current_xp, QuestManager.xp_required]

func _is_end_screen_active() -> bool:
	var root_node = get_tree().root
	for screen_name in ["LoseUI", "WinUI", "DeathScreen", "VictoryScreen", "VictoryUI"]:
		var screen = root_node.find_child(screen_name, true, false)
		if is_instance_valid(screen) and screen.visible:
			return true
	return false

func _on_roadmap_pressed() -> void:
	if not is_instance_valid(roadmap_popup):
		roadmap_popup = get_tree().root.find_child("RoadmapPopup", true, false) as CanvasLayer
	if is_instance_valid(roadmap_popup):
		roadmap_popup.visible = true
		roadmap_popup.refresh_display()
