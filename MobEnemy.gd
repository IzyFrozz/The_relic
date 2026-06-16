extends CharacterBody2D

@export var enemy_level: int = 1

@export var battle_player_marker: Marker2D
@export var battle_enemy_marker: Marker2D
@export var graveyard_marker: Marker2D
@export var combat_ui: CanvasLayer
@export var lose_ui: CanvasLayer

var enemy_health: int = 100
var enemy_max_health: int = 100
var enemy_inventory: Array[String] = []
var player_inventory: Array[String] = []
var enemy_item_pool: Array = []

var cycles_until_drop: int = 1
var drop_round_index: int = 0
var current_items_per_deal: int = 1

var player_active_armor: bool = false
var player_sharpened: bool = false
var player_piercing: bool = false
var player_is_disarmed: bool = false

var enemy_active_armor: bool = false
var enemy_sharpened: bool = false
var enemy_piercing: bool = false
var enemy_is_disarmed: bool = false

var player_ref: Node2D = null
var is_in_combat: bool = false
var enemy_overworld_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_initialize_mob_stats_by_character_tier()
	_auto_wire_overworld_signals()


func _auto_wire_overworld_signals() -> void:
	var deadzone_node = find_child("deadzone")
	if deadzone_node and deadzone_node.has_signal("body_entered"):
		if deadzone_node.body_entered.is_connected(_on_deadzone_body_entered):
			deadzone_node.body_entered.disconnect(_on_deadzone_body_entered)
		deadzone_node.body_entered.connect(_on_deadzone_body_entered)


func _initialize_mob_stats_by_character_tier() -> void:
	# HP scales every level, no cap at 4
	enemy_max_health = 80 + (enemy_level * 20)

	# Build enemy pool: always starts with potion+shield, unlocks extras per level
	enemy_item_pool = ["potion", "shield"]
	if enemy_level >= 2: enemy_item_pool.append("grindstone")
	if enemy_level >= 3: enemy_item_pool.append("whip")
	if enemy_level >= 4: enemy_item_pool.append("needle")
	if enemy_level >= 5: enemy_item_pool.append("magnet")

	enemy_health = enemy_max_health
	current_items_per_deal = 1


func _on_deadzone_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer" and not is_in_combat:
		player_ref = body
		start_combat()


func start_combat() -> void:
	is_in_combat = true
	QuestManager.is_in_combat = true

	if is_instance_valid(player_ref) and "velocity" in player_ref:
		player_ref.velocity = Vector2.ZERO

	enemy_overworld_position = self.global_position
	_initialize_mob_stats_by_character_tier()

	player_inventory.clear()
	enemy_inventory.clear()
	_reset_all_combat_modifiers()

	drop_round_index = 0
	cycles_until_drop = 1

	QuestManager.player_health = QuestManager.MAX_HEALTH
	_apply_supply_drop_rewards()

	if is_instance_valid(player_ref):
		QuestManager.player_overworld_position = player_ref.global_position
		if is_instance_valid(battle_player_marker):
			player_ref.global_position = battle_player_marker.global_position
		if player_ref.has_method("face_up"):
			player_ref.face_up()

	if is_instance_valid(battle_enemy_marker):
		self.global_position = battle_enemy_marker.global_position

	if is_instance_valid(combat_ui):
		combat_ui.open_combat_screen(self)
		combat_ui.start_player_turn()


func use_player_item(item_type: String) -> void:
	if not item_type in player_inventory:
		return

	match item_type:
		"magnet":
			if enemy_inventory.size() == 0:
				if combat_ui: combat_ui.display_round_history("🧲 Magnet fizzled — Enemy hand is empty!", true)
				if combat_ui: combat_ui._refresh_ui_states()
				return
			if combat_ui:
				var chosen = await combat_ui.show_magnet_choice_popup(enemy_inventory)
				if chosen != "":
					player_inventory.erase("magnet")
					enemy_inventory.erase(chosen)
					player_inventory.append(chosen)
					combat_ui.display_round_history("🧲 Magnet swiped 1x [%s] from the Enemy!" % chosen.to_upper(), true)
				else:
					combat_ui.display_round_history("🧲 Magnet cancelled.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return
		_:
			player_inventory.erase(item_type)

	match item_type:
		"potion":
			QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
			if combat_ui: combat_ui.display_round_history("🧪 Deployed a Potion (+20 HP)", true)
		"shield":
			player_active_armor = true
			if combat_ui: combat_ui.display_round_history("🛡️ Deployed a Shield (Block Next Hit)", true)
		"grindstone":
			player_sharpened = true
			if combat_ui: combat_ui.display_round_history("🪨 Deployed a Grindstone (2x DMG Next Phase)", true)
		"whip":
			enemy_is_disarmed = true
			if combat_ui: combat_ui.display_round_history("💥 Whipped Enemy! (Skips their upcoming turn)", true)
		"needle":
			player_piercing = true
			if combat_ui: combat_ui.display_round_history("📌 Loaded a Needle (Pierces Enemy Armor)", true)

	if combat_ui: combat_ui._refresh_ui_states()


func process_player_attack_phase() -> void:
	if player_is_disarmed:
		player_is_disarmed = false
		if combat_ui:
			combat_ui.display_round_history("💥 You were DISARMED! Your attack phase was skipped!", true)
			combat_ui._refresh_ui_states()
			await combat_ui.show_blocking_popup("⚡ DISARMED!", "The Enemy's Whip disarmed you — your attack phase is skipped this round!", false)

		if await _check_combat_end_conditions():
			return

		if combat_ui: combat_ui.start_enemy_turn_visuals()
		await get_tree().create_timer(1.3).timeout
		_execute_enemy_turn_ai()
		return

	var damage_output = 20
	if player_sharpened:
		damage_output *= 2
		player_sharpened = false

	if enemy_active_armor and not player_piercing:
		damage_output = 0
		enemy_active_armor = false
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy Shield completely blocked your hit!", true)
	else:
		if player_piercing:
			player_piercing = false
		enemy_health = clampi(enemy_health - damage_output, 0, enemy_max_health)
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d damage!" % damage_output, true)

	if combat_ui: combat_ui._refresh_ui_states()

	if await _check_combat_end_conditions():
		return

	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.3).timeout
	_execute_enemy_turn_ai()


func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		# Disarmed — shake enemy in place, no lunge
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui:
			combat_ui.display_round_history("💥 Enemy was disarmed and skipped their turn!", false)
			await combat_ui.show_blocking_popup("💀 ENEMY ACTION", "The enemy is DISARMED and cannot act!", false)
		_conclude_round_cycle_ticks()
		return

	var items_played_tracking: Dictionary = {
		"potion": 0, "shield": 0, "grindstone": 0,
		"whip": 0, "needle": 0, "magnet": 0
	}
	var shield_grindstone_evaluated: bool = false

	var processing_combat_actions = true
	while processing_combat_actions:
		var item_to_play = ""

		if enemy_health <= (enemy_max_health - 20) and enemy_inventory.has("potion") and items_played_tracking["potion"] < 1:
			item_to_play = "potion"
		elif not player_is_disarmed and enemy_inventory.has("whip") and items_played_tracking["whip"] < 1:
			item_to_play = "whip"
		elif player_active_armor and enemy_inventory.has("grindstone") and items_played_tracking["grindstone"] < 1 and not shield_grindstone_evaluated:
			shield_grindstone_evaluated = true
			if randf() < 0.50:
				item_to_play = "grindstone"
			else:
				items_played_tracking["grindstone"] = 1
		elif player_active_armor and enemy_inventory.has("needle") and items_played_tracking["needle"] < 1 and not enemy_piercing:
			item_to_play = "needle"
		elif not enemy_active_armor and enemy_inventory.has("shield") and items_played_tracking["shield"] < 1:
			item_to_play = "shield"
		elif not enemy_sharpened and enemy_inventory.has("grindstone") and items_played_tracking["grindstone"] < 1:
			item_to_play = "grindstone"
		elif player_inventory.size() > 0 and enemy_inventory.has("magnet") and items_played_tracking["magnet"] < 1:
			item_to_play = "magnet"

		if item_to_play != "":
			await _enemy_execute_item(item_to_play, items_played_tracking)
			if not is_in_combat: return
		else:
			processing_combat_actions = false

	if not is_in_combat: return

	var raw_dmg = 20
	if enemy_sharpened:
		raw_dmg *= 2
		enemy_sharpened = false

	var attack_log = ""

	if player_active_armor and not enemy_piercing:
		# Shield blocks cleanly — consumed, needle not active
		player_active_armor = false
		attack_log = "🛡️ SAFE! Your armor absorbed their %d damage hit!" % raw_dmg
		if combat_ui: combat_ui.display_round_history("🛡️ Your Shield blocked the enemy's hit.", false)
	elif enemy_piercing:
		# Needle bypasses armor — armor is NOT consumed, needle is spent
		enemy_piercing = false
		var had_armor = player_active_armor
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		if had_armor:
			attack_log = "🪡 PIERCED! Needle bypassed your shield for %d damage! (Shield still active)" % raw_dmg
			if combat_ui: combat_ui.display_round_history("🪡 Enemy Needle bypassed your shield for %d dmg — shield intact!" % raw_dmg, false)
		else:
			attack_log = "🪡 PIERCED! Enemy struck for %d damage!" % raw_dmg
			if combat_ui: combat_ui.display_round_history("🪡 Enemy Needle struck for %d damage!" % raw_dmg, false)
	else:
		# No armor, no needle — straight hit
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		attack_log = "❌ OUCH! Enemy struck for %d damage!" % raw_dmg
		if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d damage to you!" % raw_dmg, false)

	if combat_ui:
		combat_ui._refresh_ui_states()

	# Enemy lunges toward player before showing attack result
	if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
		await player_ref.do_enemy_lunge(self, player_ref.global_position, false)

	if combat_ui:
		await combat_ui.show_blocking_popup("💀 ENEMY ACTION", attack_log, false)

	if await _check_combat_end_conditions():
		return

	_conclude_round_cycle_ticks()


func _enemy_execute_item(item_type: String, tracking: Dictionary) -> void:
	if not enemy_inventory.has(item_type): return

	enemy_inventory.erase(item_type)
	tracking[item_type] = tracking.get(item_type, 0) + 1
	var outcome_text = ""

	match item_type:
		"potion":
			enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
			outcome_text = "🧪 The enemy drank a Potion and restored 20 HP!"
			if combat_ui: combat_ui.display_round_history("🧪 Enemy used a Potion.", false)
		"shield":
			enemy_active_armor = true
			outcome_text = "🛡️ The enemy deployed a Shield! Incoming damage will be blocked."
			if combat_ui: combat_ui.display_round_history("🛡️ Enemy deployed a Shield.", false)
		"grindstone":
			enemy_sharpened = true
			outcome_text = "🪨 The enemy used a Grindstone! Next attack deals 2x DAMAGE!"
			if combat_ui: combat_ui.display_round_history("🪨 Enemy used a Grindstone.", false)
		"whip":
			player_is_disarmed = true
			outcome_text = "💥 The enemy cracked the Whip! YOUR next turn is SKIPPED!"
			if combat_ui: combat_ui.display_round_history("💥 Enemy Whip — YOUR turn skipped!", false)
		"needle":
			enemy_piercing = true
			outcome_text = "🪡 The enemy loaded a Needle! Next strike PIERCES your armor!"
			if combat_ui: combat_ui.display_round_history("🪡 Enemy loaded a Needle.", false)
		"magnet":
			var valid_targets = player_inventory.filter(func(item): return item != "magnet")
			if valid_targets.size() > 0:
				var steal_target = ""
				if valid_targets.has("needle"): steal_target = "needle"
				elif valid_targets.has("grindstone"): steal_target = "grindstone"
				elif valid_targets.has("shield"): steal_target = "shield"
				else: steal_target = valid_targets.pick_random()
				player_inventory.erase(steal_target)
				enemy_inventory.append(steal_target)
				outcome_text = "🧲 MAGNET! The enemy stole your [%s]!" % steal_target.to_upper()
				if combat_ui: combat_ui.display_round_history("🧲 Enemy stole your [%s]!" % steal_target, false)
			else:
				outcome_text = "🧲 MAGNET... Enemy reached in but you have no stealable items!"
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet fizzled — Refunded to inventory.", false)
				enemy_inventory.append("magnet")

	if combat_ui:
		combat_ui._refresh_ui_states()
		await combat_ui.show_blocking_popup("💀 ENEMY ACTION", outcome_text, false)


func _conclude_round_cycle_ticks() -> void:
	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		if combat_ui: await combat_ui.show_blocking_popup("📦 SUPPLY DROP", "Supply drop deployed! New items added to both inventories.", false)

	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()


func _apply_supply_drop_rewards() -> void:
	drop_round_index += 1

	# Items per drop: 1, 2, 3, 4, 5, 6 — capped at 6 forever
	var items_this_drop = min(drop_round_index, 6)
	current_items_per_deal = items_this_drop

	# Drop timing schedule: after rounds 1, 2, 4, 6, 8, 8, 8...
	const DROP_SCHEDULE = [1, 2, 4, 6, 8]
	var next_idx = min(drop_round_index, DROP_SCHEDULE.size() - 1)
	cycles_until_drop = DROP_SCHEDULE[next_idx]

	for i in range(items_this_drop):
		if QuestManager.equipped_items.size() > 0:
			player_inventory.append(QuestManager.equipped_items.pick_random())
		if enemy_item_pool.size() > 0:
			enemy_inventory.append(enemy_item_pool.pick_random())


func _reset_all_combat_modifiers() -> void:
	player_active_armor = false
	player_sharpened = false
	player_piercing = false
	player_is_disarmed = false
	enemy_active_armor = false
	enemy_sharpened = false
	enemy_piercing = false
	enemy_is_disarmed = false


func _check_combat_end_conditions() -> bool:
	if QuestManager.player_health <= 0:
		if is_instance_valid(combat_ui): combat_ui.visible = false
		self.global_position = enemy_overworld_position
		is_in_combat = false
		QuestManager.is_in_combat = false
		if is_instance_valid(lose_ui): lose_ui.show_death_screen()
		return true

	if enemy_health <= 0:
		if is_instance_valid(combat_ui): combat_ui.visible = false

		# XP reward scales with enemy level
		var xp_reward := 25
		match enemy_level:
			1: xp_reward = 25
			2: xp_reward = 40
			3: xp_reward = 60
			4: xp_reward = 90
			_: xp_reward = 90 + ((enemy_level - 4) * 30)
		QuestManager.gain_xp(xp_reward)

		QuestManager.player_health = QuestManager.MAX_HEALTH

		# Play die animation once before removing enemy
		var enemy_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if is_instance_valid(enemy_sprite) and enemy_sprite.sprite_frames and enemy_sprite.sprite_frames.has_animation("die"):
			enemy_sprite.play("die")
			await enemy_sprite.animation_finished

		if is_instance_valid(player_ref):
			if "velocity" in player_ref: player_ref.velocity = Vector2.ZERO
			player_ref.global_position = QuestManager.player_overworld_position

		QuestManager.is_in_combat = false
		queue_free()
		return true
	return false
