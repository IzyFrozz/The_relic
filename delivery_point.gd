extends Area2D

# ── Ancient Chest ───────────────────────────────────────────────────────────
# Locked until the player brings the KEY from the QuestNPC. Opening it consumes
# the key and grants the Relic.
# Quest order: coins → QuestNPC → key → chest → relic → QuestNPC → win.

const CHEST_CLOSED := preload("res://Asset/Meta data assets files/Visuals/OBJECTS/sprites/chest-closed.png")
const CHEST_OPENED := preload("res://Asset/Meta data assets files/Visuals/OBJECTS/sprites/chest-opened.png")
const HERO_NAME := "Sir Lance"

@onready var chest_sprite: Sprite2D = get_node_or_null("Sprite2D")

var _scene_label: Label = null
var player_nearby: bool = false

func _ready() -> void:
	_scene_label = get_node_or_null("PromptLabel") as Label
	if is_instance_valid(_scene_label):
		_scene_label.visible = false
	# Guard so the scene-wired connection doesn't double-bind.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_update_chest_sprite()

func _process(_delta: float) -> void:
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if DialogueManager.is_active:
		return
	if QuestManager.chest_unlocked:
		DialogueManager.say(HERO_NAME, "The chest is empty now — the relic is already mine.")
		return
	if not QuestManager.has_key:
		if QuestManager.quest_accepted:
			DialogueManager.say(HERO_NAME, "Locked tight. I need the key the Street Kid promised.")
		else:
			DialogueManager.say(HERO_NAME, "An ancient chest, locked fast. Perhaps someone in the village knows of it.")
		return
	# Has the key → open it.
	QuestManager.chest_unlocked = true
	QuestManager.has_relic = true
	QuestManager.has_key = false
	QuestManager.has_unsaved_progress = true
	_update_chest_sprite()
	if player_nearby:
		PromptHUD.request(self, _prompt_text())
	DialogueManager.start([
		{ "name": HERO_NAME, "text": "The key turns... [i]click.[/i]" },
		{ "name": HERO_NAME, "text": "The [b]🏺 Ancient Relic![/b] I must bring this back to the Street Kid." },
	])

func _prompt_text() -> String:
	return "Opened" if QuestManager.chest_unlocked else "[E]  Open Chest"

func _update_chest_sprite() -> void:
	if is_instance_valid(chest_sprite):
		chest_sprite.texture = CHEST_OPENED if QuestManager.chest_unlocked else CHEST_CLOSED

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		PromptHUD.request(self, _prompt_text())

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)
