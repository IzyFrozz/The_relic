extends Node

# Quest & Game States
var coins_collected: int = 0
const COINS_NEEDED: int = 10
var chest_unlocked: bool = false
var has_relic: bool = false
var game_won: bool = false

# Combat States
var player_health: int = 100
var MAX_HEALTH: int = 100      # 🛠️ FIXED: Changed from 'const' to 'var' so it can scale up!
var player_shield: int = 3 
const MAX_SHIELD: int = 3

# 🧪 NEW: Persistent overworld item inventory container
var potions_collected: int = 0

var player_overworld_position: Vector2 = Vector2.ZERO
var is_in_combat: bool = false

func collect_coin() -> void:
	coins_collected += 1

func has_enough_coins() -> bool:
	return coins_collected >= COINS_NEEDED

func reset_player_health() -> void:
	player_health = MAX_HEALTH
	player_shield = MAX_SHIELD
