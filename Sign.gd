extends CharacterBody2D

# ── Starting Sign ────────────────────────────────────────────────────────────
# Replaces the auto-playing intro dialogue. A readable signpost near the player's
# spawn: press [E] to read the "how to play" notes. Re-readable any time.
#
# CharacterBody2D so it blocks the player like other NPCs. Its Sprite2D is a
# PLACEHOLDER (the "?" help icon) — swap the sprite's texture later for real sign
# art. Player detection comes from a child Area2D wired here in code.

const NPC_NAME := "Signpost"

var player_nearby: bool = false
var _marker: Sprite2D = null

# The starting notes shown when the sign is read.
const LINES := [
	{ "name": NPC_NAME, "text": "[b]Welcome, traveller![/b] Read on for how to find your way." },
	{ "name": NPC_NAME, "text": "Move with [b]WASD[/b] or the arrow keys. Hold [b]Shift[/b] to sprint." },
	{ "name": NPC_NAME, "text": "Press [b]E[/b] to interact — talk to folk, open doors, read signs like this one, and pick things up." },
	{ "name": NPC_NAME, "text": "Somewhere out here is the [b]🧭 Navigator[/b]. Seek them out — find them yourself and they'll grant you a compass and map." },
	{ "name": NPC_NAME, "text": "The [b]📜 Quest Log[/b] tracks your objectives (page it with [b]Q[/b] / [b]E[/b] once open). If a mob pulls you into a fight, pick [b]Attack[/b] or an [b]Item[/b] each round." },
	{ "name": NPC_NAME, "text": "That's it — good luck out there, hero!" },
]

func _ready() -> void:
	# Detection via the child Area2D (the body itself just blocks the player).
	var area := get_node_or_null("Area2D") as Area2D
	if is_instance_valid(area):
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		if not area.body_exited.is_connected(_on_body_exited):
			area.body_exited.connect(_on_body_exited)
	# Floating "?" icon instead of the old "[E] Read Sign" text chip.
	_marker = IconDB.add_marker(self, "help")

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		IconDB.set_marker_visible(_marker, true)

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		IconDB.set_marker_visible(_marker, false)

func _process(_delta: float) -> void:
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if QuestManager.ui_arrow_nav_open or DialogueManager.is_active or QuestManager.is_in_combat:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	DialogueManager.start(LINES)
