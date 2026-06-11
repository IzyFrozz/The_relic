extends Area2D

@onready var prompt_label: Label = get_node_or_null("InteractPrompt")
@onready var win_ui: CanvasLayer = get_node_or_null("WinUI")

var player_nearby: bool = false

func _ready() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false
	if is_instance_valid(win_ui):
		win_ui.visible = false
		
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		if QuestManager.game_won:
			return

		if QuestManager.has_relic:
			QuestManager.has_relic = false
			QuestManager.game_won = true
			
			if is_instance_valid(prompt_label):
				prompt_label.visible = false
			
			trigger_black_win_screen()
		else:
			if is_instance_valid(prompt_label):

				prompt_label.text = "Ribbit! Relich65hu6n!! Ribbit!!!"

func trigger_black_win_screen() -> void:
	# 🎯 GLOBAL RADAR HUNT: Scans the entire active game tree to find your lifeLabel node
	var life_label = get_tree().root.find_child("lifeLabel", true, false)
	if is_instance_valid(life_label):
		life_label.visible = false
		print("🎯 Success: Overworld HP label has been hidden!")
	else:
		print("⚠️ WARNING: Could not find 'lifeLabel' anywhere in the active game tree structure.")
	
	# Also hunt down and hide the container panel or UI canvas layer if needed
	var overworld_ui = get_tree().root.find_child("UI", true, false)
	if is_instance_valid(overworld_ui):
		overworld_ui.visible = false
	
	# 🏆 SHOW FULLSCREEN WIN INTERFACE
	if is_instance_valid(win_ui):
		win_ui.visible = true
		Engine.time_scale = 0.0 
	else:
		print("❌ WIN ERROR: WinUI CanvasLayer node cannot be found under Frog NPC.")

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		if is_instance_valid(prompt_label):
			if QuestManager.game_won:
				prompt_label.text = "Thank you for saving our relic!"
			elif QuestManager.has_relic:
				prompt_label.text = "[E] Give Ancient Relic"
			else:
				prompt_label.text = "[E] Talk to Frog Man"
			prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if is_instance_valid(prompt_label):
			prompt_label.visible = false
