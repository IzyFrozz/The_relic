extends CanvasLayer

var rich_text: RichTextLabel = null
var close_button: Button = null

func _ready() -> void:
	visible = false
	rich_text    = find_child("RichTextLabel", true, false) as RichTextLabel
	close_button = find_child("CloseButton", true, false) as Button
	if is_instance_valid(close_button):
		close_button.text = "✖  Close"
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
		var status_tag = ""
		if is_unlocked and is_equipped:
			status_tag = "  [color=#44FF88]✓ Equipped[/color]"
		elif is_unlocked:
			status_tag = "  [color=#FFAA44]✓ Unlocked[/color]"
		else:
			var xp_needed = ""
			status_tag = "  [color=#666666]🔒 Locked[/color]"

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
