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

var potions_collected: int = 0
var player_overworld_position: Vector2 = Vector2.ZERO
var is_in_combat: bool = false

# === PROGRESSION ===
var player_level := 1
var current_xp := 0
var xp_required := 100

# equipped_items drives what spawns in combat — ORDER MATTERS (slot 1, 2, 3...)
var unlocked_items: Array = ["potion", "shield"]
var equipped_items: Array = ["potion", "shield"]

var item_unlocks := {
	2: "grindstone",
	3: "whip",
	4: "needle",
	5: "magnet",
	6: "bandage",
	7: "poison_dart",
	8: "battle_horn",
	9: "smoke_bomb",
	10: "mirror_ward",
	11: "weaken_totem",
	12: "chain_hook",
	13: "static_field",
	14: "time_warp",
	15: "overcharge",
}

# ── Centralized item metadata — single source of truth for every UI that ──
# ── needs to display an item (CombatUI, EquipmentMenu, RoadmapPopup).     ──
const ITEM_META := {
	"potion":       { "emoji": "🧪", "label": "Potion",       "desc": "Restores 20 HP instantly." },
	"shield":       { "emoji": "🛡️", "label": "Shield",       "desc": "Blocks the next incoming hit completely." },
	"grindstone":   { "emoji": "🪨", "label": "Grindstone",   "desc": "Next attack deals 2× damage." },
	"whip":         { "emoji": "💥", "label": "Whip",         "desc": "Enemy skips their entire next turn." },
	"needle":       { "emoji": "📌", "label": "Needle",       "desc": "Next strike pierces enemy armor." },
	"magnet":       { "emoji": "🧲", "label": "Magnet",       "desc": "Steal one chosen item from the enemy." },
	"bandage":      { "emoji": "🩹", "label": "Bandage",      "desc": "Heal 10 HP now, then +10 HP for 2 more rounds." },
	"poison_dart":  { "emoji": "☠️", "label": "Poison Dart",  "desc": "Target takes 8 damage per round for 3 rounds. Ignores armor." },
	"battle_horn":  { "emoji": "📯", "label": "Battle Horn",  "desc": "Your next 2 attacks each deal +50% damage." },
	"mirror_ward":  { "emoji": "🪞", "label": "Mirror Ward",  "desc": "The next hit you take is fully reflected back at the attacker." },
	"smoke_bomb":   { "emoji": "💨", "label": "Smoke Bomb",   "desc": "The next attack against you misses completely. Cannot be pierced." },
	"weaken_totem": { "emoji": "🗿", "label": "Weaken Totem", "desc": "Target's next attack deals 50% less damage." },
	"chain_hook":   { "emoji": "⛓️", "label": "Chain Hook",   "desc": "Steal a random item AND weaken the target's next attack." },
	"static_field": { "emoji": "⚡", "label": "Static Field", "desc": "Next time you're hit, the attacker takes 15 counter damage." },
	"time_warp":    { "emoji": "⏳", "label": "Time Warp",    "desc": "Target skips their next TWO turns." },
	"overcharge":   { "emoji": "🔥", "label": "Overcharge",   "desc": "Next attack ignores armor AND deals 2× damage." },
}

func collect_coin() -> void:
	coins_collected += 1

# Equip slots scale with level: 2 base, 3 @ lvl2, 4 @ lvl4, 5 @ lvl6, 6 @ lvl8.
# This forces players to diversify their loadout as they level instead of
# min-maxing 2 overpowered items forever.
func get_max_equip_slots() -> int:
	var slots = 2
	if player_level >= 2: slots = 3
	if player_level >= 4: slots = 4
	if player_level >= 6: slots = 5
	if player_level >= 8: slots = 6
	return slots

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
			var new_item = item_unlocks[player_level]
			if not unlocked_items.has(new_item):
				unlocked_items.append(new_item)
			# Do NOT auto-add to equipped_items — player must visit station
		xp_required = int(xp_required * 1.35)
