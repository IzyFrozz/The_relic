extends CanvasLayer

# 🎬 CONFIGURATION: If your idle animation has a different name (like "default" or "walk"), change this text!
@export var player_reset_animation: String = "idle"

var restart_button: Button = null

func _ready() -> void:
	visible = false 
	_find_any_button(self)
	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)

func _find_any_button(current_node: Node) -> void:
	for child in current_node.get_children():
		if child is Button:
			restart_button = child
			return
		_find_any_button(child)

func show_death_screen() -> void:
	visible = true

func _on_restart_button_pressed() -> void:
	# 1. Restore core health metrics and inventory states
	QuestManager.reset_player_health()
	QuestManager.is_in_combat = false
	
	if QuestManager.has_meta("potions_checkpoint"):
		QuestManager.potions_collected = QuestManager.get_meta("potions_checkpoint")
	
	# 2. Safely locate your player node
	var player = get_node_or_null("/root/main/mainplayer")
	if is_instance_valid(player):
		# Teleport back to overworld safety spot
		player.global_position = QuestManager.player_overworld_position
		if "velocity" in player:
			player.velocity = Vector2.ZERO
		
		# 🎬 PLAY PLAYER ANIMATION: Auto-detects your setup and forces a visual reset
		_reset_player_visual_state(player)
	
	# 3. Cleanly dismiss the death interface screen
	visible = false

func _reset_player_visual_state(player_node: Node2D) -> void:
	# Check 1: If your player uses an AnimationPlayer node
	var anim_player = player_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if is_instance_valid(anim_player):
		if anim_player.has_animation(player_reset_animation):
			anim_player.stop() # Stops any old death animation frames
			anim_player.play(player_reset_animation)
			print("🎬 AnimationPlayer reset to: ", player_reset_animation)
			return

	# Check 2: If your player uses an AnimatedSprite2D node instead
	var anim_sprite = player_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(anim_sprite):
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(player_reset_animation):
			anim_sprite.stop()
			anim_sprite.play(player_reset_animation)
			print("🎬 AnimatedSprite2D reset to: ", player_reset_animation)
			return
			
	# Check 3: If your player is just a simple Sprite2D, look for a sibling AnimationPlayer directly inside main
	var backup_anim = player_node.find_child("*Animation*", true, false)
	if is_instance_valid(backup_anim) and backup_anim.has_method("play"):
		backup_anim.call("play", player_reset_animation)
