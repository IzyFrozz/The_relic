extends Area2D

var prompt_label: Label = null
var player_nearby: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	for child in get_children():
		if child is Label:
			prompt_label = child
			break
	
	if prompt_label:
		prompt_label.visible = false

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		QuestManager.collect_coin()
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		if prompt_label:
			prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if prompt_label:
			prompt_label.visible = false
