extends Area2D

# ── Quest NPC — Coin chest / relic quest ──────────────────────────────────
# Placeholder NPC. Attach to a new Area2D in the scene.
# Expects: $PromptLabel, $QuestUI/MenuPanel/StatusLabel

@onready var prompt_label: Label = get_node_or_null("PromptLabel")
@onready var quest_ui: CanvasLayer = get_node_or_null("QuestUI")
var status_label: Label = null

var player_nearby: bool = false

func _ready() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false
	if is_instance_valid(quest_ui):
		quest_ui.visible = false
		var panel = quest_ui.get_node_or_null("MenuPanel")
		if is_instance_valid(panel):
			status_label = panel.get_node_or_null("StatusLabel") as Label
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
		if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
			return

		if QuestManager.chest_unlocked:
			return

		if QuestManager.has_enough_coins():
			QuestManager.chest_unlocked = true
			QuestManager.has_relic = true
			if is_instance_valid(prompt_label):
				prompt_label.text = "Chest Unlocked!"
			show_canvas_popup("✨ ANCIENT RELIC GAINED!!! ✨")
		else:
			var current = str(QuestManager.coins_collected)
			var total = str(QuestManager.COINS_NEEDED)
			show_canvas_popup("It's locked! Need " + total + " coins.\n(Coins: " + current + "/" + total + ")")

func show_canvas_popup(text_to_display: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = text_to_display
	if is_instance_valid(quest_ui):
		quest_ui.visible = true
		await get_tree().create_timer(3.0).timeout
		quest_ui.visible = false

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		if is_instance_valid(prompt_label):
			if QuestManager.chest_unlocked:
				prompt_label.text = "Chest Unlocked!"
			else:
				prompt_label.text = "[E]  Inspect Chest"
			prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if is_instance_valid(prompt_label):
			prompt_label.visible = false
		if is_instance_valid(quest_ui):
			quest_ui.visible = false
