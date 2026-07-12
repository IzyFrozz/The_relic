extends RefCounted

# ── Side quest definitions ───────────────────────────────────────────────────
# Pure data + tiny helpers. All live state (states/progress/counters) lives in
# QuestManager so it saves/loads with everything else.
#
#   const SideQuestDB = preload("res://SideQuestDB.gd")
#
# Quest lifecycle:  locked → available → active → done
#   locked    — hidden everywhere until its prerequisite quest completes
#   available — visible at the Notice Board (and in the quest log's "rumors"
#               page) but not tracking progress yet; player must accept it
#   active    — tracked; progress shown in the cyclable quest log
#   done      — completed, reward granted
#
# Definition fields:
#   title/emoji/desc — display
#   teaser           — vague one-line rumor shown on the Rumors page (before the
#                      quest is revealed). Flavour only, no objective.
#   rumour_hint      — clear nudge telling the player how to trigger the reveal
#                      (only on rumour quests). Shown under the teaser.
#   reveal           — trigger that flips a rumour → available (only on rumour
#                      quests): {event, count?, npc?}. event is one of the
#                      notify_quest_event keys; count defaults to 1.
#   how              — objective text shown once available/active
#   type             — "kill_count" | "loadout_kill" | "underdog_kill"
#                    | "coin_lifetime" | "potion_count" | "talk_npcs"
#                    | "fish_count"
#   goal             — target count (talk_npcs: number of distinct npc ids)
#   params           — type-specific (loadout_kill: {items:[...]},
#                      underdog_kill: {level_diff:2}, talk_npcs: {npcs:[...]})
#   reward           — {"xp": int, "item": String (optional)}

const QUESTS := {
	"first_blood": {
		"title": "First Blood", "emoji": "⚔️",
		"teaser": "The wilds are restless — folk say something out there needs putting down.",
		"desc": "The wilds are crawling with mobs. Prove you can hold your own.",
		"how": "Defeat any enemy in combat.",
		"type": "kill_count", "goal": 1, "params": {},
		"reward": { "xp": 90 },
	},
	"armed_to_teeth": {
		"title": "Armed to the Teeth", "emoji": "🎒",
		"teaser": "A grizzled fighter keeps muttering that the best never enter a brawl unprepared.",
		"rumour_hint": "Win a battle to hear him out.",
		"reveal": { "event": "enemy_defeated", "count": 1 },
		"desc": "A real fighter picks the right tools before the fight.",
		"how": "Win a fight with Potion, Shield AND Needle all in your equipped loadout.",
		"type": "loadout_kill", "goal": 1,
		"params": { "items": ["potion", "shield", "needle"] },
		"reward": { "xp": 200 },
	},
	"underdog": {
		"title": "Underdog", "emoji": "🐺",
		"teaser": "Whispers of a beast far too strong for someone your size to face…",
		"rumour_hint": "Speak with a Wizard at a checkpoint to learn more.",
		"reveal": { "event": "npc_talked", "npc": "wizard" },
		"desc": "Beating a stronger foe takes brains, not stats. (You strike first — use it.)",
		"how": "Defeat an enemy at least 2 levels above you.",
		"type": "underdog_kill", "goal": 1,
		"params": { "level_diff": 2 },
		"reward": { "xp": 300, "item": "phoenix_feather" },
	},
	"mob_slayer": {
		"title": "Mob Slayer", "emoji": "💀",
		"teaser": "The village needs the mob numbers thinned. Badly.",
		"rumour_hint": "Defeat a few enemies to draw the village's notice.",
		"reveal": { "event": "enemy_defeated", "count": 3 },
		"desc": "The mobs respawn endlessly. Thin the herd anyway — for the village.",
		"how": "Defeat 5 enemies in total.",
		"type": "kill_count", "goal": 5, "params": {},
		"reward": { "xp": 320 },
	},
	"herbalist": {
		"title": "Herbalist", "emoji": "🧪",
		"teaser": "They say potions grow wild out past the treeline.",
		"desc": "Potions grow wild out there. Stock up before a tough fight.",
		"how": "Collect 3 potions from the overworld.",
		"type": "potion_count", "goal": 3, "params": {},
		"reward": { "xp": 150 },
	},
	"village_census": {
		"title": "Meet the Locals", "emoji": "🗣️",
		"teaser": "New face in town? The locals would like to put a name to it.",
		"desc": "Every face in this village has a story. Introduce yourself around.",
		"how": "Talk to the Street Kid, the Navigator, and a Wizard checkpoint.",
		"type": "talk_npcs", "goal": 3,
		"params": { "npcs": ["street_kid", "wizard", "navigator"] },
		"reward": { "xp": 120 },
	},
	"gone_fishing": {
		"title": "Gone Fishing", "emoji": "🎣",
		"teaser": "The old fisherman keeps hinting the waters here hide more than fish.",
		"desc": "The old fisherman swears the waters here hide more than fish.",
		"how": "Learn fishing from the fisherman (level 5), then catch 3 fish.",
		"type": "fish_count", "goal": 3, "params": {},
		"reward": { "xp": 220 },
	},
}

# Quests that start "available" (startable from the outset). Everything else in
# QUESTS starts as a "rumour" and is revealed by its `reveal` trigger.
const INITIALLY_AVAILABLE := ["first_blood", "herbalist", "village_census", "gone_fishing"]

static func get_def(id: String) -> Dictionary:
	return QUESTS.get(id, {})

static func exists(id: String) -> bool:
	return QUESTS.has(id)

# Vague rumor line shown on the Rumors page before the quest is revealed.
static func teaser(id: String) -> String:
	var d = get_def(id)
	return d.get("teaser", d.get("desc", ""))

# Clear nudge telling the player how to trigger a rumour's reveal.
static func rumour_hint(id: String) -> String:
	return get_def(id).get("rumour_hint", "Keep exploring to uncover more.")

# Progress line for the quest log, e.g. "3 / 5".
static func progress_text(id: String, progress: int) -> String:
	var goal: int = get_def(id).get("goal", 1)
	return "%d / %d" % [mini(progress, goal), goal]

static func reward_text(id: String) -> String:
	var reward: Dictionary = get_def(id).get("reward", {})
	var parts: Array[String] = []
	if reward.has("xp"):
		parts.append("%d XP" % reward["xp"])
	if reward.has("item"):
		var meta: Dictionary = QuestManager.ITEM_META.get(reward["item"], {})
		parts.append("%s %s" % [meta.get("emoji", "🎁"), meta.get("label", reward["item"])])
	return "  +  ".join(parts) if not parts.is_empty() else "—"
