extends Area2D

# ── Old Fisherman ────────────────────────────────────────────────────────────
# Interact (E) to fish. Gated behind level 5 via LevelGate("fishing"): below
# that he brushes the player off. At/above level 5 he launches the fishing
# minigame; a successful catch grants XP, progresses the "Gone Fishing" side
# quest, sometimes a coin, and rarely (5%) a brand-new combat item.
#
# Player detection via this Area2D's body_entered/exited. Place near water in
# main.tscn (do NOT edit map.tscn / foreground.tscn).

const NPC_NAME := "Old Fisherman"
const LevelGate = preload("res://LevelGate.gd")
const FishingMinigame = preload("res://FishingMinigame.gd")

var player_nearby: bool = false
var _fishing_active: bool = false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		PromptHUD.request(self, "[E]  Fish")

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)

func _process(_delta: float) -> void:
	if _fishing_active or QuestManager.is_fishing:
		return
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if QuestManager.ui_arrow_nav_open or DialogueManager.is_active:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	_interact()

func _interact() -> void:
	if not LevelGate.is_unlocked("fishing"):
		DialogueManager.say(NPC_NAME,
			"Fishin's a patient art. Get a bit more road behind you first, then I'll teach you.  " + LevelGate.hint("fishing"))
		return
	_start_fishing()

func _start_fishing() -> void:
	_fishing_active = true
	PromptHUD.release(self)
	var mg = FishingMinigame.new()
	# Nudges harder as the player levels past 5.
	mg.difficulty = 1.0 + float(max(0, QuestManager.player_level - 5)) * 0.05
	mg.finished.connect(_on_fish_result)
	get_tree().current_scene.add_child(mg)

func _on_fish_result(success: bool) -> void:
	_fishing_active = false
	if player_nearby:
		PromptHUD.request(self, "[E]  Fish")
	if not success:
		Toast.show_toast("🎣  The fish slipped the line — cast again!")
		return
	QuestManager.record_fish_caught()   # progresses the "Gone Fishing" quest
	var xp := randi_range(20, 45)
	QuestManager.gain_xp(xp)
	var msg := "🐟  Nice catch!   +%d XP" % xp
	if randf() < 0.05:
		# Rare catch: reel up a brand-new combat item.
		var item := QuestManager.unlock_random_new_item()
		if item != "":
			var meta = QuestManager.ITEM_META.get(item, {})
			msg += "    ✨ RARE FIND: %s %s!" % [meta.get("emoji", "🎁"), meta.get("label", item)]
	elif randf() < 0.4:
		QuestManager.collect_coin()
		msg += "   (+1 coin)"
	Toast.show_toast(msg)
