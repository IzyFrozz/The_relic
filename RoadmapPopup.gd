extends CanvasLayer

var rich_text: RichTextLabel = null
var close_button: Button = null

const COL_BG     := Color(0.09, 0.10, 0.15, 0.97)
const COL_BORDER := Color(0.30, 0.35, 0.55, 1.0)
const COL_GOLD   := Color(1.00, 0.85, 0.30, 1.0)

const SLOT_UNLOCKS := {
	2: 3,
	4: 4,
	6: 5,
	8: 6,
}
const STARTING_SLOTS := 2

func _ready() -> void:
	visible = false
	rich_text    = find_child("RichTextLabel", true, false) as RichTextLabel
	close_button = find_child("CloseButton", true, false) as Button
	var panel    = find_child("Panel", true, false) as Panel

	if is_instance_valid(panel):
		var s = StyleBoxFlat.new()
		s.bg_color = COL_BG
		s.set_corner_radius_all(10)
		s.set_border_width_all(2)
		s.border_color = COL_BORDER
		s.content_margin_left = 18; s.content_margin_right = 18
		s.content_margin_top = 16;  s.content_margin_bottom = 16
		panel.add_theme_stylebox_override("panel", s)

	if is_instance_valid(rich_text):
		rich_text.add_theme_font_size_override("normal_font_size", 14)
		rich_text.add_theme_color_override("default_color", Color(0.88, 0.88, 1.0))

	if is_instance_valid(close_button):
		close_button.text = "✖  Close  (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(0.20, 0.08, 0.08)
		bs.set_corner_radius_all(5); bs.set_border_width_all(1)
		bs.border_color = Color(0.6, 0.2, 0.2)
		close_button.add_theme_stylebox_override("normal", bs)
		var bsh = bs.duplicate(); bsh.bg_color = Color(0.35, 0.12, 0.12)
		close_button.add_theme_stylebox_override("hover", bsh)
		close_button.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		close_button.add_theme_font_size_override("font_size", 14)
		close_button.pressed.connect(func(): visible = false)

func _process(_delta: float) -> void:
	if visible and _is_end_screen_active():
		visible = false

func _is_end_screen_active() -> bool:
	for n in ["LoseUI", "WinUI"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node.visible:
			return true
	return false

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func _slot_unlock_at(lvl: int) -> int:
	return SLOT_UNLOCKS.get(lvl, 0)

func refresh_display() -> void:
	if not is_instance_valid(rich_text): return

	var out = "[b][color=#FFD84D]📜  PROGRESSION ROADMAP[/color][/b]\n\n"

	out += "[b]LEVEL 1[/b]\n"
	out += "  🧪  Potion  —  Restore 20 HP\n"
	out += "  🛡️  Shield  —  Block next hit\n"
	out += "  🎒  Loadout: [b]%d slots[/b]\n\n" % STARTING_SLOTS

	var sorted = QuestManager.item_unlocks.keys()
	sorted.sort()

	for lvl in sorted:
		var item        = QuestManager.item_unlocks[lvl]
		var is_unlocked = QuestManager.unlocked_items.has(item)
		var is_equipped = QuestManager.equipped_items.has(item)
		var slot_gain   = _slot_unlock_at(lvl)

		# Always pull display data from ITEM_META so renamed/reworked items
		# (e.g. battle_horn -> Lifesteal Vial) show correctly everywhere,
		# instead of deriving a label from the raw item id string.
		var meta  = QuestManager.ITEM_META.get(item, {"emoji": "❓", "label": item.capitalize(), "desc": ""})
		var emoji = meta.get("emoji", "❓")
		var label = meta.get("label", item.capitalize())
		var desc  = meta.get("desc", "")

		if not is_unlocked:
			out += "[b]LEVEL %d[/b]  [color=#555555]🔒  Locked[/color]\n" % lvl
			if slot_gain > 0:
				out += "  [color=#555555]🎒  Loadout expands to %d slots[/color]\n" % slot_gain
			out += "  [color=#444444]Reach level %d to reveal.[/color]\n\n" % lvl
			continue

		var badge := ""
		if is_equipped:  badge = "  [color=#44FF88]✓ Equipped[/color]"
		else:            badge = "  [color=#FFAA44]✓ Unlocked[/color]"

		out += "[b]LEVEL %d[/b]%s\n" % [lvl, badge]
		out += "  %s  %s  —  %s\n" % [emoji, label, desc]

		if slot_gain > 0:
			var prev = slot_gain - 1
			out += "  🎒  Loadout Slot Unlocked!  [b](%d → %d items)[/b]\n" % [prev, slot_gain]

		out += "\n"

	rich_text.bbcode_enabled = true
	rich_text.text = out
