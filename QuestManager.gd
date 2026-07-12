extends Node

var coins_collected: int = 0
const COINS_NEEDED: int = 10
var chest_unlocked: bool = false
var has_relic: bool = false
var game_won: bool = false
var quest_accepted: bool = false   # true once the QuestNPC gives the quest
var has_key: bool = false           # got from the QuestNPC after delivering 10 coins; opens the chest
var has_unsaved_progress: bool = true

# Character creation — chosen at "Start New Game", permanent for the run, saved.
var player_name: String = "Hero"
var player_scale_x: float = 1.0
var player_scale_y: float = 1.0
# Palette-swap colours (default = the sprite's original shades).
# Five independent groups on the repainted sprite — hair and shoes share the
# same browns on the sheet but are split by the region mask, so they can be
# recolored separately.
var hair_color: Color = Color("573a23")
var shirt_color: Color = Color("8f0303")
var pants_color: Color = Color("2c65b5")
var shoes_color: Color = Color("573a23")
var skin_color: Color = Color("ac7b5d")

var player_health: int = 100
var MAX_HEALTH: int = 100
var player_shield: int = 3
const MAX_SHIELD: int = 3

var potions_collected: int = 0
var player_overworld_position: Vector2 = Vector2.ZERO
# Where the player respawns on any restart (flee/death/menu). Set when the
# player saves at a Wizard checkpoint; persisted in the save file. ZERO means
# "no checkpoint yet" — the scene's authored player position is used instead.
var player_spawn_position: Vector2 = Vector2.ZERO
var is_in_combat: bool = false
# True while a UI popup that steals Q/E for arrow-navigation is open (e.g. the
# quest log). Overworld "interact" handlers check this so pressing E/Q to page a
# popup can't also enter a house or talk to an NPC. Movement/combat stay allowed.
var ui_arrow_nav_open: bool = false
# True while the fishing minigame is on screen — freezes overworld movement and
# hides the HUD/interact prompt, like combat does.
var is_fishing: bool = false

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
	# ── Side-quest reward items (not level-gated; earned by completing quests) ──
	"phoenix_feather": { "emoji": "🪶", "label": "Phoenix Feather", "desc": "Passive safety net (can't be used by hand). The moment you'd die it auto-revives you to 40 HP, then goes dormant for 5+ turns — the wait grows each time it triggers. Only one at a time." },
	"clone":           { "emoji": "👥", "label": "Mirror Clone",    "desc": "Summons a ghostly double in front of you. On your attack the clone strikes first for 20, then you strike (buffs apply to you) — two hits in one turn. The clone also soaks the enemy's next hit, then fades." },
	# ── The Ancient Relic (quest item that doubles as the ultimate loadout item) ──
	"relic":           { "emoji": "🏺", "label": "Ancient Relic",   "desc": "The strongest item alive. Once it's in your bag it charges from damage traded in a fight; when it GLOWS, unleash 40 unblockable damage and heal 20, cleansing your afflictions. Consumed on use (back to the crate pool), and each use it demands more charge. Only one at a time. Turn it in to win." },
}

# ── Side quest state (see SideQuestDB.gd for definitions) ────────────────────
# Everything here saves/loads. States: rumour / available / active / done.
#   rumour    — a vague hint; the player must trigger it in the world (fight,
#               collect, talk…) before it reveals and can be activated
#   available — revealed & startable (basic quests begin here); has Activate
#   active    — accepted & tracking progress (capped at MAX_ACTIVE_QUESTS)
#   done      — completed, reward granted
const SideQuestDB = preload("res://SideQuestDB.gd")
const MAX_ACTIVE_QUESTS := 3              # how many side quests can be active at once
var side_quest_states: Dictionary = {}    # id -> state string
var side_quest_progress: Dictionary = {}  # id -> int progress
var coins_lifetime: int = 0               # never decreases (coin_hoarder)
var potions_lifetime: int = 0             # never decreases (herbalist)
var fish_caught: int = 0                  # total fish reeled in
var fishing_tutorial_done: bool = false   # fisherman's how-to shown once
var intro_tutorial_done: bool = false     # controls/goal intro shown once, right after char creation
var combat_tutorial_done: bool = false    # "how to fight" shown once, at the tutorial mob's first pull
var tutorial_mob_defeated: bool = false   # the one guided-combat mob never respawns once beaten
var enemies_defeated: int = 0             # lifetime kills (drives rumour reveals)
var talked_npcs: Array = []               # distinct npc ids the player has talked to
# ── Map & compass (see WorldMap.gd / NavigatorNPC.gd) ──
var has_compass: bool = false             # granted by the Navigator; unlocks the compass + map markers
var explored_cells: Dictionary = {}       # "cx,cy" -> true, fog-of-war reveal (persisted)
var relic_uses: int = 0                   # lifetime relic activations — raises the charge requirement each time
signal side_quests_changed               # HUD listens to refresh the quest log

# Called once at character creation and defensively on load: seed any quest
# that has no recorded state yet. Basic quests start "available"; everything
# else starts "rumour" (a hint the player must trigger in the world).
func init_side_quests() -> void:
	for id in SideQuestDB.QUESTS:
		if not side_quest_states.has(id):
			side_quest_states[id] = "available" if id in SideQuestDB.INITIALLY_AVAILABLE else "rumour"
		# Legacy saves used "locked" for un-revealed quests — migrate to "rumour".
		elif side_quest_states[id] == "locked":
			side_quest_states[id] = "rumour"
		if not side_quest_progress.has(id):
			side_quest_progress[id] = 0
	side_quests_changed.emit()

func side_quest_ids_in_state(state: String) -> Array:
	var out: Array = []
	for id in SideQuestDB.QUESTS:            # iterate defs for stable order
		if side_quest_states.get(id, "rumour") == state:
			out.append(id)
	return out

func active_quest_count() -> int:
	return side_quest_ids_in_state("active").size()

func accept_side_quest(id: String) -> void:
	if side_quest_states.get(id, "rumour") != "available":
		return
	if active_quest_count() >= MAX_ACTIVE_QUESTS:
		Toast.show_toast("📋  Quest log full (%d/%d) — finish one first." % [MAX_ACTIVE_QUESTS, MAX_ACTIVE_QUESTS])
		return
	side_quest_states[id] = "active"
	has_unsaved_progress = true
	var d = SideQuestDB.get_def(id)
	Toast.show_toast("%s  Quest activated: %s" % [d.get("emoji", "📜"), d.get("title", id)])
	side_quests_changed.emit()

# Central event hook. Gameplay code calls this with an event key and optional
# context; every ACTIVE quest of a matching type advances or completes, and any
# RUMOUR whose reveal trigger just fired is revealed to "available".
func notify_quest_event(event: String, ctx: Dictionary = {}) -> void:
	if event == "enemy_defeated":
		enemies_defeated += 1
	var changed := false
	for id in side_quest_ids_in_state("active"):
		var d = SideQuestDB.get_def(id)
		if _event_matches_quest(event, d, ctx):
			changed = _advance_side_quest(id, d) or changed
	changed = _check_rumour_reveals() or changed
	if changed:
		side_quests_changed.emit()

# Reveal any rumour whose trigger condition is now met. Returns true if any
# rumour flipped to "available".
func _check_rumour_reveals() -> bool:
	var revealed := false
	for id in side_quest_ids_in_state("rumour"):
		if _rumour_reveal_met(id):
			side_quest_states[id] = "available"
			has_unsaved_progress = true
			revealed = true
			var d = SideQuestDB.get_def(id)
			Toast.show_toast("❗ New quest available: %s %s" % [d.get("emoji", "📜"), d.get("title", id)])
	return revealed

func _rumour_reveal_met(id: String) -> bool:
	var rv: Dictionary = SideQuestDB.get_def(id).get("reveal", {})
	var need: int = int(rv.get("count", 1))
	match rv.get("event", ""):
		"enemy_defeated":   return enemies_defeated >= need
		"coin_lifetime":    return coins_lifetime >= need
		"potion_collected": return potions_lifetime >= need
		"fish_caught":      return fish_caught >= need
		"npc_talked":       return talked_npcs.has(rv.get("npc", ""))
	return false

func _event_matches_quest(event: String, d: Dictionary, ctx: Dictionary) -> bool:
	var qtype: String = d.get("type", "")
	match qtype:
		"kill_count":
			return event == "enemy_defeated"
		"loadout_kill":
			if event != "enemy_defeated": return false
			for it in d.get("params", {}).get("items", []):
				if not equipped_items.has(it): return false
			return true
		"underdog_kill":
			if event != "enemy_defeated": return false
			var diff: int = d.get("params", {}).get("level_diff", 1)
			return ctx.get("enemy_level", 0) - player_level >= diff
		"coin_lifetime":
			return event == "coin_lifetime"
		"potion_count":
			return event == "potion_collected"
		"fish_count":
			return event == "fish_caught"
		"talk_npcs":
			return event == "npc_talked"
	return false

# Returns true if the quest's tracked count changed.
func _advance_side_quest(id: String, d: Dictionary) -> bool:
	var qtype: String = d.get("type", "")
	var goal: int = d.get("goal", 1)
	var new_progress: int
	match qtype:
		"coin_lifetime":  new_progress = coins_lifetime
		"potion_count":   new_progress = potions_lifetime
		"fish_count":     new_progress = fish_caught
		"talk_npcs":
			var need: Array = d.get("params", {}).get("npcs", [])
			var hit := 0
			for n in need:
				if talked_npcs.has(n): hit += 1
			new_progress = hit
		_:                new_progress = side_quest_progress.get(id, 0) + 1   # per-event counters
	if new_progress == side_quest_progress.get(id, 0):
		return false
	side_quest_progress[id] = new_progress
	has_unsaved_progress = true
	if new_progress >= goal:
		_complete_side_quest(id, d)
	return true

func _complete_side_quest(id: String, d: Dictionary) -> void:
	side_quest_states[id] = "done"
	var reward: Dictionary = d.get("reward", {})
	var parts: Array = []
	if reward.has("xp"):
		gain_xp(reward["xp"])          # may itself level up / announce unlocks
		parts.append("+%d XP" % reward["xp"])
	if reward.has("item"):
		var item_id: String = reward["item"]
		if not unlocked_items.has(item_id):
			unlocked_items.append(item_id)
		var meta = ITEM_META.get(item_id, {})
		parts.append("%s %s unlocked" % [meta.get("emoji", "🎁"), meta.get("label", item_id)])
	Toast.show_toast("✅  Quest complete: %s   (%s)" % [d.get("title", id), "  ".join(parts)])
	has_unsaved_progress = true

# Record talking to an npc (drives talk_npcs quests + village_census).
func record_npc_talk(npc_id: String) -> void:
	if not talked_npcs.has(npc_id):
		talked_npcs.append(npc_id)
		has_unsaved_progress = true
		notify_quest_event("npc_talked", {"npc": npc_id})

# Called by the fishing minigame each time a fish is successfully reeled in.
func record_fish_caught() -> void:
	fish_caught += 1
	has_unsaved_progress = true
	notify_quest_event("fish_caught")

# Unlocks one random combat item the player doesn't own yet (the "rare catch").
# Returns the item id, or "" if everything is already unlocked.
func unlock_random_new_item() -> String:
	var pool: Array = []
	for id in ITEM_META:
		if not unlocked_items.has(id):
			pool.append(id)
	if pool.is_empty():
		return ""
	var pick: String = pool[randi() % pool.size()]
	unlocked_items.append(pick)
	has_unsaved_progress = true
	return pick

# ── Relic as a usable item ────────────────────────────────────────────────────
# Obtaining the relic also unlocks it as an equippable combat item (the single
# strongest in the game). Turning it in wins the run and permanently removes it
# from the loadout so post-game play no longer has access to it.
func grant_relic() -> void:
	has_relic = true
	if not unlocked_items.has("relic"):
		unlocked_items.append("relic")
	has_unsaved_progress = true

func turn_in_relic() -> void:
	has_relic = false
	game_won = true
	unlocked_items.erase("relic")
	equipped_items.erase("relic")
	has_unsaved_progress = true

func collect_coin() -> void:
	# Coins are strictly the 10 win-gating pickups scattered in the world — no
	# lifetime tally, no farmable quest. (coins_lifetime is retained only so old
	# saves still load; it is no longer used for anything.)
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
# Runtime-only (never written to disk): true once THIS session has an in-game
# save or was loaded from a slot. Drives flee/death behaviour — a brand-new run
# that has never been saved must NOT reload a stale slot from another session.
var session_saved_once: bool = false
# Which of the 3 menu slots this play session belongs to (0 = a fresh run not yet
# bound to a slot). In-game saves always target THIS slot — so a session's saves
# stay with its own character/slot instead of overwriting another one. The 3 menu
# slots are the 3 separate sessions; the in-game save is just the current one.
var active_session_slot: int = 0

func _slot_path(slot: int) -> String:
	return "%s%d.save" % [SAVE_PATH_PREFIX, slot]

func save_game(slot: int = 1) -> void:
	last_used_slot = slot
	active_session_slot = slot   # this session now lives in this slot
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
		"quest_accepted":    quest_accepted,
		"has_key":           has_key,
		"player_name":       player_name,
		"player_scale_x":    player_scale_x,
		"player_scale_y":    player_scale_y,
		"hair_color":        hair_color.to_html(false),
		"shirt_color":       shirt_color.to_html(false),
		"pants_color":       pants_color.to_html(false),
		"shoes_color":       shoes_color.to_html(false),
		"skin_color":        skin_color.to_html(false),
		"spawn_x":           player_spawn_position.x,   # Vector2 isn't JSON-native; store components
		"spawn_y":           player_spawn_position.y,
		"play_time_seconds": play_time_seconds,
		"defeated_enemies":  defeated_enemies,   # persists mob kill/respawn state across saves
		"side_quest_states":   side_quest_states,
		"side_quest_progress": side_quest_progress,
		"coins_lifetime":      coins_lifetime,
		"potions_lifetime":    potions_lifetime,
		"fish_caught":         fish_caught,
		"fishing_tutorial_done": fishing_tutorial_done,
		"intro_tutorial_done":   intro_tutorial_done,
		"combat_tutorial_done":  combat_tutorial_done,
		"tutorial_mob_defeated": tutorial_mob_defeated,
		"enemies_defeated":    enemies_defeated,
		"talked_npcs":         talked_npcs,
		"has_compass":         has_compass,
		"explored_cells":      explored_cells,
		"relic_uses":          relic_uses,
	}
	var f = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		has_unsaved_progress = false
		session_saved_once = true   # this session now has a save to return to

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
	_migrate_item_ids()   # war_banner → clone, drop any items no longer in ITEM_META
	coins_collected   = parsed.get("coins_collected",    0)
	chest_unlocked    = parsed.get("chest_unlocked",     false)
	has_relic         = parsed.get("has_relic",          false)
	game_won          = parsed.get("game_won",           false)
	quest_accepted    = parsed.get("quest_accepted",     false)
	has_key           = parsed.get("has_key",            false)
	player_name       = parsed.get("player_name",        "Hero")
	player_scale_x    = parsed.get("player_scale_x",     1.0)
	player_scale_y    = parsed.get("player_scale_y",     1.0)
	# Legacy saves stored Outfit/Sash/Skin — map them onto the new five groups
	# (old Outfit covered hair+tunic+pants browns; old Sash was the blue accent).
	var legacy_outfit: String = parsed.get("outfit_color", "573a23")
	var legacy_sash: String   = parsed.get("sash_color",   "2c65b5")
	hair_color        = Color(parsed.get("hair_color",  legacy_outfit))
	shirt_color       = Color(parsed.get("shirt_color", "8f0303"))
	pants_color       = Color(parsed.get("pants_color", legacy_sash))
	shoes_color       = Color(parsed.get("shoes_color", legacy_outfit))
	skin_color        = Color(parsed.get("skin_color",  "ac7b5d"))
	player_spawn_position = Vector2(parsed.get("spawn_x", 0.0), parsed.get("spawn_y", 0.0))
	play_time_seconds = parsed.get("play_time_seconds",  0.0)
	var raw_defeated  = parsed.get("defeated_enemies",   {})
	defeated_enemies  = raw_defeated if typeof(raw_defeated) == TYPE_DICTIONARY else {}
	# ── Side quests ──
	var raw_states    = parsed.get("side_quest_states",   {})
	side_quest_states = raw_states if typeof(raw_states) == TYPE_DICTIONARY else {}
	var raw_prog      = parsed.get("side_quest_progress", {})
	side_quest_progress = raw_prog if typeof(raw_prog) == TYPE_DICTIONARY else {}
	# JSON restores dict int values as floats — coerce progress back to int.
	for k in side_quest_progress:
		side_quest_progress[k] = int(side_quest_progress[k])
	coins_lifetime    = int(parsed.get("coins_lifetime",   0))
	potions_lifetime  = int(parsed.get("potions_lifetime", 0))
	fish_caught       = int(parsed.get("fish_caught",      0))
	fishing_tutorial_done = bool(parsed.get("fishing_tutorial_done", false))
	intro_tutorial_done   = bool(parsed.get("intro_tutorial_done",   false))
	combat_tutorial_done  = bool(parsed.get("combat_tutorial_done",  false))
	tutorial_mob_defeated = bool(parsed.get("tutorial_mob_defeated", false))
	enemies_defeated  = int(parsed.get("enemies_defeated", 0))
	var raw_talked    = parsed.get("talked_npcs", [])
	talked_npcs       = raw_talked if typeof(raw_talked) == TYPE_ARRAY else []
	has_compass       = bool(parsed.get("has_compass", false))
	var raw_explored  = parsed.get("explored_cells", {})
	explored_cells    = raw_explored if typeof(raw_explored) == TYPE_DICTIONARY else {}
	relic_uses        = int(parsed.get("relic_uses", 0))
	init_side_quests()   # seed any quests missing from an older save
	player_health     = MAX_HEALTH
	player_shield     = MAX_SHIELD
	has_unsaved_progress = false
	session_saved_once = true   # loaded a real slot — flee/death should return to it
	active_session_slot = slot  # this session is bound to the slot it loaded from
	return true

# Bring an older save's item ids up to date: the War Banner became the Mirror
# Clone, and any id that's no longer a real item is dropped so it can't show up
# as a "❓" ghost in the loadout/combat.
func _migrate_item_ids() -> void:
	const RENAMES := {"war_banner": "clone"}
	for arr_name in ["unlocked_items", "equipped_items"]:
		var arr: Array = get(arr_name)
		var out: Array = []
		for it in arr:
			var id: String = RENAMES.get(it, it)
			if ITEM_META.has(id) and not out.has(id):
				out.append(id)
		set(arr_name, out)

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
	quest_accepted = false; has_key = false; player_spawn_position = Vector2.ZERO
	player_health = MAX_HEALTH; player_shield = MAX_SHIELD
	defeated_enemies.clear()
	# Side quests — fresh slate for a new run.
	side_quest_states.clear(); side_quest_progress.clear()
	coins_lifetime = 0; potions_lifetime = 0; fish_caught = 0; enemies_defeated = 0
	fishing_tutorial_done = false
	intro_tutorial_done = false; combat_tutorial_done = false; tutorial_mob_defeated = false
	has_compass = false; explored_cells.clear()
	relic_uses = 0
	talked_npcs.clear()
	init_side_quests()
	has_unsaved_progress = false
	session_saved_once = false   # a brand-new run has nothing to reload yet
	active_session_slot = 0      # not yet bound to a menu slot

# Return the run to its very start while KEEPING the created character (name,
# appearance, scale) and the "tutorial already seen" flags. Used when a run that
# has never been saved flees or dies: instead of loading a stale slot from a
# previous session, the player respawns at the authored start with starting
# gear — "like new, but still their character."
func restart_fresh_run() -> void:
	player_level = 1; current_xp = 0; xp_required = 100; MAX_HEALTH = 100
	unlocked_items = ["potion", "shield"]; equipped_items = ["potion", "shield"]
	coins_collected = 0; chest_unlocked = false; has_relic = false; game_won = false
	quest_accepted = false; has_key = false
	player_spawn_position = Vector2.ZERO   # main.gd falls back to the authored spawn
	player_health = MAX_HEALTH; player_shield = MAX_SHIELD
	is_in_combat = false
	defeated_enemies.clear(); tutorial_mob_defeated = false
	side_quest_states.clear(); side_quest_progress.clear()
	coins_lifetime = 0; potions_lifetime = 0; fish_caught = 0; enemies_defeated = 0
	has_compass = false; explored_cells.clear()
	relic_uses = 0
	talked_npcs.clear()
	init_side_quests()
	# NOTE: player_name/colors/scale and the *_tutorial_done flags are preserved
	# on purpose, and session_saved_once stays false (still an unsaved run).
	has_unsaved_progress = true

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

# ── Golden-heart heal cap ─────────────────────────────────────────────────────
# Healing only ever restores the red hearts (up to HP_PER_LAP = 300). Any HP
# above that — the gold hearts you get from a high MAX_HEALTH — is a per-fight
# bonus buffer that can NOT be healed back once it's spent.
func heal_cap() -> int:
	return mini(MAX_HEALTH, HP_PER_LAP)

func can_heal_player() -> bool:
	return player_health < heal_cap()

# Heal the player by `amount` respecting the gold-heart rule. Never lifts HP
# above heal_cap(), and never lowers it if already in the gold zone.
func heal_player(amount: int) -> void:
	var cap := maxi(heal_cap(), player_health)
	player_health = clampi(player_health + amount, 0, cap)

# ── Relic charge requirement (climbs with every use, persisted) ───────────────
const RELIC_CHARGE_BASE := 100
const RELIC_CHARGE_STEP := 40
func relic_charge_needed() -> int:
	return RELIC_CHARGE_BASE + relic_uses * RELIC_CHARGE_STEP

func gain_xp(amount: int) -> void:
	current_xp += amount
	has_unsaved_progress = true
	while current_xp >= xp_required:
		current_xp -= xp_required
		player_level += 1
		MAX_HEALTH += 20   # keeps growing forever — no level cap
		Toast.show_toast("⭐  Level up!  You're now Level %d  (+20 max HP)" % player_level)
		if item_unlocks.has(player_level):
			var new_item = item_unlocks[player_level]
			if not unlocked_items.has(new_item):
				unlocked_items.append(new_item)
		# Announce any level-gated mechanic that just opened up (LevelGate.gd).
		preload("res://LevelGate.gd").announce_unlocks_at(player_level)
		# Two-stage XP curve: steep early (1.35x) so the first unlocks feel
		# earned, then gentler (1.18x) from level 8 so 20+ stays reachable —
		# with the old flat 1.35x, level 19→20 needed ~30 same-level kills.
		xp_required = int(xp_required * (1.35 if player_level < 8 else 1.18))
