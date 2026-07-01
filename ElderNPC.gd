extends CharacterBody2D

# ── Wizard checkpoint (Elder NPC) ───────────────────────────────────────────
# Save point ONLY. The player can only save here. Saving also records this
# wizard as the respawn anchor: on any restart (flee / death / menu reload) the
# player reappears in front of THIS wizard (see main.gd + QuestManager).
# Fully self-contained so it can be duplicated across regions as a checkpoint —
# each copy just needs its own InteractPrompt label + InteractionArea child.
# Relic turn-in / winning lives on the QuestNPC now, not here.

@onready var prompt_label: Label = get_node_or_null("InteractPrompt")

# Where the player is dropped when respawning at this wizard, relative to it.
# Exported so each duplicated checkpoint can nudge its own "in front" spot.
@export var respawn_offset: Vector2 = Vector2(0, 40)

var player_nearby: bool = false

func _ready() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
		if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
			return
		_open_save()

func _open_save() -> void:
	# Record this wizard as the respawn point BEFORE saving so it lands on disk.
	QuestManager.player_spawn_position = global_position + respawn_offset
	var save_popup = get_tree().root.find_child("SavePopup", true, false)
	if is_instance_valid(save_popup) and save_popup.has_method("open_popup"):
		save_popup.open_popup()
	elif is_instance_valid(prompt_label):
		prompt_label.text = "No save slots found!"

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		PromptHUD.request(self, "[E]  Save Game")

func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		PromptHUD.release(self)
