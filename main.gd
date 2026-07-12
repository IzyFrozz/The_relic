extends Node2D

# NOTE: Real combat is triggered by MobEnemy.gd when the player enters a
# mob's deadzone (see MobEnemy._on_deadzone_body_entered -> start_combat()).
# This script used to also fire a fake "test combat" on every Space/Enter
# press via a MockEnemy, which crashed the game (it pointed at the wrong
# node and had no real combat data) any time Space/Enter was pressed
# outside of combat, including on the Win/Lose screens. That debug-only
# code has been removed.


func _ready() -> void:
	_apply_respawn_position()
	_maybe_show_intro_tutorial()

# Shown exactly once, the first time a fresh character enters the overworld
# (persisted flag survives save/load so it never repeats). Explains movement,
# interact, the quest log, and points the player at their first objective.
func _maybe_show_intro_tutorial() -> void:
	if QuestManager.intro_tutorial_done:
		return
	QuestManager.intro_tutorial_done = true
	QuestManager.has_unsaved_progress = true
	await get_tree().process_frame
	DialogueManager.start([
		{ "name": "", "text": "Welcome, traveller! A few things before you set out." },
		{ "name": "", "text": "Move with [b]WASD[/b] (or arrow keys) — hold [b]Shift[/b] to sprint." },
		{ "name": "", "text": "Press [b]E[/b] to interact: talk to people, open doors, pick things up." },
		{ "name": "", "text": "Somewhere out here is the [b]🧭 Navigator[/b]. Go and [b]seek them out[/b] — you'll have to find them yourself." },
		{ "name": "", "text": "Once you do, they'll hand you a compass that unlocks your [b]mini-map[/b] and marks where to go. Until then, explore on foot." },
		{ "name": "", "text": "The [b]📜 Quest Log[/b] tracks your objectives too — once open, page it with [b]Q[/b] / [b]E[/b]. Good luck!" },
	])

# On any scene (re)load, drop the player in front of their last-saved Wizard
# checkpoint. ZERO means no checkpoint yet (fresh game) — keep the scene's
# authored player spawn.
func _apply_respawn_position() -> void:
	if QuestManager.player_spawn_position == Vector2.ZERO:
		return
	var player = get_node_or_null("mainplayer")
	if not is_instance_valid(player):
		player = get_tree().root.find_child("mainplayer", true, false)
	if is_instance_valid(player):
		player.global_position = QuestManager.player_spawn_position
		if "velocity" in player:
			player.velocity = Vector2.ZERO
