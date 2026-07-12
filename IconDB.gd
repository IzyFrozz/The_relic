extends Node

# ── Icon database ────────────────────────────────────────────────────────────
# Autoloaded. Maps a game concept id -> a texture in Asset/Selected Icon/. UI code
# calls IconDB.tex("potion"): it returns the Texture2D if the file exists, else
# null — so callers fall back to their emoji automatically and a half-finished
# icon set still renders cleanly (icons where we have them, emoji elsewhere).
#
# Filenames are the artist-chosen names in the folder (spaces/case preserved).

const DIR := "res://Asset/Selected Icon/"

# concept id -> filename (without the folder)
const MAP := {
	# ── Combat items (match QuestManager.ITEM_META ids) ──
	"potion":          "fb266.png",              # a healing potion from the fb265-272 set
	"shield":          "fb853.png",              # shield set fb853-860
	"grindstone":      "grindstone.png",
	"whip":            "whip.png",
	"needle":          "needle.png",
	"magnet":          "magnet.png",
	"bandage":         "bandage.png",
	"poison_dart":     "poison dart.png",
	"battle_horn":     "lifesteal_vial.png",     # "Lifesteal Vial"
	"mirror_ward":     "mirror ward.png",
	"smoke_bomb":      "smoke bomb.png",
	"weaken_totem":    "weaken totem.png",
	"chain_hook":      "chain hook.png",
	"static_field":    "static field.png",
	"time_warp":       "time warp.png",
	"overcharge":      "overcharge.png",
	"phoenix_feather": "phoenix feather.png",
	"clone":           "clone.png",
	"relic":           "Relic.png",

	# ── Currency / world objects ──
	"coin":            "gold coin.png",
	"supply_crate":    "supply crate.png",
	"chest":           "chest icon.png",
	"reward":          "reward.png",

	# ── HUD / progression ──
	"level_up":        "level_up.png",
	"heart_full":      "red heart.png",
	"map":             "map.png",
	"trophy":          "trophy.png",
	"skull":           "skull label.png",

	# ── Menu / misc ──
	"key":             "key.png",
	"save":            "save.png",
	"load":            "load.png",
	"settings":        "settings.png",
	"help":            "help.png",
	"loadout_station": "loadout_station.png",
	"loadout_bag":     "pouch.png",          # the 🎒 in the Roadmap loadout-slot lines
	"quest_scroll":    "quest book.png",     # quest log / markers
	"talk":            "chat.png",           # talk-to-NPC quests
	"audio":           "music node icon.png",

	# ── Fishing ──
	"fishing_rod":     "fishing_rod_basic.png",

	# ── Stamina bar states ──
	"stamina_full":    "green stamina icon.png",
	"stamina_low":     "yellow stamina icon.png",
	"stamina_empty":   "red stamina icon.png",
}

var _cache: Dictionary = {}

# Returns the Texture2D for `id`, or null if there's no mapped/imported file.
func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var result: Texture2D = null
	if MAP.has(id):
		var path: String = DIR + MAP[id]
		if ResourceLoader.exists(path):
			result = load(path) as Texture2D
	_cache[id] = result
	return result

func has(id: String) -> bool:
	return tex(id) != null
