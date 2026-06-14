extends CanvasLayer

var rich_text: RichTextLabel = null
var close_button: Button = null

func _ready() -> void:
	visible = false
	rich_text = find_child("RichTextLabel", true, false) as RichTextLabel
	close_button = find_child("CloseButton", true, false) as Button
	if is_instance_valid(close_button):
		close_button.pressed.connect(func(): visible = false)

func refresh_display() -> void:
	if not is_instance_valid(rich_text): return

	var output = "[b]ITEM UNLOCK ROADMAP[/b]\n\n"

	# Level 1 — always unlocked from start
	output += "[b]LEVEL 1[/b]\n"
	output += "  • Potion\n"
	output += "  • Shield\n\n"

	# Levels 2+ from item_unlocks dict
	var sorted_levels = QuestManager.item_unlocks.keys()
	sorted_levels.sort()
	for lvl in sorted_levels:
		var item = QuestManager.item_unlocks[lvl]
		var is_unlocked = QuestManager.unlocked_items.has(item)
		var status = " ✓" if is_unlocked else " 🔒"
		output += "[b]LEVEL %d[/b]%s\n" % [lvl, status]
		output += "  • %s\n\n" % item.capitalize()

	rich_text.bbcode_enabled = true
	rich_text.text = output
