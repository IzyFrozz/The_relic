extends CanvasLayer

# Attach to: CanvasLayer > Panel > (TitleLabel, UnlockedGrid, EquippedGrid, CloseButton)

var unlocked_grid: GridContainer = null
var equipped_grid: GridContainer = null
var close_button: Button = null

func _ready() -> void:
	visible = false
	unlocked_grid = find_child("UnlockedGrid", true, false) as GridContainer
	equipped_grid = find_child("EquippedGrid", true, false) as GridContainer
	close_button = find_child("CloseButton", true, false) as Button
	if is_instance_valid(close_button):
		close_button.pressed.connect(func(): visible = false)

func refresh_display() -> void:
	_build_unlocked_list()
	_build_equipped_list()

func _build_unlocked_list() -> void:
	if not is_instance_valid(unlocked_grid): return
	for child in unlocked_grid.get_children():
		child.queue_free()

	for item in QuestManager.unlocked_items:
		var btn = Button.new()
		var already_equipped = QuestManager.equipped_items.has(item)
		btn.text = item.to_upper() + (" ✓" if already_equipped else "")
		btn.disabled = already_equipped
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): _equip_item(item))
		unlocked_grid.add_child(btn)

func _build_equipped_list() -> void:
	if not is_instance_valid(equipped_grid): return
	for child in equipped_grid.get_children():
		child.queue_free()

	for item in QuestManager.equipped_items:
		var btn = Button.new()
		btn.text = "❌ " + item.to_upper()
		btn.focus_mode = Control.FOCUS_NONE
		# Must keep at least 2 items equipped
		btn.disabled = QuestManager.equipped_items.size() <= 2
		btn.pressed.connect(func(): _unequip_item(item))
		equipped_grid.add_child(btn)

func _equip_item(item: String) -> void:
	if QuestManager.equipped_items.has(item): return
	if QuestManager.equipped_items.size() >= 6: return
	QuestManager.equipped_items.append(item)
	refresh_display()

func _unequip_item(item: String) -> void:
	if QuestManager.equipped_items.size() <= 2: return
	QuestManager.equipped_items.erase(item)
	refresh_display()
