extends CanvasLayer

var rich_text: RichTextLabel = null
var close_button: Button = null

const COL_BG     := Color(0.09, 0.10, 0.15, 0.97)
const COL_BORDER := Color(0.30, 0.35, 0.55, 1.0)
const COL_GOLD   := Color(1.00, 0.85, 0.30, 1.0)

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

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func refresh_display() -> void:
	if not is_instance_valid(rich_text): return

	var out = "[b][color=#FFD84D]📜  ITEM UNLOCK ROADMAP[/color][/b]\n\n"

	# Level 1 starters
	out += "[b]LEVEL 1[/b]  [color=#aaaaaa](Starting Gear)[/color]\n"
	out += "  🧪  Potion  —  Restore 20 HP\n"
	out += "  🛡️  Shield  —  Block next hit\n\n"

	var sorted = QuestManager.item_unlocks.keys()
	sorted.sort()
	for lvl in sorted:
		var item = QuestManager.item_unlocks[lvl]
		var is_unlocked = QuestManager.unlocked_items.has(item)
		var is_equipped  = QuestManager.equipped_items.has(item)

		if not is_unlocked:
			# Locked — show nothing about the item
			out += "[b]LEVEL %d[/b]  [color=#444444]🔒 ???[/color]\n" % lvl
			out += "  [color=#333333]Reach level %d to unlock.[/color]\n\n" % lvl
			continue

		var status_tag = ""
		if is_equipped:
			status_tag = "  [color=#44FF88]✓ Equipped[/color]"
		else:
			status_tag = "  [color=#FFAA44]✓ Unlocked[/color]"

		var emoji = ""
		var desc  = ""
		match item:
			"grindstone": emoji = "🪨"; desc = "2× damage next attack"
			"whip":       emoji = "💥"; desc = "Enemy skips their turn"
			"needle":     emoji = "📌"; desc = "Pierce enemy armor"
			"magnet":     emoji = "🧲"; desc = "Steal an enemy item"

		out += "[b]LEVEL %d[/b]%s\n" % [lvl, status_tag]
		out += "  %s  %s  —  %s\n\n" % [emoji, item.capitalize(), desc]

	rich_text.bbcode_enabled = true
	rich_text.text = out
