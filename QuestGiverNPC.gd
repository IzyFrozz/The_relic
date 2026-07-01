extends CharacterBody2D

# ── Quest NPC (quest giver + relic turn-in) ─────────────────────────────────
# Quest flow:
#   1. Talk to accept the quest.
#   2. Collect 10 coins in the world, bring them here → receive the KEY.
#   3. Take the key to the chest → unlock it → get the Relic.
#   4. Bring the Relic back here and turn it in → WIN.
#
# CharacterBody2D (so it blocks the player). Player detection comes from a child
# Area2D whose body_entered/exited are scene-wired to _on_area_2d_body_*.
# Messages go through DialogueManager; the "[E] …" prompt goes through PromptHUD.

const NPC_NAME := "Street Kid"
const HERO_NAME := "Sir Lance"

var _scene_label: Label = null
var player_nearby: bool = false

func _ready() -> void:
	_scene_label = get_node_or_null("PromptLabel") as Label
	if is_instance_valid(_scene_label):
		_scene_label.visible = false

func _process(_delta: float) -> void:
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if DialogueManager.is_active:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	_handle_interact()

func _handle_interact() -> void:
	if QuestManager.game_won:
		DialogueManager.say(NPC_NAME, "Our whole village is safe because of you. Thank you, hero!")
		return

	# ── 1. Accept the quest ──
	if not QuestManager.quest_accepted:
		QuestManager.quest_accepted = true
		QuestManager.has_unsaved_progress = true
		_update_prompt()
		DialogueManager.start([
			{ "name": NPC_NAME,  "text": "Please, hero! A dragon sealed our village's relic inside an ancient chest." },
			{ "name": NPC_NAME,  "text": "Bring me [b]%d gold coins[/b] and I'll trade you the key to that chest." % QuestManager.COINS_NEEDED },
			{ "name": HERO_NAME, "text": "Ten coins for a key? ...Fine. I'll gather them." },
		])
		return

	# ── 4. Turn in the relic → win ──
	if QuestManager.has_relic:
		QuestManager.has_relic = false
		QuestManager.game_won = true
		PromptHUD.release(self)
		await _say_and_wait([
			{ "name": HERO_NAME, "text": "Here — your village's relic, safe and sound." },
			{ "name": NPC_NAME,  "text": "You did it! You truly saved us all. Thank you, hero!" },
		])
		_trigger_win_screen()
		return

	# ── 3. Has the key, still needs the relic ──
	if QuestManager.has_key:
		DialogueManager.start([
			{ "name": NPC_NAME, "text": "The chest is out there waiting. Use the key, take the relic, and hurry back!" },
		])
		return

	# ── 2. Accepted, no key yet — check coins ──
	if QuestManager.has_enough_coins():
		QuestManager.coins_collected -= QuestManager.COINS_NEEDED
		QuestManager.has_key = true
		QuestManager.has_unsaved_progress = true
		_update_prompt()
		DialogueManager.start([
			{ "name": HERO_NAME, "text": "Here — ten coins, as promised." },
			{ "name": NPC_NAME,  "text": "You actually did it! Take this [b]🔑 key[/b] — open the chest and claim the relic." },
		])
	else:
		DialogueManager.say(NPC_NAME,
			"You've gathered [b]%d of %d[/b] coins so far. Keep looking!" % [QuestManager.coins_collected, QuestManager.COINS_NEEDED])

func _say_and_wait(lines: Array) -> void:
	DialogueManager.start(lines)
	await DialogueManager.dialogue_finished

func _prompt_text() -> String:
	if QuestManager.has_relic:
		return "[E]  Turn in the Relic"
	if QuestManager.quest_accepted and not QuestManager.has_key:
		return "[E]  Deliver Coins"
	return "[E]  Talk"

func _update_prompt() -> void:
	if player_nearby:
		PromptHUD.request(self, _prompt_text())

# Targets the SCRIPTED WinUI (with show_win_screen) so it isn't fooled by any
# other node that happens to be named "WinUI".
func _trigger_win_screen() -> void:
	var win_ui_node: Node = null
	for n in get_tree().root.find_children("WinUI", "", true, false):
		if n.has_method("show_win_screen"):
			win_ui_node = n
			break
	if is_instance_valid(win_ui_node):
		win_ui_node.show_win_screen()
		Engine.time_scale = 0.0
	else:
		push_error("QuestNPC: scripted WinUI not found.")

# ── Child Area2D signals (wired in the scene) ────────────────────────────────
func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		_update_prompt()

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)
