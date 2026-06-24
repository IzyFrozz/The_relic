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

# ── Flash colours ─────────────────────────────────────────────────────────────
const FLASH_HEAL       := Color(0.30, 1.00, 0.30, 1.0)
const FLASH_POISON     := Color(0.10, 0.55, 0.10, 1.0)
const FLASH_DAMAGE     := Color(1.00, 0.18, 0.18, 1.0)
const FLASH_SHIELD     := Color(0.50, 0.75, 1.00, 1.0)
const FLASH_OVERCHARGE := Color(1.00, 0.55, 0.10, 1.0)
const FLASH_CURSE      := Color(0.65, 0.20, 0.90, 1.0)
const FLASH_DODGE      := Color(0.30, 0.90, 1.00, 1.0)
const FLASH_REFLECT    := Color(1.00, 0.90, 0.20, 1.0)
const FLASH_DISARM     := Color(1.00, 0.70, 0.10, 1.0)
const FLASH_STEAL      := Color(0.80, 0.40, 1.00, 1.0)
const FLASH_HORN       := Color(1.00, 0.85, 0.30, 1.0)
const FLASH_STATIC     := Color(0.70, 0.90, 1.00, 1.0)
const FLASH_TIMEWARP   := Color(0.70, 1.00, 0.95, 1.0)

# Pause between actions so FX is visible
const ACTION_PAUSE := 0.25

# ── Ground circle FX (persistent status) ─────────────────────────────────────
var _player_ground_fx: ColorRect = null
var _enemy_ground_fx: ColorRect = null

func _get_sprite(target: String) -> AnimatedSprite2D:
	if target == "player":
		if is_instance_valid(player_ref):
			return player_ref.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	else:
		return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _set_ground_fx(target: String, color: Color) -> void:
	var sprite = _get_sprite(target)
	if not is_instance_valid(sprite): return
	var fx: ColorRect
	if target == "player":
		if not is_instance_valid(_player_ground_fx):
			_player_ground_fx = ColorRect.new()
			_player_ground_fx.z_index = -1
			sprite.get_parent().add_child(_player_ground_fx)
		fx = _player_ground_fx
	else:
		if not is_instance_valid(_enemy_ground_fx):
			_enemy_ground_fx = ColorRect.new()
			_enemy_ground_fx.z_index = -1
			sprite.get_parent().add_child(_enemy_ground_fx)
		fx = _enemy_ground_fx
	if color.a < 0.01:
		fx.visible = false
		return
	fx.color = color
	fx.size = Vector2(36, 10)
	fx.position = sprite.position + Vector2(-18, 8)
	fx.visible = true

func _sync_ground_fx() -> void:
	# Player ground
	if player_poison_rounds > 0:        _set_ground_fx("player", Color(0.05, 0.35, 0.05, 0.75))
	elif player_cursed:                  _set_ground_fx("player", Color(0.25, 0.05, 0.40, 0.70))
	elif player_regen_rounds > 0:        _set_ground_fx("player", Color(0.10, 0.55, 0.10, 0.65))
	elif player_active_armor:            _set_ground_fx("player", Color(0.20, 0.45, 0.90, 0.60))
	elif player_dodge_active:            _set_ground_fx("player", Color(0.20, 0.80, 0.90, 0.55))
	elif player_reflect_active:          _set_ground_fx("player", Color(0.90, 0.80, 0.10, 0.60))
	else:                                _set_ground_fx("player", Color.TRANSPARENT)
	# Enemy ground
	if enemy_poison_rounds > 0:         _set_ground_fx("enemy", Color(0.05, 0.35, 0.05, 0.75))
	elif enemy_cursed:                   _set_ground_fx("enemy", Color(0.25, 0.05, 0.40, 0.70))
	elif enemy_regen_rounds > 0:         _set_ground_fx("enemy", Color(0.10, 0.55, 0.10, 0.65))
	elif enemy_active_armor:             _set_ground_fx("enemy", Color(0.20, 0.45, 0.90, 0.60))
	elif enemy_dodge_active:             _set_ground_fx("enemy", Color(0.20, 0.80, 0.90, 0.55))
	elif enemy_reflect_active:           _set_ground_fx("enemy", Color(0.90, 0.80, 0.10, 0.60))
	else:                                _set_ground_fx("enemy", Color.TRANSPARENT)

# Awaitable flicker flash — MUST be awaited so next action waits for FX to finish
func _flash(target: String, color: Color, duration: float = 0.5) -> void:
	var sprite = _get_sprite(target)
	if not is_instance_valid(sprite): return
	var original = sprite.modulate
	var elapsed := 0.0
	var on := true
	while elapsed < duration:
		sprite.modulate = color if on else original
		on = not on
		await get_tree().create_timer(0.10).timeout
		elapsed += 0.10
	if is_instance_valid(sprite):
		sprite.modulate = original

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

# ── Player item use ───────────────────────────────────────────────────────────
func use_player_item(item_type: String) -> void:
	if not item_type in player_inventory: return

	match item_type:
		"magnet":
			if enemy_inventory.size() == 0:
				if combat_ui: combat_ui.display_round_history("🧲 Magnet fizzled — enemy hand empty!", true)
				if combat_ui: combat_ui._refresh_ui_states()
				return
			if combat_ui:
				var chosen = await combat_ui.show_magnet_choice_popup(enemy_inventory)
				if chosen != "":
					player_inventory.erase("magnet")
					enemy_inventory.erase(chosen)
					player_inventory.append(chosen)
					await _flash("player", FLASH_STEAL, 0.5)
					combat_ui.display_round_history("🧲 Magnet swiped [%s] from enemy!" % chosen.to_upper(), true)
				else:
					combat_ui.display_round_history("🧲 Magnet cancelled.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return
		"chain_hook":
			player_inventory.erase("chain_hook")
			var valid_targets = enemy_inventory.filter(func(i): return i != "chain_hook")
			enemy_weakened = true
			if valid_targets.size() > 0:
				var st = valid_targets.pick_random()
				enemy_inventory.erase(st)
				player_inventory.append(st)
				await _flash("player", FLASH_STEAL, 0.5)
				if combat_ui: combat_ui.display_round_history("⛓️ Chain Hook yanked [%s] + weakened enemy!" % st.to_upper(), true)
			else:
				await _flash("enemy", FLASH_CURSE, 0.4)
				if combat_ui: combat_ui.display_round_history("⛓️ Nothing to steal — enemy weakened anyway.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return
		_:
			player_inventory.erase(item_type)

	match item_type:
		"potion":
			QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
			await _flash("player", FLASH_HEAL, 0.7)
			if combat_ui: combat_ui.display_round_history("🧪 Potion (+20 HP)", true)
		"shield":
			player_active_armor = true
			await _flash("player", FLASH_SHIELD, 0.6)
			if combat_ui: combat_ui.display_round_history("🛡️ Shield raised", true)
		"grindstone":
			player_sharpened = true
			await _flash("player", FLASH_OVERCHARGE, 0.6)
			if combat_ui: combat_ui.display_round_history("🪨 Grindstone — next attack 2×", true)
		"whip":
			enemy_is_disarmed = true
			await _flash("enemy", FLASH_DISARM, 0.6)
			if combat_ui: combat_ui.display_round_history("💥 Whip — enemy turn skipped", true)
		"needle":
			player_piercing = true
			await _flash("player", FLASH_OVERCHARGE, 0.5)
			if combat_ui: combat_ui.display_round_history("📌 Needle — next attack pierces armor", true)
		"bandage":
			QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
			player_regen_rounds = 2
			await _flash("player", FLASH_HEAL, 0.7)
			if combat_ui: combat_ui.display_round_history("🩹 Bandage (+10 HP + regen ×2)", true)
		"poison_dart":
			enemy_poison_rounds = 4
			await _flash("enemy", FLASH_POISON, 0.6)
			if combat_ui: combat_ui.display_round_history("☠️ Poison Dart — enemy 10/round ×4", true)
		"battle_horn":
			player_horn_charges = 2
			await _flash("player", FLASH_HORN, 0.6)
			if combat_ui: combat_ui.display_round_history("📯 Battle Horn — next 2 attacks +50%", true)
		"mirror_ward":
			player_reflect_active = true
			await _flash("player", FLASH_REFLECT, 0.6)
			if combat_ui: combat_ui.display_round_history("🪞 Mirror Ward — next hit reflected", true)
		"smoke_bomb":
			player_dodge_active = true
			await _flash("player", FLASH_DODGE, 0.6)
			if combat_ui: combat_ui.display_round_history("💨 Smoke Bomb — next enemy attack misses", true)
		"weaken_totem":
			enemy_cursed = true
			await _flash("enemy", FLASH_CURSE, 0.7)
			if combat_ui: combat_ui.display_round_history("🗿 Weaken Totem — enemy attack cursed", true)
		"static_field":
			enemy_items_locked = true
			await _flash("enemy", FLASH_STATIC, 0.6)
			if combat_ui: combat_ui.display_round_history("⚡ Static Field — enemy items locked", true)
		"time_warp":
			enemy_is_disarmed = true
			enemy_stun_extra_turns += 1
			await _flash("enemy", FLASH_TIMEWARP, 0.8)
			if combat_ui: combat_ui.display_round_history("⏳ Time Warp — enemy skips 2 turns", true)
		"overcharge":
			player_piercing = true
			player_sharpened = true
			await _flash("player", FLASH_OVERCHARGE, 0.8)
			if combat_ui: combat_ui.display_round_history("🔥 Overcharge — pierce + 2× next attack", true)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()

# ── Player attack phase ───────────────────────────────────────────────────────
func process_player_attack_phase() -> void:
	if player_items_locked:
		player_items_locked = false

	if player_is_disarmed:
		player_is_disarmed = false
		if player_stun_extra_turns > 0:
			player_stun_extra_turns -= 1
			player_is_disarmed = true
		await _flash("player", FLASH_DISARM, 0.5)
		if combat_ui:
			combat_ui.display_round_history("💥 DISARMED — attack skipped!", true)
			combat_ui._refresh_ui_states()
		await get_tree().create_timer(ACTION_PAUSE).timeout
		if await _check_combat_end_conditions(): return
		if combat_ui: combat_ui.start_enemy_turn_visuals()
		await get_tree().create_timer(1.0).timeout
		_execute_enemy_turn_ai()
		return

	var dmg = 20
	if player_sharpened:   dmg *= 2;             player_sharpened = false
	if player_horn_charges > 0: dmg = int(dmg * 1.5); player_horn_charges -= 1
	if player_weakened:    dmg = int(dmg * 0.5); player_weakened = false

	if player_cursed:
		player_cursed = false
		enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
		await _flash("player", FLASH_CURSE, 0.6)
		await _flash("enemy",  FLASH_HEAL,  0.5)
		if combat_ui: combat_ui.display_round_history("🗿 CURSED — 0 dmg, enemy healed 20!", true)
	elif enemy_dodge_active:
		enemy_dodge_active = false
		await _flash("enemy", FLASH_DODGE, 0.5)
		if combat_ui: combat_ui.display_round_history("💨 Enemy dodged — missed!", true)
	elif enemy_reflect_active:
		enemy_reflect_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - dmg, 0, QuestManager.MAX_HEALTH)
		await _flash("enemy",  FLASH_REFLECT, 0.5)
		await _flash("player", FLASH_DAMAGE,  0.5)
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d dmg bounced back!" % dmg, true)
	elif enemy_active_armor and not player_piercing:
		enemy_active_armor = false
		await _flash("enemy", FLASH_SHIELD, 0.5)
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy shield blocked your hit!", true)
	else:
		if player_piercing: player_piercing = false
		enemy_health = clampi(enemy_health - dmg, 0, enemy_max_health)
		await _flash("enemy", FLASH_DAMAGE, 0.45)
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d dmg!" % dmg, true)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.0).timeout
	_execute_enemy_turn_ai()

# ── Enemy AI turn ─────────────────────────────────────────────────────────────
func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		if enemy_stun_extra_turns > 0:
			enemy_stun_extra_turns -= 1
			enemy_is_disarmed = true
		await _flash("enemy", FLASH_DISARM, 0.5)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui: combat_ui.display_round_history("💥 Enemy disarmed — turn skipped!", false)
		await _conclude_round_cycle_ticks()
		return

	var tracking: Dictionary = {}
	for k in ["potion","shield","grindstone","whip","needle","magnet","bandage",
			"poison_dart","battle_horn","mirror_ward","smoke_bomb","weaken_totem",
			"chain_hook","static_field","time_warp","overcharge"]:
		tracking[k] = 0
	var sg_eval := false

	if enemy_items_locked:
		enemy_items_locked = false
		await _flash("enemy", FLASH_STATIC, 0.5)
		if combat_ui: combat_ui.display_round_history("⚡ Enemy items LOCKED — basic attack only!", false)
		await get_tree().create_timer(ACTION_PAUSE).timeout
	else:
		var going := true
		while going:
			var pick := ""
			if enemy_health <= enemy_max_health - 20 and enemy_inventory.has("potion") and tracking["potion"] < 1:
				pick = "potion"
			elif enemy_health <= enemy_max_health - 20 and enemy_inventory.has("bandage") and tracking["bandage"] < 1:
				pick = "bandage"
			elif not player_is_disarmed and enemy_health <= enemy_max_health * 0.4 and enemy_inventory.has("time_warp") and tracking["time_warp"] < 1:
				pick = "time_warp"
			elif not player_is_disarmed and enemy_inventory.has("whip") and tracking["whip"] < 1:
				pick = "whip"
			elif not enemy_dodge_active and enemy_inventory.has("smoke_bomb") and tracking["smoke_bomb"] < 1 and randf() < 0.35:
				pick = "smoke_bomb"
			elif not enemy_reflect_active and not enemy_dodge_active and enemy_inventory.has("mirror_ward") and tracking["mirror_ward"] < 1 and randf() < 0.35:
				pick = "mirror_ward"
			elif player_active_armor and enemy_inventory.has("grindstone") and tracking["grindstone"] < 1 and not sg_eval:
				sg_eval = true
				if randf() < 0.5: pick = "grindstone"
				else: tracking["grindstone"] = 1
			elif player_active_armor and enemy_inventory.has("needle") and tracking["needle"] < 1 and not enemy_piercing:
				pick = "needle"
			elif not enemy_active_armor and enemy_inventory.has("shield") and tracking["shield"] < 1:
				pick = "shield"
			elif not enemy_sharpened and enemy_inventory.has("grindstone") and tracking["grindstone"] < 1:
				pick = "grindstone"
			elif enemy_horn_charges <= 0 and enemy_inventory.has("battle_horn") and tracking["battle_horn"] < 1:
				pick = "battle_horn"
			elif player_poison_rounds <= 0 and enemy_inventory.has("poison_dart") and tracking["poison_dart"] < 1:
				pick = "poison_dart"
			elif not player_cursed and enemy_inventory.has("weaken_totem") and tracking["weaken_totem"] < 1 and randf() < 0.6:
				pick = "weaken_totem"
			elif not player_items_locked and enemy_inventory.has("static_field") and tracking["static_field"] < 1 and randf() < 0.45:
				pick = "static_field"
			elif player_inventory.size() >= 2 and enemy_inventory.has("chain_hook") and tracking["chain_hook"] < 1:
				pick = "chain_hook"
			elif player_inventory.size() > 0 and enemy_inventory.has("magnet") and tracking["magnet"] < 1:
				pick = "magnet"
			elif enemy_health <= enemy_max_health * 0.3 and enemy_inventory.has("overcharge") and tracking["overcharge"] < 1:
				pick = "overcharge"

			if pick != "":
				await _enemy_execute_item(pick, tracking)
				if not is_in_combat: return
			else:
				going = false

	if not is_in_combat: return

	# Basic attack
	var raw := 20
	if enemy_sharpened:      raw *= 2;              enemy_sharpened = false
	if enemy_horn_charges > 0: raw = int(raw * 1.5); enemy_horn_charges -= 1
	if enemy_weakened:       raw = int(raw * 0.5);  enemy_weakened = false

	if enemy_cursed:
		enemy_cursed = false
		QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("enemy",  FLASH_CURSE, 0.6)
		await _flash("player", FLASH_HEAL,  0.5)
		if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed — 0 dmg, you healed 20!", false)
	elif player_dodge_active:
		player_dodge_active = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("player", FLASH_DODGE, 0.5)
		if combat_ui: combat_ui.display_round_history("💨 DODGED — enemy attack missed!", false)
	elif player_reflect_active:
		player_reflect_active = false
		enemy_health = clampi(enemy_health - raw, 0, enemy_max_health)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("player", FLASH_REFLECT, 0.5)
		await _flash("enemy",  FLASH_DAMAGE,  0.5)
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d dmg bounced at enemy!" % raw, false)
	elif player_active_armor and not enemy_piercing:
		player_active_armor = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("player", FLASH_SHIELD, 0.5)
		if combat_ui: combat_ui.display_round_history("🛡️ Your shield blocked the hit!", false)
	elif enemy_piercing:
		enemy_piercing = false
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("player", FLASH_DAMAGE, 0.6)
		if combat_ui: combat_ui.display_round_history("🪡 Needle pierced shield for %d dmg!" % raw, false)
	else:
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _flash("player", FLASH_DAMAGE, 0.5)
		if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d dmg!" % raw, false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	await _conclude_round_cycle_ticks()

# ── Enemy item execution (awaited, FX fully completes before returning) ───────
func _enemy_execute_item(item_type: String, tracking: Dictionary) -> void:
	if not enemy_inventory.has(item_type): return
	enemy_inventory.erase(item_type)
	tracking[item_type] = tracking.get(item_type, 0) + 1

	match item_type:
		"potion":
			enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
			await _flash("enemy", FLASH_HEAL, 0.6)
			if combat_ui: combat_ui.display_round_history("🧪 Enemy Potion (+20 HP)", false)
		"shield":
			enemy_active_armor = true
			await _flash("enemy", FLASH_SHIELD, 0.6)
			if combat_ui: combat_ui.display_round_history("🛡️ Enemy raised Shield", false)
		"grindstone":
			enemy_sharpened = true
			await _flash("enemy", FLASH_OVERCHARGE, 0.6)
			if combat_ui: combat_ui.display_round_history("🪨 Enemy Grindstone (2× next attack)", false)
		"whip":
			player_is_disarmed = true
			await _flash("player", FLASH_DISARM, 0.6)
			if combat_ui: combat_ui.display_round_history("💥 Enemy Whip — YOUR turn skipped!", false)
		"needle":
			enemy_piercing = true
			await _flash("enemy", FLASH_OVERCHARGE, 0.5)
			if combat_ui: combat_ui.display_round_history("🪡 Enemy Needle (pierces armor)", false)
		"bandage":
			enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
			enemy_regen_rounds = 2
			await _flash("enemy", FLASH_HEAL, 0.6)
			if combat_ui: combat_ui.display_round_history("🩹 Enemy Bandage (+10 HP + regen)", false)
		"poison_dart":
			player_poison_rounds = 4
			await _flash("player", FLASH_POISON, 0.6)
			if combat_ui: combat_ui.display_round_history("☠️ Enemy poisoned you! (10/round ×4)", false)
		"battle_horn":
			enemy_horn_charges = 2
			await _flash("enemy", FLASH_HORN, 0.6)
			if combat_ui: combat_ui.display_round_history("📯 Enemy Battle Horn (+50% ×2)", false)
		"mirror_ward":
			enemy_reflect_active = true
			await _flash("enemy", FLASH_REFLECT, 0.6)
			if combat_ui: combat_ui.display_round_history("🪞 Enemy Mirror Ward (reflects next hit)", false)
		"smoke_bomb":
			enemy_dodge_active = true
			await _flash("enemy", FLASH_DODGE, 0.6)
			if combat_ui: combat_ui.display_round_history("💨 Enemy Smoke Bomb (next attack misses)", false)
		"weaken_totem":
			player_cursed = true
			await _flash("player", FLASH_CURSE, 0.6)
			if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed your next attack!", false)
		"static_field":
			player_items_locked = true
			await _flash("player", FLASH_STATIC, 0.6)
			if combat_ui: combat_ui.display_round_history("⚡ Enemy locked your items next turn!", false)
		"time_warp":
			player_is_disarmed = true
			player_stun_extra_turns += 1
			await _flash("player", FLASH_TIMEWARP, 0.8)
			if combat_ui: combat_ui.display_round_history("⏳ Enemy Time Warp — YOU skip 2 turns!", false)
		"overcharge":
			enemy_piercing = true
			enemy_sharpened = true
			await _flash("enemy", FLASH_OVERCHARGE, 0.8)
			if combat_ui: combat_ui.display_round_history("🔥 Enemy Overcharged — pierce + 2×!", false)
		"chain_hook":
			var valid = player_inventory.filter(func(i): return i != "chain_hook")
			player_weakened = true
			if valid.size() > 0:
				var st = valid.pick_random()
				player_inventory.erase(st)
				enemy_inventory.append(st)
				await _flash("player", FLASH_STEAL, 0.5)
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy Chain Hook stole [%s]!" % st, false)
			else:
				await _flash("player", FLASH_CURSE, 0.4)
				if combat_ui: combat_ui.display_round_history("⛓️ Enemy Chain Hook weakened you.", false)
		"magnet":
			var valid = player_inventory.filter(func(i): return i != "magnet")
			if valid.size() > 0:
				var st := ""
				if valid.has("needle"):       st = "needle"
				elif valid.has("grindstone"): st = "grindstone"
				elif valid.has("shield"):     st = "shield"
				else: st = valid.pick_random()
				player_inventory.erase(st)
				enemy_inventory.append(st)
				await _flash("player", FLASH_STEAL, 0.5)
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet stole [%s]!" % st, false)
			else:
				enemy_inventory.append("magnet")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet fizzled — refunded.", false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout

# ── Round tick (DoT/HoT) ─────────────────────────────────────────────────────
func _conclude_round_cycle_ticks() -> void:
	await _process_dot_hot_ticks()
	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	if await _check_combat_end_conditions(): return
	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		if combat_ui: combat_ui.display_round_history("📦 Supply drop — new items added!", true)
	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()

func _process_dot_hot_ticks() -> void:
	var log := ""
	if player_poison_rounds > 0:
		player_poison_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health - 10, 0, QuestManager.MAX_HEALTH)
		await _flash("player", FLASH_POISON, 0.4)
		log += "☠️ Poison ticked — 10 dmg (%d left)\n" % player_poison_rounds
	if enemy_poison_rounds > 0:
		enemy_poison_rounds -= 1
		enemy_health = clampi(enemy_health - 10, 0, enemy_max_health)
		await _flash("enemy", FLASH_POISON, 0.4)
		log += "☠️ Enemy poison ticked — 10 dmg (%d left)\n" % enemy_poison_rounds
	if player_regen_rounds > 0:
		player_regen_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
		await _flash("player", FLASH_HEAL, 0.4)
		log += "🩹 Regen healed you 10 HP (%d left)\n" % player_regen_rounds
	if enemy_regen_rounds > 0:
		enemy_regen_rounds -= 1
		enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
		await _flash("enemy", FLASH_HEAL, 0.4)
		log += "🩹 Enemy regen healed 10 HP (%d left)\n" % enemy_regen_rounds
	if log != "" and combat_ui:
		combat_ui.display_round_history(log.strip_edges(), true)
		await get_tree().create_timer(ACTION_PAUSE).timeout

func _apply_supply_drop_rewards() -> void:
	drop_round_index += 1
	var items_this_drop = min(drop_round_index, 6)
	current_items_per_deal = items_this_drop
	const DROP_SCHEDULE = [1, 2, 4, 6, 8]
	cycles_until_drop = DROP_SCHEDULE[min(drop_round_index, DROP_SCHEDULE.size() - 1)]
	for i in range(items_this_drop):
		if QuestManager.equipped_items.size() > 0:
			player_inventory.append(QuestManager.equipped_items.pick_random())
		if enemy_item_pool.size() > 0:
			enemy_inventory.append(enemy_item_pool.pick_random())

func _reset_all_combat_modifiers() -> void:
	player_active_armor = false; player_sharpened = false; player_piercing = false
	player_is_disarmed = false;  enemy_active_armor = false; enemy_sharpened = false
	enemy_piercing = false;      enemy_is_disarmed = false
	player_regen_rounds = 0;     enemy_regen_rounds = 0
	player_poison_rounds = 0;    enemy_poison_rounds = 0
	player_horn_charges = 0;     enemy_horn_charges = 0
	player_reflect_active = false; enemy_reflect_active = false
	player_dodge_active = false;   enemy_dodge_active = false
	player_weakened = false;     enemy_weakened = false
	player_cursed = false;       enemy_cursed = false
	player_items_locked = false; enemy_items_locked = false
	player_stun_extra_turns = 0; enemy_stun_extra_turns = 0

func _switch_to_combat_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam): cam.enabled = true; cam.make_current()

func _switch_to_overworld_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam): cam.enabled = false
	if is_instance_valid(player_ref):
		var pcam = player_ref.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(pcam): pcam.enabled = true; pcam.make_current()

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
		var xp := 25
		match enemy_level:
			1: xp = 25
			2: xp = 40
			3: xp = 60
			4: xp = 90
			_: xp = 90 + ((enemy_level - 4) * 30)
		QuestManager.gain_xp(xp)
		QuestManager.player_health = QuestManager.MAX_HEALTH
		var spr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if is_instance_valid(spr) and spr.sprite_frames and spr.sprite_frames.has_animation("die"):
			spr.stop(); spr.play("die")
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(spr): spr.stop()
		if is_instance_valid(player_ref):
			if "velocity" in player_ref: player_ref.velocity = Vector2.ZERO
			player_ref.global_position = QuestManager.player_overworld_position
		_switch_to_overworld_camera()
		queue_free()
		return true
	return false
