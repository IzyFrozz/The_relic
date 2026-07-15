extends CharacterBody2D

# ── Navigator NPC ────────────────────────────────────────────────────────────
# The player's first waypoint. The intro tutorial tells the player to seek the
# Navigator; talking here grants the COMPASS (QuestManager.has_compass), which
# turns on the objective marker/arrow on the mini-map (see WorldMap.gd) and
# guides them through the opening quest — starting with the level-1 tutorial mob.
#
# Placed as an Area2D near the player's spawn in main.tscn. Detection is via this
# Area2D's own body_entered/exited (needs a child CollisionShape2D).

const NPC_NAME := "Navigator"

var player_nearby: bool = false
var _talk_marker: Sprite2D = null

func _ready() -> void:
	# Now a CharacterBody2D (so it blocks the player). Player detection comes from
	# a child Area2D, wired here in code (its own body_entered/exited).
	var area := get_node_or_null("Area2D") as Area2D
	if is_instance_valid(area):
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		if not area.body_exited.is_connected(_on_body_exited):
			area.body_exited.connect(_on_body_exited)
	_talk_marker = IconDB.add_talk_marker(self)

# The floating chat icon replaces the old "[E] Talk" text prompt — it just shows
# while the player is in range.
func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		if is_instance_valid(_talk_marker): _talk_marker.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if is_instance_valid(_talk_marker): _talk_marker.visible = false

func _process(_delta: float) -> void:
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if QuestManager.ui_arrow_nav_open or DialogueManager.is_active or QuestManager.is_in_combat:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	_talk()

func _talk() -> void:
	QuestManager.record_npc_talk("navigator")   # counts for "Meet the Locals"
	if not QuestManager.has_compass:
		QuestManager.has_compass = true
		QuestManager.has_unsaved_progress = true
		Toast.show_toast("🧭  Received the Compass! Follow the marker to your objective.")
		DialogueManager.start([
			{ "name": NPC_NAME, "text": "Ah — a fresh face, and lost already. These lands swallow the unprepared, friend." },
			{ "name": NPC_NAME, "text": "Here, take my [b]🧭 Compass[/b]. It always points to whatever matters most for you right now." },
			{ "name": NPC_NAME, "text": "Watch the golden marker on your [b]mini-map[/b] (top-right), or press [b]M[/b] for the full world map." },
			{ "name": NPC_NAME, "text": "First lesson: go [b]learn to fight[/b]. There's a lone brawler just south of here itching for a scrap. The compass will take you right to them." },
		])
	else:
		DialogueManager.say(NPC_NAME, "Keep your eye on the compass marker — it always knows where you're needed next. Safe travels!")
