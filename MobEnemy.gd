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

# ── New item effect state (10 new items) ──
var player_regen_rounds: int = 0
var enemy_regen_rounds: int = 0
var player_poison_rounds: int = 0
var enemy_poison_rounds: int = 0
var player_horn_charges: int = 0
var enemy_horn_charges: int = 0
var player_reflect_active: bool = false
var enemy_reflect_active: bool = false
var player_dodge_active: bool = false
var enemy_dodge_active: bool = false
var player_weakened: bool = false
var enemy_weakened: bool = false
var player_counter_active: bool = false
var enemy_counter_active: bool = false
var player_stun_extra_turns: int = 0
var enemy_stun_extra_turns: int = 0

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


# Curated item pools for tiers 6-15. Each pool is a deliberately different
# combo (not just cumulative) — the strategy each tier teaches changes as
# levels go up, escalating toward more complex, punishing combos by tier 15.
const TIER_POOLS_LV6_PLUS := {
	6:  ["potion", "shield", "grindstone", "bandage"],
	7:  ["shield", "whip", "needle", "poison_dart"],
	8:  ["grindstone", "battle_horn", "needle", "magnet"],
	9:  ["shield", "smoke_bomb", "poison_dart", "whip"],
	10: ["mirror_ward", "grindstone", "battle_horn", "needle"],
	11: ["weaken_totem", "shield", "poison_dart", "bandage"],
	12: ["chain_hook", "magnet", "needle", "smoke_bomb"],
	13: ["static_field", "mirror_ward", "weaken_totem", "battle_horn"],
	14: ["time_warp", "chain_hook", "poison_dart", "needle"],
	15: ["overcharge", "time_warp", "static_field", "mirror_ward", "chain_hook"],
}

func _initialize_mob_stats_by_character_tier() -> void:
	# HP scales every level, no cap
	enemy_max_health = 80 + (enemy_level * 20)

	if enemy_level <= 5:
		# Original 5 tiers — unchanged, cumulative unlock as before
		enemy_item_pool = ["potion", "shield"]
		if enemy_level >= 2: enemy_item_pool.append("grindstone")
		if enemy_level >= 3: enemy_item_pool.append("whip")
		if enemy_level >= 4: enemy_item_pool.append("needle")
		if enemy_level >= 5: enemy_item_pool.append("magnet")
	else:
		# Tiers 6+ use curated, distinct combo pools rather than simple
		# cumulative stacking — each tier teaches a different strategy.
		enemy_item_pool = TIER_POOLS_LV6_PLUS.get(enemy_level, ["potion", "shield", "grindstone", "needle"]).duplicate()

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
		"chain_hook":
			player_inventory.erase("chain_hook")
			var valid_targets = enemy_inventory.filter(func(item): return item != "chain_hook")
			enemy_weakened = true
			if valid_targets.size() > 0:
				var steal_target = valid_targets.pick_random()
				enemy_inventory.erase(steal_target)
				player_inventory.append(steal_target)
				if combat_ui: combat_ui.display_round_history("⛓️ Chain Hook yanked [%s] from the Enemy and weakened their next attack!" % steal_target.to_upper(), true)
			else:
				if combat_ui: combat_ui.display_round_history("⛓️ Chain Hook found nothing to steal, but still weakened the Enemy's next attack!", true)
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
		"bandage":
			QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
			player_regen_rounds = 2
			if combat_ui: combat_ui.display_round_history("🩹 Applied a Bandage (+10 HP now, +10 HP for 2 more rounds)", true)
		"poison_dart":
			enemy_poison_rounds = 3
			if combat_ui: combat_ui.display_round_history("☠️ Threw a Poison Dart at the Enemy (8 dmg/round for 3 rounds)", true)
		"battle_horn":
			player_horn_charges = 2
			if combat_ui: combat_ui.display_round_history("📯 Sounded the Battle Horn (Next 2 attacks +50% damage)", true)
		"mirror_ward":
			player_reflect_active = true
			if combat_ui: combat_ui.display_round_history("🪞 Raised a Mirror Ward (Next hit taken is reflected)", true)
		"smoke_bomb":
			player_dodge_active = true
			if combat_ui: combat_ui.display_round_history("💨 Threw a Smoke Bomb (Next attack against you will miss)", true)
		"weaken_totem":
			enemy_weakened = true
			if combat_ui: combat_ui.display_round_history("🗿 Planted a Weaken Totem (Enemy's next attack -50% damage)", true)
		"static_field":
			player_counter_active = true
			if combat_ui: combat_ui.display_round_history("⚡ Charged a Static Field (Next attacker takes 15 counter damage)", true)
		"time_warp":
			enemy_is_disarmed = true
			enemy_stun_extra_turns += 1
			if combat_ui: combat_ui.display_round_history("⏳ Cast Time Warp! Enemy skips their next TWO turns!", true)
		"overcharge":
			player_piercing = true
			player_sharpened = true
			if combat_ui: combat_ui.display_round_history("🔥 Overcharged! Next attack ignores armor AND deals 2× damage!", true)

	if combat_ui: combat_ui._refresh_ui_states()


func process_player_attack_phase() -> void:
	if player_is_disarmed:
		player_is_disarmed = false
		if player_stun_extra_turns > 0:
			player_stun_extra_turns -= 1
			player_is_disarmed = true
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
	if player_horn_charges > 0:
		damage_output = int(damage_output * 1.5)
		player_horn_charges -= 1
	if player_weakened:
		damage_output = int(damage_output * 0.5)
		player_weakened = false

	if enemy_dodge_active:
		enemy_dodge_active = false
		if combat_ui: combat_ui.display_round_history("💨 The enemy vanished in smoke — your attack missed completely!", true)
	elif enemy_reflect_active:
		enemy_reflect_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - damage_output, 0, QuestManager.MAX_HEALTH)
		if combat_ui: combat_ui.display_round_history("🪞 The enemy's Mirror Ward bounced your %d damage right back at you!" % damage_output, true)
	elif enemy_active_armor and not player_piercing:
		damage_output = 0
		enemy_active_armor = false
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy Shield completely blocked your hit!", true)
	else:
		if player_piercing:
			player_piercing = false
		enemy_health = clampi(enemy_health - damage_output, 0, enemy_max_health)
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d damage!" % damage_output, true)
		if enemy_counter_active and damage_output > 0:
			enemy_counter_active = false
			QuestManager.player_health = clampi(QuestManager.player_health - 15, 0, QuestManager.MAX_HEALTH)
			if combat_ui: combat_ui.display_round_history("⚡ The enemy's Static Field shocked you for 15 counter damage!", true)

	if combat_ui: combat_ui._refresh_ui_states()

	if await _check_combat_end_conditions():
		return

	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.3).timeout
	_execute_enemy_turn_ai()


func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		if enemy_stun_extra_turns > 0:
			enemy_stun_extra_turns -= 1
			enemy_is_disarmed = true
		# Disarmed — shake enemy in place, no lunge
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui:
			combat_ui.display_round_history("💥 Enemy was disarmed and skipped their turn!", false)
			await combat_ui.show_blocking_popup("💀 ENEMY ACTION", "The enemy is DISARMED and cannot act!", false)
		await _conclude_round_cycle_ticks()
		return

	var items_played_tracking: Dictionary = {
		"potion": 0, "shield": 0, "grindstone": 0,
		"whip": 0, "needle": 0, "magnet": 0,
		"bandage": 0, "poison_dart": 0, "battle_horn": 0,
		"mirror_ward": 0, "smoke_bomb": 0, "weaken_totem": 0,
		"chain_hook": 0, "static_field": 0, "time_warp": 0, "overcharge": 0,
	}
	var shield_grindstone_evaluated: bool = false

	var processing_combat_actions = true
	while processing_combat_actions:
		var item_to_play = ""

		if enemy_health <= (enemy_max_health - 20) and enemy_inventory.has("potion") and items_played_tracking["potion"] < 1:
			item_to_play = "potion"
		elif enemy_health <= (enemy_max_health - 20) and enemy_inventory.has("bandage") and items_played_tracking["bandage"] < 1:
			item_to_play = "bandage"
		elif not player_is_disarmed and enemy_health <= enemy_max_health * 0.4 and enemy_inventory.has("time_warp") and items_played_tracking["time_warp"] < 1:
			item_to_play = "time_warp"
		elif not player_is_disarmed and enemy_inventory.has("whip") and items_played_tracking["whip"] < 1:
			item_to_play = "whip"
		elif not enemy_dodge_active and enemy_inventory.has("smoke_bomb") and items_played_tracking["smoke_bomb"] < 1 and randf() < 0.35:
			item_to_play = "smoke_bomb"
		elif not enemy_reflect_active and not enemy_dodge_active and enemy_inventory.has("mirror_ward") and items_played_tracking["mirror_ward"] < 1 and randf() < 0.35:
			item_to_play = "mirror_ward"
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
		elif enemy_horn_charges <= 0 and enemy_inventory.has("battle_horn") and items_played_tracking["battle_horn"] < 1:
			item_to_play = "battle_horn"
		elif player_poison_rounds <= 0 and enemy_inventory.has("poison_dart") and items_played_tracking["poison_dart"] < 1:
			item_to_play = "poison_dart"
		elif not player_weakened and enemy_inventory.has("weaken_totem") and items_played_tracking["weaken_totem"] < 1 and randf() < 0.6:
			item_to_play = "weaken_totem"
		elif not enemy_counter_active and enemy_inventory.has("static_field") and items_played_tracking["static_field"] < 1 and randf() < 0.45:
			item_to_play = "static_field"
		elif player_inventory.size() >= 2 and enemy_inventory.has("chain_hook") and items_played_tracking["chain_hook"] < 1:
			item_to_play = "chain_hook"
		elif player_inventory.size() > 0 and enemy_inventory.has("magnet") and items_played_tracking["magnet"] < 1:
			item_to_play = "magnet"
		elif enemy_health <= enemy_max_health * 0.3 and enemy_inventory.has("overcharge") and items_played_tracking["overcharge"] < 1:
			item_to_play = "overcharge"

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
	if enemy_horn_charges > 0:
		raw_dmg = int(raw_dmg * 1.5)
		enemy_horn_charges -= 1
	if enemy_weakened:
		raw_dmg = int(raw_dmg * 0.5)
		enemy_weakened = false

	var attack_log = ""

	if player_dodge_active:
		player_dodge_active = false
		attack_log = "💨 DODGED! You vanished in smoke and the enemy's attack missed completely!"
		if combat_ui: combat_ui.display_round_history("💨 Your Smoke Bomb caused the enemy's attack to miss entirely!", false)
	elif player_reflect_active:
		player_reflect_active = false
		enemy_health = clampi(enemy_health - raw_dmg, 0, enemy_max_health)
		attack_log = "🪞 REFLECTED! Your Mirror Ward bounced %d damage back at the enemy!" % raw_dmg
		if combat_ui: combat_ui.display_round_history("🪞 Your Mirror Ward reflected %d damage back at the enemy!" % raw_dmg, false)
	elif player_active_armor and not enemy_piercing:
		# Shield blocks cleanly — consumed, needle not active
		player_active_armor = false
		attack_log = "🛡️ SAFE! Your armor absorbed their %d damage hit!" % raw_dmg
		if combat_ui: combat_ui.display_round_history("🛡️ Your Shield blocked the enemy's hit.", false)
	elif enemy_piercing:
		# Needle bypasses armor — armor is NOT consumed, needle is spent
		enemy_piercing = false
		var had_armor = player_active_armor
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		if player_counter_active:
			player_counter_active = false
			enemy_health = clampi(enemy_health - 15, 0, enemy_max_health)
		if had_armor:
			attack_log = "🪡 PIERCED! Needle bypassed your shield for %d damage! (Shield still active)" % raw_dmg
			if combat_ui: combat_ui.display_round_history("🪡 Enemy Needle bypassed your shield for %d dmg — shield intact!" % raw_dmg, false)
		else:
			attack_log = "🪡 PIERCED! Enemy struck for %d damage!" % raw_dmg
			if combat_ui: combat_ui.display_round_history("🪡 Enemy Needle struck for %d damage!" % raw_dmg, false)
	else:
		# No armor, no needle — straight hit
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		if player_counter_active:
			player_counter_active = false
			enemy_health = clampi(enemy_health - 15, 0, enemy_max_health)
			attack_log = "❌ OUCH! Enemy struck for %d damage! ⚡ Your Static Field zapped them back for 15!" % raw_dmg
			if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d damage — your Static Field shocked them for 15 in return!" % raw_dmg, false)
		else:
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

	await _conclude_round_cycle_ticks()


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
		"bandage":
			enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
			enemy_regen_rounds = 2
			outcome_text = "🩹 The enemy applied a Bandage! +10 HP now, +10 HP for 2 more rounds!"
			if combat_ui: combat_ui.display_round_history("🩹 Enemy used a Bandage.", false)
		"poison_dart":
			player_poison_rounds = 3
			outcome_text = "☠️ The enemy threw a Poison Dart at YOU! 8 damage per round for 3 rounds!"
			if combat_ui: combat_ui.display_round_history("☠️ Enemy poisoned you!", false)
		"battle_horn":
			enemy_horn_charges = 2
			outcome_text = "📯 The enemy sounded their Battle Horn! Their next 2 attacks deal +50% damage!"
			if combat_ui: combat_ui.display_round_history("📯 Enemy used a Battle Horn.", false)
		"mirror_ward":
			enemy_reflect_active = true
			outcome_text = "🪞 The enemy raised a Mirror Ward! Your next hit on them will be reflected!"
			if combat_ui: combat_ui.display_round_history("🪞 Enemy raised a Mirror Ward.", false)
		"smoke_bomb":
			enemy_dodge_active = true
			outcome_text = "💨 The enemy threw a Smoke Bomb! Your next attack against them will miss!"
			if combat_ui: combat_ui.display_round_history("💨 Enemy used a Smoke Bomb.", false)
		"weaken_totem":
			player_weakened = true
			outcome_text = "🗿 The enemy planted a Weaken Totem! YOUR next attack deals 50% less damage!"
			if combat_ui: combat_ui.display_round_history("🗿 Enemy weakened your next attack.", false)
		"static_field":
			enemy_counter_active = true
			outcome_text = "⚡ The enemy charged a Static Field! If you land a hit, YOU take 15 counter damage!"
			if combat_ui: combat_ui.display_round_history("⚡ Enemy charged a Static Field.", false)
		"time_warp":
			player_is_disarmed = true
			player_stun_extra_turns += 1
			outcome_text = "⏳ The enemy cast Time Warp! YOU skip your next TWO turns!"
			if combat_ui: combat_ui.display_round_history("⏳ Enemy cast Time Warp on you!", false)
		"overcharge":
			enemy_piercing = true
			enemy_sharpened = true
			outcome_text = "🔥 The enemy Overcharged! Their next attack ignores your armor AND deals 2× damage!"
			if combat_ui: combat_ui.display_round_history("🔥 Enemy Overcharged their next attack!", false)
		"chain_hook":
			var valid_targets = player_inventory.filter(func(item): return item != "chain_hook")
			player_weakened = true
			if valid_targets.size() > 0:
				var steal_target = valid_targets.pick_random()
				player_inventory.erase(steal_target)
				enemy_inventory.append(steal_target)
				outcome_text = "⛓️ CHAIN HOOK! The enemy yanked your [%s] AND weakened your next attack!" % steal_target.to_upper()
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy stole your [%s] with a Chain Hook!" % steal_target, false)
			else:
				outcome_text = "⛓️ CHAIN HOOK! Nothing to steal, but your next attack is still weakened!"
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy Chain Hook weakened your next attack.", false)
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
	await _process_dot_hot_ticks()
	if combat_ui: combat_ui._refresh_ui_states()
	if await _check_combat_end_conditions():
		return

	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		if combat_ui: await combat_ui.show_blocking_popup("📦 SUPPLY DROP", "Supply drop deployed! New items added to both inventories.", false)

	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()


func _process_dot_hot_ticks() -> void:
	var tick_log := ""
	if player_poison_rounds > 0:
		player_poison_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health - 8, 0, QuestManager.MAX_HEALTH)
		tick_log += "☠️ Poison ticked — you took 8 damage! (%d round%s left)\n" % [player_poison_rounds, "" if player_poison_rounds == 1 else "s"]
	if enemy_poison_rounds > 0:
		enemy_poison_rounds -= 1
		enemy_health = clampi(enemy_health - 8, 0, enemy_max_health)
		tick_log += "☠️ Your Poison Dart ticked on the enemy — 8 damage! (%d round%s left)\n" % [enemy_poison_rounds, "" if enemy_poison_rounds == 1 else "s"]
	if player_regen_rounds > 0:
		player_regen_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
		tick_log += "✨ Bandage regen healed you for 10 HP! (%d round%s left)\n" % [player_regen_rounds, "" if player_regen_rounds == 1 else "s"]
	if enemy_regen_rounds > 0:
		enemy_regen_rounds -= 1
		enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
		tick_log += "✨ The enemy's Bandage regen healed them for 10 HP! (%d round%s left)\n" % [enemy_regen_rounds, "" if enemy_regen_rounds == 1 else "s"]

	if tick_log != "" and combat_ui:
		combat_ui.display_round_history(tick_log.strip_edges(), true)
		await combat_ui.show_blocking_popup("🔄 ROUND EFFECTS", tick_log.strip_edges(), false)


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
	player_regen_rounds = 0
	enemy_regen_rounds = 0
	player_poison_rounds = 0
	enemy_poison_rounds = 0
	player_horn_charges = 0
	enemy_horn_charges = 0
	player_reflect_active = false
	enemy_reflect_active = false
	player_dodge_active = false
	enemy_dodge_active = false
	player_weakened = false
	enemy_weakened = false
	player_counter_active = false
	enemy_counter_active = false
	player_stun_extra_turns = 0
	enemy_stun_extra_turns = 0


func _check_combat_end_conditions() -> bool:
	if QuestManager.player_health <= 0:
		if is_instance_valid(combat_ui): combat_ui.visible = false
		self.global_position = enemy_overworld_position
		is_in_combat = false
		QuestManager.is_in_combat = false
		if is_instance_valid(lose_ui): lose_ui.show_death_screen()
		return true

	if enemy_health <= 0:
		# Immediately block any further combat input
		is_in_combat = false
		QuestManager.is_in_combat = false
		if is_instance_valid(combat_ui): combat_ui.visible = false

		# XP reward
		var xp_reward := 25
		match enemy_level:
			1: xp_reward = 25
			2: xp_reward = 40
			3: xp_reward = 60
			4: xp_reward = 90
			_: xp_reward = 90 + ((enemy_level - 4) * 30)
		QuestManager.gain_xp(xp_reward)
		QuestManager.player_health = QuestManager.MAX_HEALTH

		# Play die animation — force stop after one fixed pause so loop doesn't trap us
		var enemy_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if is_instance_valid(enemy_sprite) and enemy_sprite.sprite_frames \
				and enemy_sprite.sprite_frames.has_animation("die"):
			enemy_sprite.stop()
			enemy_sprite.play("die")

		# Fixed pause — adjust to match your die animation length
		await get_tree().create_timer(1.0).timeout

		# Stop the animation so it doesn't keep playing after we return
		if is_instance_valid(enemy_sprite):
			enemy_sprite.stop()

		# Restore player position
		if is_instance_valid(player_ref):
			if "velocity" in player_ref: player_ref.velocity = Vector2.ZERO
			player_ref.global_position = QuestManager.player_overworld_position

		queue_free()
		return true
	return false
