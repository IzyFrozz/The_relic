extends Label

func _ready() -> void:
	# Find the player node in the scene. 
	# (Make sure your Player path matches your scene tree structure)
	var player = get_node_or_null("/root/MainScene/Player") 
	
	if player:
		# Connect the player's life signal to our local updater function
		player.life_changed.connect(_on_player_life_changed)


func _on_player_life_changed(new_life: int) -> void:
	# Formats the text to read exactly "LIFE: X"
	text = "LIFE: " + str(new_life)
