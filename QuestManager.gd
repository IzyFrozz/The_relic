extends Node

var coins_collected: int = 0
const COINS_NEEDED: int = 10
var chest_unlocked: bool = false
var has_relic: bool = false
var game_won: bool = false
var has_unsaved_progress: bool = true

var player_health: int = 100
var MAX_HEALTH: int = 100
var player_shield: int = 3
const MAX_SHIELD: int = 3

var potions_collected: int = 0
var player_overworld_position: Vector2 = Vector2.ZERO
var is_in_combat: bool = false

var player_level := 1
var current_xp := 0
var xp_required := 100

var unlocked_items: Array = ["potion", "shield"]
var equipped_items: Array = ["potion", "shield"]

var play_time_seconds: float = 0.0

# ── Defeated-enemy / respawn tracking ─────────────────────────────────────────
# Maps a stable enemy_id (string) -> the play_time_seconds timestamp at which
# it was defeated. Enemies remain hidden in the graveyard until
# RESPAWN_COOLDOWN_SECONDS has elapsed on this same persistent clock, so the
# state survives save/load exactly like the play timer does.
var defeated_enemies: Dictionary = {}
const RESPAWN_COOLDOWN_SECONDS := 300.0   # 5 minutes

var item_unlocks := {
	2:  "grindstone",
	3:  "needle",
	4:  "whip",
	5:  "magnet",
	6:  "bandage",
	7:  "poison_dart",
	8:  "battle_horn",
	9:  "smoke_bomb",
	10: "mirror_ward",
	11: "weaken_totem",
	12: "chain_hook",
	13: "static_field",
	14: "time_warp",
	15: "overcharge",
}

const ITEM_META := {
	"potion":       { "emoji": "🧪", "label": "Potion",          "desc": "Restores 20 HP instantly." },
	"shield":       { "emoji": "🛡️", "label": "Shield",          "desc": "Blocks the next incoming hit completely." },
	"grindstone":   { "emoji": "🪨", "label": "Grindstone",      "desc": "Adds +20 damage to your next attack. Stacks with other damage buffs." },
	"whip":         { "emoji": "💥", "label": "Whip",            "desc": "Enemy skips their entire next turn." },
	"needle":       { "emoji": "📌", "label": "Needle",          "desc": "Next strike pierces enemy armor completely." },
	"magnet":       { "emoji": "🧲", "label": "Magnet",          "desc": "Steal one chosen item from the enemy (only from your loadout)." },
	"bandage":      { "emoji": "🩹", "label": "Bandage",         "desc": "Heal 10 HP now, then +10 HP for 2 more rounds." },
	"poison_dart":  { "emoji": "☠️", "label": "Poison Dart",     "desc": "Target takes 10 damage per round for 3 rounds. Ignores armor." },
	"battle_horn":  { "emoji": "🩸", "label": "Lifesteal Vial",  "desc": "Your next attack heals you for 50%% of damage dealt (stacks with damage buffs)." },
	"mirror_ward":  { "emoji": "🪞", "label": "Mirror Ward",     "desc": "Reflects the full incoming hit back at the attacker — including all multipliers." },
	"smoke_bomb":   { "emoji": "💨", "label": "Smoke Bomb",      "desc": "The next attack against you misses completely." },
	"weaken_totem": { "emoji": "🗿", "label": "Weaken Totem",    "desc": "Curses the target — their next attack heals you 20 HP instead of dealing damage." },
	"chain_hook":   { "emoji": "⛓️", "label": "Chain Hook",      "desc": "Steal a random item AND reduce the target's next attack by 20 damage." },
	"static_field": { "emoji": "⚡", "label": "Static Field",    "desc": "Target cannot use any items on their next turn — basic attack only." },
	"time_warp":    { "emoji": "⏳", "label": "Time Warp",       "desc": "Target skips their next TWO turns." },
	"overcharge":   { "emoji": "🔥", "label": "Overcharge",      "desc": "Adds +20 damage AND pierces armor on next attack. Stacks with Grindstone." },
}

func collect_coin() -> void:
	coins_collected += 1
	has_unsaved_progress = true

const HP_PER_HEART := 20
const HEARTS_PER_LAP := 15
const HP_PER_LAP := HEARTS_PER_LAP * HP_PER_HEART

func hp_to_hearts(hp: int, max_hp: int) -> String:
	hp = clampi(hp, 0, max_hp)
	var base_max     = mini(max_hp, HP_PER_LAP)
	var base_current = mini(hp, HP_PER_LAP)
	var base_slots   = int(ceil(float(base_max) / float(HP_PER_HEART)))
	if base_slots <= 0: base_slots = 1
	var overflow_current = maxi(0, hp - HP_PER_LAP)
	var overflow_slots   = int(ceil(float(overflow_current) / float(HP_PER_HEART)))
	var result = _render_heart_segment(base_current, base_slots, "❤️", "💔", "🖤")
	if overflow_slots > 0:
		result += _render_heart_segment(overflow_current, overflow_slots, "💛", "🧡", "🖤")
	return result

func _render_heart_segment(current: int, slots: int, full_sym: String, half_sym: String, empty_sym: String) -> String:
	var full_count = current / HP_PER_HEART
	var remainder  = current % HP_PER_HEART
	if full_count > slots: full_count = slots; remainder = 0
	var s = ""; var used = full_count
	for _i in range(full_count): s += full_sym + " "
	if remainder > 0 and used < slots: s += half_sym + " "; used += 1
	while used < slots: s += empty_sym + " "; used += 1
	return s

const SAVE_PATH_PREFIX := "user://savegame_slot"
var last_used_slot: int = 1

func _slot_path(slot: int) -> String:
	return "%s%d.save" % [SAVE_PATH_PREFIX, slot]

func save_game(slot: int = 1) -> void:
	last_used_slot = slot
	var data = {
		"player_level":      player_level,
		"current_xp":        current_xp,
		"xp_required":       xp_required,
		"MAX_HEALTH":        MAX_HEALTH,
		"unlocked_items":    unlocked_items,
		"equipped_items":    equipped_items,
		"coins_collected":   coins_collected,
		"chest_unlocked":    chest_unlocked,
		"has_relic":         has_relic,
		"game_won":          game_won,
		"play_time_seconds": play_time_seconds,
		"defeated_enemies":  defeated_enemies,   # persists mob kill/respawn state across saves
	}
	var f = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		has_unsaved_progress = false

func load_game(slot: int = 1) -> bool:
	if not FileAccess.file_exists(_slot_path(slot)): return false
	var f = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if not f: return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return false
	last_used_slot    = slot
	player_level      = parsed.get("player_level",      1)
	current_xp        = parsed.get("current_xp",        0)
	xp_required       = parsed.get("xp_required",       100)
	MAX_HEALTH        = parsed.get("MAX_HEALTH",         100)
	unlocked_items    = parsed.get("unlocked_items",     ["potion", "shield"])
	equipped_items    = parsed.get("equipped_items",     ["potion", "shield"])
	coins_collected   = parsed.get("coins_collected",    0)
	chest_unlocked    = parsed.get("chest_unlocked",     false)
	has_relic         = parsed.get("has_relic",          false)
	game_won          = parsed.get("game_won",           false)
	play_time_seconds = parsed.get("play_time_seconds",  0.0)
	var raw_defeated  = parsed.get("defeated_enemies",   {})
	defeated_enemies  = raw_defeated if typeof(raw_defeated) == TYPE_DICTIONARY else {}
	player_health     = MAX_HEALTH
	player_shield     = MAX_SHIELD
	has_unsaved_progress = false
	return true

func get_slot_info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_slot_path(slot)): return {"exists": false}
	var f = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if not f: return {"exists": false}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return {"exists": false}
	return {
		"exists": true,
		"level":  parsed.get("player_level", 1),
		"time":   parsed.get("play_time_seconds", 0.0),
	}

func reset_to_defaults() -> void:
	player_level = 1; current_xp = 0; xp_required = 100; MAX_HEALTH = 100
	unlocked_items = ["potion", "shield"]; equipped_items = ["potion", "shield"]
	coins_collected = 0; chest_unlocked = false; has_relic = false; game_won = false
	player_health = MAX_HEALTH; player_shield = MAX_SHIELD
	defeated_enemies.clear()
	has_unsaved_progress = false

func get_max_equip_slots() -> int:
	if player_level >= 8: return 6
	if player_level >= 6: return 5
	if player_level >= 4: return 4
	if player_level >= 2: return 3
	return 2

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
		xp_required = int(xp_required * 1.35)
