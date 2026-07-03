extends RefCounted

# ── Level-gated mechanics registry ──────────────────────────────────────────
# One tiny module that answers "is mechanic X unlocked yet?" so every future
# level-locked feature (fishing today, more NPCs/mechanics later) reuses the
# same plumbing instead of hardcoding level checks all over.
#
# Usage (preload-const pattern, same as PlayerSkin):
#   const LevelGate = preload("res://LevelGate.gd")
#   if not LevelGate.is_unlocked("fishing"):
#       DialogueManager.say(NPC_NAME, "<in-character brush-off>  " + LevelGate.hint("fishing"))
#       return
#
# The rejection dialogue itself stays in each NPC (each has its own voice);
# this module only owns the requirement data + unlock announcements.
#
# Gates are pure functions of player_level — nothing to save/load.

const GATES := {
	"fishing": {
		"level": 5,
		"label": "Fishing",
		"unlock_toast": "🎣  You feel experienced enough to learn fishing — find the fisherman by the water!",
	},
	# Future gated mechanics go here, e.g.:
	# "blacksmith": { "level": 8, "label": "Forging", "unlock_toast": "⚒️ ..." },
}

static func required_level(id: String) -> int:
	return GATES.get(id, {}).get("level", 1)

static func is_unlocked(id: String) -> bool:
	return QuestManager.player_level >= required_level(id)

# Short player-facing requirement note NPCs can append to their brush-off line.
static func hint(id: String) -> String:
	return "(Reach level %d to unlock %s.)" % [required_level(id), GATES.get(id, {}).get("label", id)]

# Called by QuestManager.gain_xp after each level-up: announces any mechanic
# whose requirement was crossed at exactly this level, so the player learns
# WHERE to go the moment the content opens up.
static func announce_unlocks_at(level: int) -> void:
	for id in GATES:
		var gate: Dictionary = GATES[id]
		if gate.get("level", 1) == level and gate.has("unlock_toast"):
			Toast.show_toast(gate["unlock_toast"])
