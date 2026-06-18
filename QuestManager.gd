extends Node

# Quest & Game States
var coins_collected: int = 0
const COINS_NEEDED: int = 10
var chest_unlocked: bool = false
var has_relic: bool = false
var game_won: bool = false
var has_unsaved_progress: bool = true

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
	6: "poison_dart",
	7: "bandage",
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
	"poison_dart":  { "emoji": "☠️", "label": "Poison Dart",  "desc": "Target takes 10 damage per round for 4 rounds. Ignores armor." },
	"battle_horn":  { "emoji": "📯", "label": "Battle Horn",  "desc": "Your next 2 attacks each deal +50% damage." },
	"mirror_ward":  { "emoji": "🪞", "label": "Mirror Ward",  "desc": "The next hit you take is fully reflected back at the attacker." },
	"smoke_bomb":   { "emoji": "💨", "label": "Smoke Bomb",   "desc": "The next attack against you misses completely. Cannot be pierced." },
	"weaken_totem": { "emoji": "🗿", "label": "Weaken Totem", "desc": "Curses the target — their next attack deals 0 damage, and you heal 20 HP instead." },
	"chain_hook":   { "emoji": "⛓️", "label": "Chain Hook",   "desc": "Steal a random item AND cut the target's next attack damage in half." },
	"static_field": { "emoji": "⚡", "label": "Static Field", "desc": "Target cannot use any items on their next turn — forces a basic attack only." },
	"time_warp":    { "emoji": "⏳", "label": "Time Warp",    "desc": "Target skips their next TWO turns." },
	"overcharge":   { "emoji": "🔥", "label": "Overcharge",   "desc": "Next attack ignores armor AND deals 2× damage." },
}

func collect_coin() -> void:
	coins_collected += 1
	has_unsaved_progress = true

# ── Centralized heart-bar renderer ──────────────────────────────────────────
# 1 heart = 20 HP. Caps display at 15 hearts (300 HP) per "lap" so high-HP
# bosses don't spam the screen with dozens of hearts — once HP climbs past
# 300, the SAME 15 slots start refilling from heart #1 again, but in gold,
# representing the next 300-HP block. A third lap (600+) would just repeat
# the gold coloring rather than introduce a new color, which is fine since
# nothing in the game currently has HP anywhere near that high.
const HP_PER_HEART := 20
const HEARTS_PER_LAP := 15
const HP_PER_LAP := HEARTS_PER_LAP * HP_PER_HEART  # 300

func hp_to_hearts(hp: int, max_hp: int) -> String:
	hp = clampi(hp, 0, max_hp)

	var lap = hp / HP_PER_LAP
	if hp > 0 and hp % HP_PER_LAP == 0:
		lap -= 1  # treat exact lap boundaries as "end of previous lap, fully full"

	var max_lap = max_hp / HP_PER_LAP
	if max_hp > 0 and max_hp % HP_PER_LAP == 0:
		max_lap -= 1

	var hp_in_lap = hp - (lap * HP_PER_LAP)

	var total_slots: int
	if lap < max_lap:
		total_slots = HEARTS_PER_LAP
	else:
		var max_hp_in_lap = max_hp - (lap * HP_PER_LAP)
		total_slots = int(ceil(float(max_hp_in_lap) / float(HP_PER_HEART)))
	if total_slots <= 0: total_slots = 1
	if total_slots > HEARTS_PER_LAP: total_slots = HEARTS_PER_LAP

	var full_heart = "💛" if lap >= 1 else "❤️"
	var broken_heart = "💔"
	var empty_heart = "🖤"

	var full_count = hp_in_lap / HP_PER_HEART
	var remainder = hp_in_lap % HP_PER_HEART
	if full_count > total_slots:
		full_count = total_slots
		remainder = 0

	var heart_string = ""
	for i in range(full_count):
		heart_string += full_heart + " "
	var slots_used = full_count
	if remainder > 0 and slots_used < total_slots:
		heart_string += broken_heart + " "
		slots_used += 1
	while slots_used < total_slots:
		heart_string += empty_heart + " "
		slots_used += 1
	return heart_string

# ── Save / Load ──────────────────────────────────────────────────────────
# Core data persistence. The NPC save-point UI (coming in a later pass) will
# call save_game() when the player chooses to save. Restart-on-death and
# restart-on-win both call load_game() so progress reflects your last save,
# not whatever happened to be in memory when you died/won.
const SAVE_PATH := "user://savegame.save"

func save_game() -> void:
	var data = {
		"player_level": player_level,
		"current_xp": current_xp,
		"xp_required": xp_required,
		"MAX_HEALTH": MAX_HEALTH,
		"unlocked_items": unlocked_items,
		"equipped_items": equipped_items,
		"coins_collected": coins_collected,
		"chest_unlocked": chest_unlocked,
		"has_relic": has_relic,
		"game_won": game_won,
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		has_unsaved_progress = false

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	player_level     = parsed.get("player_level", 1)
	current_xp       = parsed.get("current_xp", 0)
	xp_required      = parsed.get("xp_required", 100)
	MAX_HEALTH       = parsed.get("MAX_HEALTH", 100)
	unlocked_items   = parsed.get("unlocked_items", ["potion", "shield"])
	equipped_items   = parsed.get("equipped_items", ["potion", "shield"])
	coins_collected  = parsed.get("coins_collected", 0)
	chest_unlocked   = parsed.get("chest_unlocked", false)
	has_relic        = parsed.get("has_relic", false)
	game_won         = parsed.get("game_won", false)
	player_health    = MAX_HEALTH
	player_shield    = MAX_SHIELD
	has_unsaved_progress = false
	return true

func reset_to_defaults() -> void:
	player_level = 1
	current_xp = 0
	xp_required = 100
	MAX_HEALTH = 100
	unlocked_items = ["potion", "shield"]
	equipped_items = ["potion", "shield"]
	coins_collected = 0
	chest_unlocked = false
	has_relic = false
	game_won = false
	player_health = MAX_HEALTH
	player_shield = MAX_SHIELD
	has_unsaved_progress = false

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
	has_unsaved_progress = true
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
