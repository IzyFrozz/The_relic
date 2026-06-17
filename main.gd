extends Node2D

# NOTE: Real combat is triggered by MobEnemy.gd when the player enters a
# mob's deadzone (see MobEnemy._on_deadzone_body_entered -> start_combat()).
# This script used to also fire a fake "test combat" on every Space/Enter
# press via a MockEnemy, which crashed the game (it pointed at the wrong
# node and had no real combat data) any time Space/Enter was pressed
# outside of combat, including on the Win/Lose screens. That debug-only
# code has been removed.


func _ready() -> void:
	pass
