extends Node

# Quest & Game States
var coins_collected: int = 0
const COINS_NEEDED: int = 10
var chest_unlocked: bool = false
var has_relic: bool = false
var game_won: bool = false

# Combat States
var player_health: int = 100
var MAX_HEALTH: int = 100
var player_shield: int = 3
const MAX_SHIELD: int = 3

# Overworld inventory
var potions_collected: int = 0

var player_overworld_position: Vector2 = Vector2.ZERO
var is_in_combat: bool = false

# === PROGRESSION ===
var player_level := 1
var current_xp := 0
var xp_required := 100

var unlocked_items := ["potion", "shield"]
var equipped_items := ["potion", "shield"]

var item_unlocks := {
	2: "grindstone",
	3: "whip",
	4: "needle",
	5: "magnet"
}

func collect_coin() -> void:
	coins_collected += 1

func has_enough_coins() -> bool:
	return coins_collected >= COINS_NEEDED

func reset_player_health() -> void:
	player_health = MAX_HEALTH
	player_shield = MAX_SHIELD

func gain_xp(amount: int) -> void:
	current_xp += amount
	while current_xp >= xp_required:
		current_xp -= xp_required
		player_level += 1
		MAX_HEALTH += 20
		if item_unlocks.has(player_level):
			unlocked_items.append(item_unlocks[player_level])
		xp_required = int(xp_required * 1.35)
