extends CanvasLayer

var unlocked_grid: GridContainer = null
var equipped_grid: GridContainer = null
var close_button: Button = null
var title_label: Label = null

const ITEM_META := {
	"potion":     { "emoji": "🧪", "label": "Potion",     "desc": "Restores 20 HP." },
	"shield":     { "emoji": "🛡️", "label": "Shield",     "desc": "Blocks the next hit." },
	"grindstone": { "emoji": "🪨", "label": "Grindstone", "desc": "2× damage next attack." },
	"whip":       { "emoji": "💥", "label": "Whip",       "desc": "Enemy skips their turn." },
	"needle":     { "emoji": "📌", "label": "Needle",     "desc": "Pierces enemy armor." },
	"magnet":     { "emoji": "🧲", "label": "Magnet",     "desc": "Steal an enemy item." },
}

func _ready() -> void:
	visible = false
	title_label   = find_child("TitleLabel", true, false) as Label
	unlocked_grid = find_child("UnlockedGrid", true, false) as GridContainer
	equipped_grid = find_child("EquippedGrid", true, false) as GridContainer
	close_button  = find_child("CloseButton", true, false) as Button

	if is_instance_valid(title_label):
		title_label.text = "⚙️  LOADOUT CONFIGURATION"
		title_label.add_theme_font_size_override("font_size", 18)
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

	if is_instance_valid(close_button):
		close_button.text = "✖  Close"
		close_button.pressed.connect(func(): visible = false)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func refresh_display() -> void:
	_build_unlocked_list()
	_build_equipped_list()

func _build_unlocked_list() -> void:
	if not is_instance_valid(unlocked_grid): return
	for child in unlocked_grid.get_children(): child.queue_free()

	for item in QuestManager.unlocked_items:
		var meta = ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var already = QuestManager.equipped_items.has(item)

		var btn = Button.new()
		btn.text = "%s  %s%s" % [meta["emoji"], meta["label"], "  ✓" if already else ""]
		btn.tooltip_text = meta["desc"] + ("\n(Already in loadout)" if already else "\nClick to equip")
		btn.disabled = already or QuestManager.equipped_items.size() >= 6
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(150, 44)
		btn.modulate.a = 0.45 if already else 1.0

		var captured = item
		btn.pressed.connect(func(): _equip_item(captured))
		unlocked_grid.add_child(btn)

func _build_equipped_list() -> void:
	if not is_instance_valid(equipped_grid): return
	for child in equipped_grid.get_children(): child.queue_free()

	for i in range(QuestManager.equipped_items.size()):
		var item = QuestManager.equipped_items[i]
		var meta = ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})

		var btn = Button.new()
		btn.text = "[%d]  %s  %s  ✕" % [i + 1, meta["emoji"], meta["label"]]
		btn.tooltip_text = "Slot %d — %s\nClick to remove" % [i + 1, meta["desc"]]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(170, 44)
		btn.disabled = QuestManager.equipped_items.size() <= 2
		btn.modulate.a = 0.45 if btn.disabled else 1.0

		var captured = item
		btn.pressed.connect(func(): _unequip_item(captured))
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
