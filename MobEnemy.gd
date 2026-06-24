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
var player_cursed: bool = false
var enemy_cursed: bool = false
var player_items_locked: bool = false
var enemy_items_locked: bool = false
var player_stun_extra_turns: int = 0
var enemy_stun_extra_turns: int = 0

var player_ref: Node2D = null
var is_in_combat: bool = false
var enemy_overworld_position: Vector2 = Vector2.ZERO

# ── Visual flash colours ──────────────────────────────────────────────────────
const FLASH_HEAL        := Color(0.30, 1.00, 0.30, 1.0)   # bright green   — heal / regen
const FLASH_POISON      := Color(0.10, 0.55, 0.10, 1.0)   # dark green     — poison applied
const FLASH_DAMAGE      := Color(1.00, 0.18, 0.18, 1.0)   # red            — taking a hit
const FLASH_SHIELD      := Color(0.50, 0.75, 1.00, 1.0)   # blue-white     — shield up
const FLASH_OVERCHARGE  := Color(1.00, 0.55, 0.10, 1.0)   # orange         — overcharge / grindstone
const FLASH_CURSE       := Color(0.65, 0.20, 0.90, 1.0)   # purple         — curse / weaken
const FLASH_DODGE       := Color(0.30, 0.90, 1.00, 1.0)   # cyan           — dodge / smoke
const FLASH_REFLECT     := Color(1.00, 0.90, 0.20, 1.0)   # gold           — mirror ward
const FLASH_DISARM      := Color(1.00, 0.70, 0.10, 1.0)   # amber          — whip / disarm
const FLASH_STEAL       := Color(0.80, 0.40, 1.00, 1.0)   # violet         — magnet / chain hook
const FLASH_HORN        := Color(1.00, 0.85, 0.30, 1.0)   # gold-yellow    — battle horn
const FLASH_STATIC      := Color(0.70, 0.90, 1.00, 1.0)   # electric blue  — static field
const FLASH_TIMEWARP    := Color(0.70, 1.00, 0.95, 1.0)   # teal           — time warp

# ── Emoji floater colours / labels ───────────────────────────────────────────
# Used to show a floating emoji above the sprite for 1s so intent is clear.
func _float_emoji(target: String, emoji: String) -> void:
	var sprite = _get_sprite(target)
	if not is_instance_valid(sprite): return
	var lbl = Label.new()
	lbl.text = emoji
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.position = sprite.global_position + Vector2(-20, -80)
	lbl.z_index = 100
	get_tree().root.add_child(lbl)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(lbl): lbl.queue_free()

func _get_sprite(target: String) -> AnimatedSprite2D:
	if target == "player":
		if is_instance_valid(player_ref):
			return player_ref.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	elif target == "enemy":
		return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _flash(target: String, color: Color, duration: float = 0.5) -> void:
	if is_instance_valid(combat_ui) and combat_ui.has_method("flash_sprite"):
		combat_ui.flash_sprite(target, color, duration)
	else:
		# Fallback: direct modulate if CombatUI not available
		var sprite = _get_sprite(target)
		if is_instance_valid(sprite):
			var orig = sprite.modulate
			sprite.modulate = color
			await get_tree().create_timer(duration).timeout
			if is_instance_valid(sprite): sprite.modulate = orig

# Short pause between actions — replaces blocking popups
const ACTION_PAUSE := 0.55

func _ready() -> void:
	_initialize_mob_stats_by_character_tier()
	_auto_wire_overworld_signals()


func _auto_wire_overworld_signals() -> void:
	var deadzone_node = find_child("deadzone")
	if deadzone_node and deadzone_node.has_signal("body_entered"):
		if deadzone_node.body_entered.is_connected(_on_deadzone_body_entered):
			deadzone_node.body_entered.disconnect(_on_deadzone_body_entered)
		deadzone_node.body_entered.connect(_on_deadzone_body_entered)


const TIER_POOLS_LV6_PLUS := {
	6:  ["potion", "shield", "grindstone", "needle", "magnet", "poison_dart"],
	7:  ["shield", "whip", "poison_dart", "bandage", "needle", "magnet"],
	8:  ["grindstone", "battle_horn", "needle", "magnet", "potion", "shield"],
	9:  ["shield", "smoke_bomb", "poison_dart", "whip", "bandage", "needle"],
	10: ["mirror_ward", "grindstone", "battle_horn", "needle", "potion", "magnet"],
	11: ["weaken_totem", "shield", "poison_dart", "bandage", "smoke_bomb", "needle"],
	12: ["chain_hook", "magnet", "needle", "smoke_bomb", "battle_horn", "potion"],
	13: ["static_field", "mirror_ward", "weaken_totem", "battle_horn", "bandage", "needle"],
	14: ["time_warp", "chain_hook", "poison_dart", "needle", "shield", "potion"],
	15: ["overcharge", "time_warp", "static_field", "mirror_ward", "chain_hook", "bandage"],
}

func _initialize_mob_stats_by_character_tier() -> void:
	enemy_max_health = 80 + (enemy_level * 20)
	if enemy_level <= 5:
		enemy_item_pool = ["potion", "shield"]
		if enemy_level >= 2: enemy_item_pool.append("grindstone")
		if enemy_level >= 3: enemy_item_pool.append("whip")
		if enemy_level >= 4: enemy_item_pool.append("needle")
		if enemy_level >= 5: enemy_item_pool.append("magnet")
	else:
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

	_switch_to_combat_camera()

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
					_flash("player", FLASH_STEAL, 0.5)
					_float_emoji("player", "🧲")
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
				_flash("player", FLASH_STEAL, 0.5)
				_float_emoji("enemy", "⛓️")
				combat_ui.display_round_history("⛓️ Chain Hook yanked [%s] from Enemy and weakened their next attack!" % steal_target.to_upper(), true)
			else:
				_flash("enemy", FLASH_CURSE, 0.4)
				combat_ui.display_round_history("⛓️ Chain Hook found nothing to steal, but still weakened the Enemy's next attack!", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return
		_:
			player_inventory.erase(item_type)

	match item_type:
		"potion":
			QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
			_flash("player", FLASH_HEAL, 0.7)
			_float_emoji("player", "🧪")
			if combat_ui: combat_ui.display_round_history("🧪 Potion (+20 HP)", true)
		"shield":
			player_active_armor = true
			_flash("player", FLASH_SHIELD, 0.6)
			_float_emoji("player", "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Shield raised", true)
		"grindstone":
			player_sharpened = true
			_flash("player", FLASH_OVERCHARGE, 0.6)
			_float_emoji("player", "🪨")
			if combat_ui: combat_ui.display_round_history("🪨 Grindstone — next attack 2×", true)
		"whip":
			enemy_is_disarmed = true
			_flash("enemy", FLASH_DISARM, 0.6)
			_float_emoji("enemy", "💥")
			if combat_ui: combat_ui.display_round_history("💥 Whip — enemy turn skipped", true)
		"needle":
			player_piercing = true
			_flash("player", FLASH_OVERCHARGE, 0.5)
			_float_emoji("player", "📌")
			if combat_ui: combat_ui.display_round_history("📌 Needle — next attack pierces armor", true)
		"bandage":
			QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
			player_regen_rounds = 2
			_flash("player", FLASH_HEAL, 0.7)
			_float_emoji("player", "🩹")
			if combat_ui: combat_ui.display_round_history("🩹 Bandage (+10 HP now, +10 regen × 2)", true)
		"poison_dart":
			enemy_poison_rounds = 4
			_flash("enemy", FLASH_POISON, 0.6)
			_float_emoji("enemy", "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Poison Dart — enemy takes 10/round × 4", true)
		"battle_horn":
			player_horn_charges = 2
			_flash("player", FLASH_HORN, 0.6)
			_float_emoji("player", "📯")
			if combat_ui: combat_ui.display_round_history("📯 Battle Horn — next 2 attacks +50%", true)
		"mirror_ward":
			player_reflect_active = true
			_flash("player", FLASH_REFLECT, 0.6)
			_float_emoji("player", "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Mirror Ward — next hit reflected", true)
		"smoke_bomb":
			player_dodge_active = true
			_flash("player", FLASH_DODGE, 0.6)
			_float_emoji("player", "💨")
			if combat_ui: combat_ui.display_round_history("💨 Smoke Bomb — next enemy attack misses", true)
		"weaken_totem":
			enemy_cursed = true
			_flash("enemy", FLASH_CURSE, 0.7)
			_float_emoji("enemy", "🗿")
			if combat_ui: combat_ui.display_round_history("🗿 Weaken Totem — enemy attack cursed", true)
		"static_field":
			enemy_items_locked = true
			_flash("enemy", FLASH_STATIC, 0.6)
			_float_emoji("enemy", "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Static Field — enemy items locked next turn", true)
		"time_warp":
			enemy_is_disarmed = true
			enemy_stun_extra_turns += 1
			_flash("enemy", FLASH_TIMEWARP, 0.8)
			_float_emoji("enemy", "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Time Warp — enemy skips 2 turns", true)
		"overcharge":
			player_piercing = true
			player_sharpened = true
			_flash("player", FLASH_OVERCHARGE, 0.8)
			_float_emoji("player", "🔥")
			if combat_ui: combat_ui.display_round_history("🔥 Overcharge — pierce + 2× damage next attack", true)

	if combat_ui: combat_ui._refresh_ui_states()


func process_player_attack_phase() -> void:
	if player_items_locked:
		player_items_locked = false

	if player_is_disarmed:
		player_is_disarmed = false
		if player_stun_extra_turns > 0:
			player_stun_extra_turns -= 1
			player_is_disarmed = true
		_flash("player", FLASH_DISARM, 0.5)
		_float_emoji("player", "💥")
		if combat_ui:
			combat_ui.display_round_history("💥 DISARMED — your attack phase skipped!", true)
			combat_ui._refresh_ui_states()
		await get_tree().create_timer(ACTION_PAUSE).timeout
		if await _check_combat_end_conditions(): return
		if combat_ui: combat_ui.start_enemy_turn_visuals()
		await get_tree().create_timer(1.0).timeout
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

	var was_cursed = false
	if player_cursed:
		player_cursed = false
		was_cursed = true
		damage_output = 0
		enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)

	if was_cursed:
		_flash("player", FLASH_CURSE, 0.6)
		_float_emoji("player", "🗿")
		_flash("enemy", FLASH_HEAL, 0.6)
		if combat_ui: combat_ui.display_round_history("🗿 CURSED — your attack dealt 0 dmg, enemy healed 20!", true)
	elif enemy_dodge_active:
		enemy_dodge_active = false
		_flash("enemy", FLASH_DODGE, 0.5)
		_float_emoji("enemy", "💨")
		if combat_ui: combat_ui.display_round_history("💨 Enemy dodged — your attack missed!", true)
	elif enemy_reflect_active:
		enemy_reflect_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - damage_output, 0, QuestManager.MAX_HEALTH)
		_flash("enemy", FLASH_REFLECT, 0.5)
		_flash("player", FLASH_DAMAGE, 0.5)
		_float_emoji("enemy", "🪞")
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d damage bounced back at you!" % damage_output, true)
	elif enemy_active_armor and not player_piercing:
		damage_output = 0
		enemy_active_armor = false
		_flash("enemy", FLASH_SHIELD, 0.5)
		_float_emoji("enemy", "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy shield blocked your hit!", true)
	else:
		if player_piercing:
			player_piercing = false
		enemy_health = clampi(enemy_health - damage_output, 0, enemy_max_health)
		_flash("enemy", FLASH_DAMAGE, 0.45)
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d damage!" % damage_output, true)

	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.0).timeout
	_execute_enemy_turn_ai()


func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		if enemy_stun_extra_turns > 0:
			enemy_stun_extra_turns -= 1
			enemy_is_disarmed = true
		_flash("enemy", FLASH_DISARM, 0.5)
		_float_emoji("enemy", "💥")
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui:
			combat_ui.display_round_history("💥 Enemy was disarmed — turn skipped!", false)
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

	if enemy_items_locked:
		enemy_items_locked = false
		_flash("enemy", FLASH_STATIC, 0.5)
		_float_emoji("enemy", "⚡")
		if combat_ui:
			combat_ui.display_round_history("⚡ Enemy items LOCKED — forced basic attack!", false)
		await get_tree().create_timer(ACTION_PAUSE).timeout
	else:
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
			elif not player_cursed and enemy_inventory.has("weaken_totem") and items_played_tracking["weaken_totem"] < 1 and randf() < 0.6:
				item_to_play = "weaken_totem"
			elif not player_items_locked and enemy_inventory.has("static_field") and items_played_tracking["static_field"] < 1 and randf() < 0.45:
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

	# ── Enemy basic attack ────────────────────────────────────────────────────
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

	var enemy_was_cursed = false
	if enemy_cursed:
		enemy_cursed = false
		enemy_was_cursed = true
		raw_dmg = 0
		QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)

	# Enemy lunges first so it looks like the attack is happening
	if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
		await player_ref.do_enemy_lunge(self, player_ref.global_position, false)

	if enemy_was_cursed:
		_flash("enemy", FLASH_CURSE, 0.6)
		_flash("player", FLASH_HEAL, 0.6)
		_float_emoji("enemy", "🗿")
		if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed — 0 dmg, you healed 20!", false)
	elif player_dodge_active:
		player_dodge_active = false
		_flash("player", FLASH_DODGE, 0.5)
		_float_emoji("player", "💨")
		if combat_ui: combat_ui.display_round_history("💨 DODGED — enemy attack missed!", false)
	elif player_reflect_active:
		player_reflect_active = false
		enemy_health = clampi(enemy_health - raw_dmg, 0, enemy_max_health)
		_flash("player", FLASH_REFLECT, 0.5)
		_flash("enemy", FLASH_DAMAGE, 0.5)
		_float_emoji("player", "🪞")
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d damage bounced back at enemy!" % raw_dmg, false)
	elif player_active_armor and not enemy_piercing:
		player_active_armor = false
		_flash("player", FLASH_SHIELD, 0.5)
		_float_emoji("player", "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Your shield blocked enemy's hit!", false)
	elif enemy_piercing:
		enemy_piercing = false
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		_flash("player", FLASH_DAMAGE, 0.6)
		_float_emoji("player", "🪡")
		if combat_ui: combat_ui.display_round_history("🪡 Needle pierced your shield for %d dmg!" % raw_dmg, false)
	else:
		QuestManager.player_health = clampi(QuestManager.player_health - raw_dmg, 0, QuestManager.MAX_HEALTH)
		_flash("player", FLASH_DAMAGE, 0.5)
		if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d damage to you!" % raw_dmg, false)

	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout

	if await _check_combat_end_conditions(): return
	await _conclude_round_cycle_ticks()


func _enemy_execute_item(item_type: String, tracking: Dictionary) -> void:
	if not enemy_inventory.has(item_type): return

	enemy_inventory.erase(item_type)
	tracking[item_type] = tracking.get(item_type, 0) + 1

	match item_type:
		"potion":
			enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
			_flash("enemy", FLASH_HEAL, 0.6)
			_float_emoji("enemy", "🧪")
			if combat_ui: combat_ui.display_round_history("🧪 Enemy used Potion (+20 HP)", false)
		"shield":
			enemy_active_armor = true
			_flash("enemy", FLASH_SHIELD, 0.6)
			_float_emoji("enemy", "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Enemy raised Shield", false)
		"grindstone":
			enemy_sharpened = true
			_flash("enemy", FLASH_OVERCHARGE, 0.6)
			_float_emoji("enemy", "🪨")
			if combat_ui: combat_ui.display_round_history("🪨 Enemy used Grindstone (2× next attack)", false)
		"whip":
			player_is_disarmed = true
			_flash("player", FLASH_DISARM, 0.6)
			_float_emoji("enemy", "💥")
			if combat_ui: combat_ui.display_round_history("💥 Enemy Whip — YOUR turn skipped!", false)
		"needle":
			enemy_piercing = true
			_flash("enemy", FLASH_OVERCHARGE, 0.5)
			_float_emoji("enemy", "🪡")
			if combat_ui: combat_ui.display_round_history("🪡 Enemy loaded Needle (pierces armor)", false)
		"bandage":
			enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
			enemy_regen_rounds = 2
			_flash("enemy", FLASH_HEAL, 0.6)
			_float_emoji("enemy", "🩹")
			if combat_ui: combat_ui.display_round_history("🩹 Enemy used Bandage (+10 HP + regen)", false)
		"poison_dart":
			player_poison_rounds = 4
			_flash("player", FLASH_POISON, 0.6)
			_float_emoji("enemy", "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Enemy poisoned you! (10/round × 4)", false)
		"battle_horn":
			enemy_horn_charges = 2
			_flash("enemy", FLASH_HORN, 0.6)
			_float_emoji("enemy", "📯")
			if combat_ui: combat_ui.display_round_history("📯 Enemy Battle Horn (+50% next 2 attacks)", false)
		"mirror_ward":
			enemy_reflect_active = true
			_flash("enemy", FLASH_REFLECT, 0.6)
			_float_emoji("enemy", "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Enemy Mirror Ward (reflects next hit)", false)
		"smoke_bomb":
			enemy_dodge_active = true
			_flash("enemy", FLASH_DODGE, 0.6)
			_float_emoji("enemy", "💨")
			if combat_ui: combat_ui.display_round_history("💨 Enemy Smoke Bomb (next attack misses)", false)
		"weaken_totem":
			player_cursed = true
			_flash("player", FLASH_CURSE, 0.6)
			_float_emoji("enemy", "🗿")
			if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed your next attack!", false)
		"static_field":
			player_items_locked = true
			_flash("player", FLASH_STATIC, 0.6)
			_float_emoji("enemy", "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Enemy locked your items next turn!", false)
		"time_warp":
			player_is_disarmed = true
			player_stun_extra_turns += 1
			_flash("player", FLASH_TIMEWARP, 0.8)
			_float_emoji("enemy", "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Enemy Time Warp — YOU skip 2 turns!", false)
		"overcharge":
			enemy_piercing = true
			enemy_sharpened = true
			_flash("enemy", FLASH_OVERCHARGE, 0.8)
			_float_emoji("enemy", "🔥")
			if combat_ui: combat_ui.display_round_history("🔥 Enemy Overcharged — pierce + 2× next attack!", false)
		"chain_hook":
			var valid_targets = player_inventory.filter(func(item): return item != "chain_hook")
			player_weakened = true
			if valid_targets.size() > 0:
				var steal_target = valid_targets.pick_random()
				player_inventory.erase(steal_target)
				enemy_inventory.append(steal_target)
				_flash("player", FLASH_STEAL, 0.5)
				_float_emoji("enemy", "⛓️")
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy Chain Hook stole your [%s]!" % steal_target, false)
			else:
				_flash("player", FLASH_CURSE, 0.4)
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy Chain Hook weakened your next attack.", false)
		"magnet":
			var valid_targets = player_inventory.filter(func(item): return item != "magnet")
			if valid_targets.size() > 0:
				var steal_target = ""
				if valid_targets.has("needle"):      steal_target = "needle"
				elif valid_targets.has("grindstone"): steal_target = "grindstone"
				elif valid_targets.has("shield"):     steal_target = "shield"
				else: steal_target = valid_targets.pick_random()
				player_inventory.erase(steal_target)
				enemy_inventory.append(steal_target)
				_flash("player", FLASH_STEAL, 0.5)
				_float_emoji("enemy", "🧲")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet stole your [%s]!" % steal_target, false)
			else:
				enemy_inventory.append("magnet")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet fizzled — refunded.", false)

	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout


func _conclude_round_cycle_ticks() -> void:
	await _process_dot_hot_ticks()
	if combat_ui: combat_ui._refresh_ui_states()
	if await _check_combat_end_conditions(): return

	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		if combat_ui:
			combat_ui.display_round_history("📦 Supply drop — new items added!", true)

	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()


func _process_dot_hot_ticks() -> void:
	var tick_log := ""
	if player_poison_rounds > 0:
		player_poison_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health - 10, 0, QuestManager.MAX_HEALTH)
		_flash("player", FLASH_POISON, 0.4)
		tick_log += "☠️ Poison ticked — 10 dmg (%d left)\n" % player_poison_rounds
	if enemy_poison_rounds > 0:
		enemy_poison_rounds -= 1
		enemy_health = clampi(enemy_health - 10, 0, enemy_max_health)
		_flash("enemy", FLASH_POISON, 0.4)
		tick_log += "☠️ Enemy poison ticked — 10 dmg (%d left)\n" % enemy_poison_rounds
	if player_regen_rounds > 0:
		player_regen_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
		_flash("player", FLASH_HEAL, 0.4)
		tick_log += "🩹 Regen healed you 10 HP (%d left)\n" % player_regen_rounds
	if enemy_regen_rounds > 0:
		enemy_regen_rounds -= 1
		enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
		_flash("enemy", FLASH_HEAL, 0.4)
		tick_log += "🩹 Enemy regen healed 10 HP (%d left)\n" % enemy_regen_rounds

	if tick_log != "" and combat_ui:
		combat_ui.display_round_history(tick_log.strip_edges(), true)
		await get_tree().create_timer(ACTION_PAUSE).timeout


func _apply_supply_drop_rewards() -> void:
	drop_round_index += 1
	var items_this_drop = min(drop_round_index, 6)
	current_items_per_deal = items_this_drop
	const DROP_SCHEDULE = [1, 2, 4, 6, 8]
	var next_idx = min(drop_round_index, DROP_SCHEDULE.size() - 1)
	cycles_until_drop = DROP_SCHEDULE[next_idx]
	for i in range(items_this_drop):
		if QuestManager.equipped_items.size() > 0:
			player_inventory.append(QuestManager.equipped_items.pick_random())
		if enemy_item_pool.size() > 0:
			enemy_inventory.append(enemy_item_pool.pick_random())


func _reset_all_combat_modifiers() -> void:
	player_active_armor = false; player_sharpened = false; player_piercing = false
	player_is_disarmed = false; enemy_active_armor = false; enemy_sharpened = false
	enemy_piercing = false; enemy_is_disarmed = false
	player_regen_rounds = 0; enemy_regen_rounds = 0
	player_poison_rounds = 0; enemy_poison_rounds = 0
	player_horn_charges = 0; enemy_horn_charges = 0
	player_reflect_active = false; enemy_reflect_active = false
	player_dodge_active = false; enemy_dodge_active = false
	player_weakened = false; enemy_weakened = false
	player_cursed = false; enemy_cursed = false
	player_items_locked = false; enemy_items_locked = false
	player_stun_extra_turns = 0; enemy_stun_extra_turns = 0


func _switch_to_combat_camera() -> void:
	var arena_cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(arena_cam):
		arena_cam.enabled = true
		arena_cam.make_current()


func _switch_to_overworld_camera() -> void:
	var arena_cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(arena_cam):
		arena_cam.enabled = false
	if is_instance_valid(player_ref):
		var player_cam = player_ref.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(player_cam):
			player_cam.enabled = true
			player_cam.make_current()


func _check_combat_end_conditions() -> bool:
	if QuestManager.player_health <= 0:
		if is_instance_valid(combat_ui): combat_ui.visible = false
		self.global_position = enemy_overworld_position
		is_in_combat = false
		QuestManager.is_in_combat = false
		_switch_to_overworld_camera()
		if is_instance_valid(lose_ui): lose_ui.show_death_screen()
		return true

	if enemy_health <= 0:
		is_in_combat = false
		QuestManager.is_in_combat = false
		if is_instance_valid(combat_ui): combat_ui.visible = false

		var xp_reward := 25
		match enemy_level:
			1: xp_reward = 25
			2: xp_reward = 40
			3: xp_reward = 60
			4: xp_reward = 90
			_: xp_reward = 90 + ((enemy_level - 4) * 30)
		QuestManager.gain_xp(xp_reward)
		QuestManager.player_health = QuestManager.MAX_HEALTH

		var enemy_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if is_instance_valid(enemy_sprite) and enemy_sprite.sprite_frames \
				and enemy_sprite.sprite_frames.has_animation("die"):
			enemy_sprite.stop()
			enemy_sprite.play("die")

		await get_tree().create_timer(1.0).timeout

		if is_instance_valid(enemy_sprite):
			enemy_sprite.stop()

		if is_instance_valid(player_ref):
			if "velocity" in player_ref: player_ref.velocity = Vector2.ZERO
			player_ref.global_position = QuestManager.player_overworld_position

		_switch_to_overworld_camera()
		queue_free()
		return true
	return false
