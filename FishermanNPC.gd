extends CharacterBody2D

# ── Old Fisherman ────────────────────────────────────────────────────────────
# The teacher, NOT the fishing spot. Interact (E) to talk: below level 5 he
# brushes the player off; at/above level 5 he runs the one-time how-to tutorial;
# afterwards he just chats and points you to the water. The actual fishing lives
# on the separate FishingSpot ("puddle") node — see FishingSpot.gd.
#
# CharacterBody2D (so it blocks the player like other NPCs). Player detection
# comes from a child Area2D whose body_entered/exited are wired here in code.
# Place near water in main.tscn (do NOT edit map.tscn / foreground.tscn).

const NPC_NAME := "Old Fisherman"
const LevelGate = preload("res://LevelGate.gd")

var player_nearby: bool = false

func _ready() -> void:
	var area := get_node_or_null("Area2D") as Area2D
	if is_instance_valid(area):
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		if not area.body_exited.is_connected(_on_body_exited):
			area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		PromptHUD.request(self, "[E]  Talk")

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)

func _process(_delta: float) -> void:
	if QuestManager.is_fishing:
		return
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if QuestManager.ui_arrow_nav_open or DialogueManager.is_active:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	_interact()

func _interact() -> void:
	if not LevelGate.is_unlocked("fishing"):
		DialogueManager.say(NPC_NAME,
			"Fishin's a patient art. Get a bit more road behind you first, then I'll teach you.  " + LevelGate.hint("fishing"))
		return
	# First time fishing is unlocked → the old man walks the player through it.
	# He no longer casts for you: he sends you to the water's edge to fish.
	if not QuestManager.fishing_tutorial_done:
		QuestManager.fishing_tutorial_done = true
		QuestManager.has_unsaved_progress = true
		var cast_key: String = KeybindManager.key_display("interact")
		var reel_key: String = KeybindManager.key_display("fish_reel")
		DialogueManager.start([
			{ "name": NPC_NAME, "text": "So you're ready to learn the line at last! Sit tight, it's simple enough." },
			{ "name": NPC_NAME, "text": "Step up to the [b]water's edge[/b] and press [b]%s[/b] to cast. You'll get a moment to steady yourself first." % cast_key },
			{ "name": NPC_NAME, "text": "When a fish bites, a green [b]bar[/b] appears. [b]Hold %s[/b] to raise it; let go and it sinks." % reel_key },
			{ "name": NPC_NAME, "text": "Keep that bar [b]over the fish[/b] and the meter fills; let it slip and it drains. Some fish are friskier than others — you'll feel it." },
			{ "name": NPC_NAME, "text": "Fill the meter to the top and she's yours. Now — off to the water with you!" },
		])
		return
	# Already taught → friendly chatter that keeps pointing at the water, with a
	# vague hint that patient anglers pull up more than fish (don't name it).
	var lines := [
		"They're biting well today. Get down to the water and cast a line!",
		"Patience and a steady hand at the water's edge — that's all it takes.",
		"Keep at it, friend. They say the sea gives up [b]rare treasures[/b] to those who fish long enough… not just fish, mind you.",
		"Land enough catches and the tide might reward you with something [b]special[/b]. What, exactly? Well — you'll know it when you reel it up.",
	]
	DialogueManager.say(NPC_NAME, lines[randi() % lines.size()])
