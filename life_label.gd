extends Label

func _process(_delta: float) -> void:
	# 1. Hide during active combat loops
	if QuestManager.is_in_combat:
		visible = false
		return
	
	# 2. Hide if a Victory or Game Over screen overlay is visible
	if _is_end_screen_active():
		visible = false
		return
	
	# 3. Safe to show and refresh when strictly back in normal overworld exploration
	visible = true
	_update_hp_display()

func _is_end_screen_active() -> bool:
	var root_node = get_tree().root
	
	# Common node names for your win/die screens. 
	# (Feel free to update these strings if your actual scene nodes use different names!)
	var target_screens = ["LoseUI", "WinUI", "DeathScreen", "VictoryScreen", "VictoryUI"]
	
	for screen_name in target_screens:
		var screen = root_node.find_child(screen_name, true, false)
		if is_instance_valid(screen) and screen.visible:
			return true
			
	return false

func _update_hp_display() -> void:
	var hp: int = QuestManager.player_health
	var max_hp: int = QuestManager.MAX_HEALTH
	var heart_string = QuestManager.hp_to_hearts(hp, max_hp)
	text = "HP: " + heart_string + "(%d HP/ %d MaxHP)" % [hp, max_hp]
