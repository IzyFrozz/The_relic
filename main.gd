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
