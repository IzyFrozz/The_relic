extends Node2D

@onready var combat_ui = $GameUI
var active_enemy = null

func _ready() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		print("Simulating enemy interaction via Spacebar...")
		var mock_enemy = MockEnemy.new()
		start_combat(mock_enemy)

func start_combat(enemy_object: Object) -> void:
	active_enemy = enemy_object
	if combat_ui:
		print("Main Engine: Opening Combat Screen...")
		combat_ui.open_combat_screen(active_enemy)
		combat_ui.start_player_turn()
	else:
		print("ERROR: main.gd cannot find the GameUI node!")

# --- MOCK ENEMY — Completely mirrors properties MobEnemy.gd exposes ---
class MockEnemy:
	var enemy_level: int = 1
	var enemy_health: int = 100
	var enemy_max_health: int = 100
	var cycles_until_drop: int = 1
	var drop_round_index: int = 0
	var current_items_per_deal: int = 2
	var player_inventory: Array = ["potion", "shield", "grindstone", "whip", "needle"]
	var enemy_inventory: Array = ["potion", "shield", "grindstone"]
	var player_active_armor: bool = false
	var player_sharpened: bool = false
	var player_piercing: bool = false
	var player_is_disarmed: bool = false
	var enemy_active_armor: bool = false
	var enemy_sharpened: bool = false
	var enemy_piercing: bool = false
	var enemy_is_disarmed: bool = false
