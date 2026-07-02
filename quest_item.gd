extends Area2D

# Collectible coin. Press [E] near it to grab it (feeds QuestManager coins,
# which the player later trades to the QuestNPC for the chest key).

var _scene_label: Label = null
var player_nearby: bool = false

func _ready() -> void:
	# Guard so scene-wired connections don't double-bind.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	# Old per-coin world label is superseded by the screen-space PromptHUD.
	for child in get_children():
		if child is Label:
			_scene_label = child
			_scene_label.visible = false
			break

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		QuestManager.collect_coin()
		_spawn_pickup_feedback()
		PromptHUD.release(self)
		queue_free()

# A little "+1 🪙 (n/10)" that floats up and fades. Parented to our parent so
# it outlives this coin being freed.
func _spawn_pickup_feedback() -> void:
	var parent = get_parent()
	if not is_instance_valid(parent):
		return
	var lbl = Label.new()
	lbl.text = "+1  🪙  %d/%d" % [QuestManager.coins_collected, QuestManager.COINS_NEEDED]
	lbl.scale = Vector2(0.4, 0.4)
	lbl.z_index = 100
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	parent.add_child(lbl)
	lbl.global_position = global_position + Vector2(-18, -16)
	var tw = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 26, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.15)
	get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		PromptHUD.request(self, "[E]  Grab Coin")

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)
