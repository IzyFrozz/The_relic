extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		# Add to global inventory bag instead of eating immediately
		QuestManager.potions_collected += 1
		QuestManager.potions_lifetime += 1
		SFX.play(SFX.item_pickup)
		QuestManager.notify_quest_event("potion_collected")
		print("🧪 Potion collected and stored! Total stash: ", QuestManager.potions_collected)

		queue_free() # Vaporize from overworld grid map
