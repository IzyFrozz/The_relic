extends CharacterBody2D

@export var enemy_level: int = 1
@export var enemy_id: String = ""   # stable id for save/respawn tracking — auto-generated if blank

@export var battle_player_marker: Marker2D
@export var battle_enemy_marker:  Marker2D
@export var graveyard_marker:     Marker2D
@export var combat_ui:  CanvasLayer
@export var lose_ui:    CanvasLayer

var enemy_health:     int = 100
var enemy_max_health: int = 100
var enemy_inventory:  Array[String] = []
var player_inventory: Array[String] = []
var enemy_item_pool:  Array = []

var cycles_until_drop:    int = 1
var drop_round_index:     int = 0
var current_items_per_deal: int = 1

var player_active_armor:   bool = false;  var enemy_active_armor:   bool = false
var player_sharpened:      bool = false;  var enemy_sharpened:      bool = false
var player_overcharged:    bool = false;  var enemy_overcharged:    bool = false
var player_piercing:       bool = false;  var enemy_piercing:       bool = false
var player_is_disarmed:    bool = false;  var enemy_is_disarmed:    bool = false
var player_weakened:       bool = false;  var enemy_weakened:       bool = false
var player_cursed:         bool = false;  var enemy_cursed:         bool = false
var player_reflect_active: bool = false;  var enemy_reflect_active: bool = false
var player_dodge_active:   bool = false;  var enemy_dodge_active:   bool = false
var player_items_locked:   bool = false;  var enemy_items_locked:   bool = false
var player_lifesteal_active: bool = false; var enemy_lifesteal_active: bool = false

var player_damage_bonus: int = 0;  var enemy_damage_bonus: int = 0

var player_regen_rounds:     int = 0;  var enemy_regen_rounds:     int = 0
var player_poison_rounds:    int = 0;  var enemy_poison_rounds:    int = 0
var player_stun_extra_turns: int = 0;  var enemy_stun_extra_turns: int = 0

var player_ref: Node2D = null
var is_in_combat: bool = false
var enemy_overworld_position: Vector2 = Vector2.ZERO

const ACTION_PAUSE := 0.90
const FX_TINT_DUR  := 0.42

var _player_ground_fx: ColorRect = null
var _enemy_ground_fx:  ColorRect = null

# ── Graveyard / respawn state ──────────────────────────────────────────────────
var _is_defeated_waiting_respawn: bool = false
var _orig_collision_layer: int = 1
var _orig_collision_mask:  int = 1

# =============================================================================
#  FX SYSTEM
# =============================================================================
# NOTE: every fx function checks `is_in_combat` after each await. Combat can
# end (and call _reset_sprite_modulates()) WHILE one of these coroutines is
# still paused mid-await — e.g. a poison tick that hasn't finished its 0.38s
# timer when the killing blow lands. Without this guard, the stale coroutine
# resumes afterward and overwrites the freshly-reset white modulate with its
# own (now-incorrect) "orig" colour, leaving the sprite tinted after the
# fight ends. The guard makes every fx function a no-op once combat is over.

func _get_sprite(target: String) -> AnimatedSprite2D:
	if target == "player":
		if is_instance_valid(player_ref):
			return player_ref.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	else:
		return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _fx_heal(target: String) -> void:
	if not is_in_combat: return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	for _i in 2:
		s.modulate = Color(0.60, 1.45, 0.60, 1.0)
		await get_tree().create_timer(0.15).timeout
		if not is_in_combat: return
		if is_instance_valid(s): s.modulate = orig
		await get_tree().create_timer(0.10).timeout
		if not is_in_combat: return
	_float_icon(target, "✚", Color(0.35, 1.0, 0.45))
	if is_instance_valid(s): s.modulate = orig

func _fx_damage(target: String) -> void:
	if not is_in_combat: return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(1.75, 0.18, 0.18, 1.0)
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_status(target: String, color: Color, icon: String = "") -> void:
	if not is_in_combat: return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = color
	if icon != "": _float_icon(target, icon, color)
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_poison_tick(target: String) -> void:
	if not is_in_combat: return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(0.28, 0.82, 0.28, 1.0)
	_float_icon(target, "☠", Color(0.3, 0.85, 0.3))
	await get_tree().create_timer(0.38).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_steal(from_target: String) -> void:
	if not is_in_combat: return
	var s = _get_sprite(from_target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(0.95, 0.38, 1.12, 1.0)
	_float_icon(from_target, "🧲", Color(0.9, 0.4, 1.0))
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _float_icon(target: String, icon: String, color: Color) -> void:
	if not is_instance_valid(combat_ui): return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var sp  = get_viewport().get_canvas_transform() * s.global_position
	var lbl = Label.new()
	lbl.text = icon
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", color)
	lbl.position     = sp + Vector2(-14, -54)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index      = 200
	combat_ui.add_child(lbl)
	var tw = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 58, 0.88).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.88).set_delay(0.26)
	get_tree().create_timer(0.96).timeout.connect(
		func(): if is_instance_valid(lbl): lbl.queue_free()
	)

func _reset_sprite_modulates() -> void:
	var ps = _get_sprite("player"); if is_instance_valid(ps): ps.modulate = Color.WHITE
	var es = _get_sprite("enemy");  if is_instance_valid(es): es.modulate = Color.WHITE

func _set_ground_fx(target: String, color: Color) -> void:
	var sprite = _get_sprite(target)
	if not is_instance_valid(sprite): return
	var fx: ColorRect
	if target == "player":
		if not is_instance_valid(_player_ground_fx):
			_player_ground_fx = ColorRect.new(); _player_ground_fx.z_index = -1
			sprite.get_parent().add_child(_player_ground_fx)
		fx = _player_ground_fx
	else:
		if not is_instance_valid(_enemy_ground_fx):
			_enemy_ground_fx = ColorRect.new(); _enemy_ground_fx.z_index = -1
			sprite.get_parent().add_child(_enemy_ground_fx)
		fx = _enemy_ground_fx
	if color.a < 0.01:
		fx.visible = false
		return
	fx.color = color; fx.size = Vector2(36, 10)
	fx.position = sprite.position + Vector2(-18, 8); fx.visible = true

func _sync_ground_fx() -> void:
	if player_poison_rounds  > 0: _set_ground_fx("player", Color(0.05, 0.38, 0.05, 0.75))
	elif player_cursed:           _set_ground_fx("player", Color(0.25, 0.05, 0.42, 0.70))
	elif player_regen_rounds > 0: _set_ground_fx("player", Color(0.10, 0.55, 0.10, 0.65))
	elif player_active_armor:     _set_ground_fx("player", Color(0.20, 0.45, 0.90, 0.60))
	elif player_dodge_active:     _set_ground_fx("player", Color(0.20, 0.80, 0.90, 0.55))
	elif player_reflect_active:   _set_ground_fx("player", Color(0.90, 0.80, 0.10, 0.60))
	else:                         _set_ground_fx("player", Color.TRANSPARENT)
	if enemy_poison_rounds  > 0:  _set_ground_fx("enemy", Color(0.05, 0.38, 0.05, 0.75))
	elif enemy_cursed:             _set_ground_fx("enemy", Color(0.25, 0.05, 0.42, 0.70))
	elif enemy_regen_rounds > 0:  _set_ground_fx("enemy", Color(0.10, 0.55, 0.10, 0.65))
	elif enemy_active_armor:      _set_ground_fx("enemy", Color(0.20, 0.45, 0.90, 0.60))
	elif enemy_dodge_active:      _set_ground_fx("enemy", Color(0.20, 0.80, 0.90, 0.55))
	elif enemy_reflect_active:    _set_ground_fx("enemy", Color(0.90, 0.80, 0.10, 0.60))
	else:                         _set_ground_fx("enemy", Color.TRANSPARENT)

func _clear_ground_fx_visibility() -> void:
	if is_instance_valid(_player_ground_fx): _player_ground_fx.visible = false
	if is_instance_valid(_enemy_ground_fx):  _enemy_ground_fx.visible  = false

# =============================================================================
#  INIT
# =============================================================================

func _ready() -> void:
	if enemy_id == "":
		var parent_name = get_parent().name if is_instance_valid(get_parent()) else "root"
		enemy_id = "%s/%s" % [parent_name, name]

	_orig_collision_layer = collision_layer
	_orig_collision_mask  = collision_mask

	_initialize_mob_stats_by_character_tier()
	_auto_wire_overworld_signals()
	enemy_overworld_position = self.global_position
	_check_existing_defeat_state()

func _process(_delta: float) -> void:
	if _is_defeated_waiting_respawn:
		var death_time = QuestManager.defeated_enemies.get(enemy_id, QuestManager.play_time_seconds)
		var elapsed = QuestManager.play_time_seconds - float(death_time)
		if elapsed >= QuestManager.RESPAWN_COOLDOWN_SECONDS:
			QuestManager.defeated_enemies.erase(enemy_id)
			_respawn_enemy()

func _check_existing_defeat_state() -> void:
	if not QuestManager.defeated_enemies.has(enemy_id):
		return
	var death_time = float(QuestManager.defeated_enemies[enemy_id])
	var elapsed = QuestManager.play_time_seconds - death_time
	if elapsed >= QuestManager.RESPAWN_COOLDOWN_SECONDS:
		QuestManager.defeated_enemies.erase(enemy_id)
	else:
		_is_defeated_waiting_respawn = true
		_hide_and_disable_at_graveyard()

func _hide_and_disable_at_graveyard() -> void:
	visible = false
	collision_layer = 0
	collision_mask  = 0
	var dz = find_child("deadzone")
	if is_instance_valid(dz) and dz is Area2D:
		dz.monitoring  = false
		dz.monitorable = false
	if is_instance_valid(graveyard_marker):
		self.global_position = graveyard_marker.global_position
	else:
		self.global_position = enemy_overworld_position

func _respawn_enemy() -> void:
	_is_defeated_waiting_respawn = false
	visible = true
	collision_layer = _orig_collision_layer
	collision_mask  = _orig_collision_mask
	var dz = find_child("deadzone")
	if is_instance_valid(dz) and dz is Area2D:
		dz.monitoring  = true
		dz.monitorable = true
	self.global_position = enemy_overworld_position
	_initialize_mob_stats_by_character_tier()

func _auto_wire_overworld_signals() -> void:
	var dz = find_child("deadzone")
	if dz and dz.has_signal("body_entered"):
		if dz.body_entered.is_connected(_on_deadzone_body_entered):
			dz.body_entered.disconnect(_on_deadzone_body_entered)
		dz.body_entered.connect(_on_deadzone_body_entered)

const TIER_POOLS_LV6_PLUS := {
	6:  ["potion", "shield", "grindstone", "needle", "magnet", "poison_dart"],
	7:  ["shield", "whip",   "poison_dart", "bandage", "needle", "magnet"],
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
		if enemy_level >= 3: enemy_item_pool.append("needle")
		if enemy_level >= 4: enemy_item_pool.append("whip")
		if enemy_level >= 5: enemy_item_pool.append("magnet")
	else:
		enemy_item_pool = TIER_POOLS_LV6_PLUS.get(
			enemy_level, ["potion", "shield", "grindstone", "needle"]).duplicate()
	enemy_health = enemy_max_health
	current_items_per_deal = 1

func _on_deadzone_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer" and not is_in_combat and not _is_defeated_waiting_respawn:
		player_ref = body
		start_combat()

# =============================================================================
#  COMBAT START
# =============================================================================

func start_combat() -> void:
	is_in_combat = true
	QuestManager.is_in_combat = true
	if is_instance_valid(player_ref) and "velocity" in player_ref:
		player_ref.velocity = Vector2.ZERO
	enemy_overworld_position = self.global_position
	_initialize_mob_stats_by_character_tier()
	player_inventory.clear(); enemy_inventory.clear()
	_reset_all_combat_modifiers()
	_clear_ground_fx_visibility()
	drop_round_index = 0; cycles_until_drop = 1
	QuestManager.player_health = QuestManager.MAX_HEALTH
	_apply_supply_drop_rewards()

	if is_instance_valid(player_ref):
		QuestManager.player_overworld_position = player_ref.global_position

	# ── Fighter positioning ───────────────────────────────────────────────────
	# Trust the scene's own authored markers exactly as placed in the editor.
	if is_instance_valid(battle_player_marker):
		player_ref.global_position = battle_player_marker.global_position
	if is_instance_valid(battle_enemy_marker):
		self.global_position = battle_enemy_marker.global_position

	if is_instance_valid(player_ref) and player_ref.has_method("face_right"):
		player_ref.face_right()

	var espr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(espr):
		espr.flip_h = true

	_switch_to_combat_camera()
	if is_instance_valid(combat_ui):
		combat_ui.open_combat_screen(self)
		combat_ui.start_player_turn()

# =============================================================================
#  PLAYER ITEM USE
# =============================================================================

func use_player_item(item_type: String) -> void:
	if not item_type in player_inventory: return

	match item_type:
		"magnet":
			var stealable = enemy_inventory.filter(func(i: String) -> bool:
				return (i in QuestManager.equipped_items) and i != "magnet" and i != "chain_hook"
			)
			if stealable.is_empty():
				if combat_ui:
					combat_ui.display_round_history("🧲 Magnet fizzled — nothing stealable from your loadout!", true)
					combat_ui._refresh_ui_states()
				return
			if combat_ui:
				var chosen = await combat_ui.show_magnet_choice_popup(stealable)
				if chosen != "":
					player_inventory.erase("magnet"); enemy_inventory.erase(chosen)
					player_inventory.append(chosen)
					await _fx_steal("enemy")
					combat_ui.display_round_history("🧲 Magnet swiped [%s]!" % chosen.to_upper(), true)
				else:
					combat_ui.display_round_history("🧲 Magnet cancelled.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return

		"chain_hook":
			player_inventory.erase("chain_hook")
			var valid = enemy_inventory.filter(func(i: String) -> bool:
				return i != "chain_hook" and i != "magnet" and i in QuestManager.equipped_items
			)
			enemy_weakened = true
			if valid.size() > 0:
				var st = valid.pick_random()
				enemy_inventory.erase(st); player_inventory.append(st)
				await _fx_steal("enemy")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Chain Hook yanked [%s] + enemy next attack -20!" % st.to_upper(), true)
			else:
				await _fx_status("enemy", Color(1.0, 0.65, 0.1, 1.0), "⛓️")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Chain Hook — nothing to steal, enemy next attack -20.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return

		_:
			player_inventory.erase(item_type)

	match item_type:
		"potion":
			QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🧪 Potion (+20 HP)", true)
		"shield":
			player_active_armor = true
			await _fx_status("player", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Shield raised", true)
		"grindstone":
			player_sharpened = true
			player_damage_bonus += 20
			await _fx_status("player", Color(1.0, 0.58, 0.10, 1.0), "🪨")
			if combat_ui: combat_ui.display_round_history(
				"🪨 Grindstone — +20 damage bonus (total bonus: +%d)" % player_damage_bonus, true)
		"whip":
			enemy_is_disarmed = true
			await _fx_status("enemy", Color(1.0, 0.68, 0.10, 1.0), "💥")
			if combat_ui: combat_ui.display_round_history("💥 Whip — enemy turn skipped!", true)
		"needle":
			player_piercing = true
			await _fx_status("player", Color(0.80, 0.55, 1.0, 1.0), "📌")
			if combat_ui: combat_ui.display_round_history("📌 Needle — next hit pierces armor", true)
		"bandage":
			QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
			player_regen_rounds = 2
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🩹 Bandage (+10 HP + regen ×2)", true)
		"poison_dart":
			enemy_poison_rounds = 3
			await _fx_status("enemy", Color(0.22, 0.72, 0.22, 1.0), "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Poison Dart — enemy 10/round ×3", true)
		"battle_horn":
			player_lifesteal_active = true
			await _fx_status("player", Color(0.90, 0.20, 0.40, 1.0), "🩸")
			if combat_ui: combat_ui.display_round_history(
				"🩸 Lifesteal Vial — next attack heals 50% of damage dealt!", true)
		"mirror_ward":
			player_reflect_active = true
			await _fx_status("player", Color(1.0, 0.90, 0.22, 1.0), "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Mirror Ward — next hit fully reflected!", true)
		"smoke_bomb":
			player_dodge_active = true
			await _fx_status("player", Color(0.30, 0.90, 1.0, 1.0), "💨")
			if combat_ui: combat_ui.display_round_history("💨 Smoke Bomb — next attack misses!", true)
		"weaken_totem":
			enemy_cursed = true
			await _fx_status("enemy", Color(0.70, 0.20, 1.0, 1.0), "🗿")
			if combat_ui: combat_ui.display_round_history(
				"🗿 Weaken Totem — enemy attack becomes a 20 HP heal for you!", true)
		"static_field":
			enemy_items_locked = true
			await _fx_status("enemy", Color(0.70, 0.90, 1.0, 1.0), "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Static Field — enemy items locked!", true)
		"time_warp":
			enemy_is_disarmed = true; enemy_stun_extra_turns += 1
			await _fx_status("enemy", Color(0.70, 1.0, 0.95, 1.0), "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Time Warp — enemy skips 2 turns!", true)
		"overcharge":
			player_overcharged = true
			player_damage_bonus += 20
			player_piercing = true
			await _fx_status("player", Color(1.0, 0.52, 0.10, 1.0), "🔥")
			if combat_ui: combat_ui.display_round_history(
				"🔥 Overcharge — +20 damage + pierces armor (total bonus: +%d)" % player_damage_bonus, true)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()

# =============================================================================
#  PLAYER ATTACK PHASE
# =============================================================================

func process_player_attack_phase() -> void:
	if player_items_locked: player_items_locked = false

	if player_is_disarmed:
		player_is_disarmed = false
		if player_stun_extra_turns > 0:
			player_stun_extra_turns -= 1; player_is_disarmed = true
		player_damage_bonus = 0; player_sharpened = false; player_overcharged = false
		player_lifesteal_active = false
		await _fx_status("player", Color(1.0, 0.68, 0.10, 1.0), "❌")
		if combat_ui:
			combat_ui.display_round_history("💥 DISARMED — your attack was skipped!", true)
			combat_ui._refresh_ui_states()
		await get_tree().create_timer(ACTION_PAUSE).timeout
		if await _check_combat_end_conditions(): return
		if combat_ui: combat_ui.start_enemy_turn_visuals()
		await get_tree().create_timer(1.0).timeout
		_execute_enemy_turn_ai()
		return

	var dmg = 20 + player_damage_bonus
	player_damage_bonus = 0; player_sharpened = false; player_overcharged = false
	if player_weakened:
		dmg = maxi(0, dmg - 20)
		player_weakened = false

	var actual_dmg_dealt := 0

	if player_cursed:
		player_cursed = false
		player_lifesteal_active = false
		enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
		await _fx_status("player", Color(0.70, 0.20, 1.0, 1.0), "🗿")
		await _fx_heal("enemy")
		if combat_ui: combat_ui.display_round_history("🗿 CURSED — 0 dmg, healed enemy 20 HP!", true)
	elif enemy_dodge_active:
		enemy_dodge_active = false
		player_lifesteal_active = false
		await _fx_status("enemy", Color(0.30, 0.90, 1.0, 1.0), "💨")
		if combat_ui: combat_ui.display_round_history("💨 Enemy dodged — missed!", true)
	elif enemy_reflect_active:
		enemy_reflect_active = false
		player_lifesteal_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - dmg, 0, QuestManager.MAX_HEALTH)
		await _fx_status("enemy", Color(1.0, 0.90, 0.22, 1.0), "🪞")
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d dmg bounced back at you!" % dmg, true)
	elif enemy_active_armor and not player_piercing:
		enemy_active_armor = false
		player_lifesteal_active = false
		await _fx_status("enemy", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy shield blocked your hit!", true)
	else:
		if player_piercing: player_piercing = false
		enemy_health = clampi(enemy_health - dmg, 0, enemy_max_health)
		actual_dmg_dealt = dmg
		await _fx_damage("enemy")
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d damage!" % dmg, true)

	if player_lifesteal_active:
		player_lifesteal_active = false
		if actual_dmg_dealt > 0:
			var steal_heal = actual_dmg_dealt / 2
			QuestManager.player_health = clampi(
				QuestManager.player_health + steal_heal, 0, QuestManager.MAX_HEALTH)
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🩸 Lifesteal — healed %d HP!" % steal_heal, true)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.0).timeout
	_execute_enemy_turn_ai()

# =============================================================================
#  ENEMY AI TURN
# =============================================================================

func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		if enemy_stun_extra_turns > 0:
			enemy_stun_extra_turns -= 1; enemy_is_disarmed = true
		enemy_damage_bonus = 0; enemy_sharpened = false
		enemy_overcharged  = false; enemy_lifesteal_active = false
		await _fx_status("enemy", Color(1.0, 0.68, 0.10, 1.0), "❌")
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui: combat_ui.display_round_history("💥 Enemy disarmed — turn skipped!", false)
		await _conclude_round_cycle_ticks()
		return

	var tracking: Dictionary = {}
	var sg_eval := false

	if enemy_items_locked:
		enemy_items_locked = false
		await _fx_status("enemy", Color(0.70, 0.90, 1.0, 1.0), "⚡")
		if combat_ui: combat_ui.display_round_history("⚡ Enemy items LOCKED — basic attack only!", false)
		await get_tree().create_timer(ACTION_PAUSE).timeout
	else:
		var going := true
		while going:
			var pick := ""
			if enemy_health <= enemy_max_health - 20 and enemy_inventory.has("potion") and tracking.get("potion", 0) < 1:
				pick = "potion"
			elif enemy_health <= enemy_max_health - 20 and enemy_inventory.has("bandage") and tracking.get("bandage", 0) < 1:
				pick = "bandage"
			elif not player_is_disarmed and enemy_health <= enemy_max_health * 0.4 and enemy_inventory.has("time_warp") and tracking.get("time_warp", 0) < 1:
				pick = "time_warp"
			elif not player_is_disarmed and enemy_inventory.has("whip") and tracking.get("whip", 0) < 1:
				pick = "whip"
			elif not enemy_dodge_active and enemy_inventory.has("smoke_bomb") and tracking.get("smoke_bomb", 0) < 1 and randf() < 0.35:
				pick = "smoke_bomb"
			elif not enemy_reflect_active and not enemy_dodge_active and enemy_inventory.has("mirror_ward") and tracking.get("mirror_ward", 0) < 1 and randf() < 0.35:
				pick = "mirror_ward"
			elif player_active_armor and enemy_inventory.has("grindstone") and tracking.get("grindstone", 0) < 1 and not sg_eval:
				sg_eval = true
				if randf() < 0.5:
					pick = "grindstone"
				else:
					tracking["grindstone"] = 1
			elif player_active_armor and enemy_inventory.has("needle") and tracking.get("needle", 0) < 1 and not enemy_piercing:
				pick = "needle"
			elif not enemy_active_armor and enemy_inventory.has("shield") and tracking.get("shield", 0) < 1:
				pick = "shield"
			elif not enemy_sharpened and enemy_inventory.has("grindstone") and tracking.get("grindstone", 0) < 1:
				pick = "grindstone"
			elif not enemy_lifesteal_active and enemy_inventory.has("battle_horn") and tracking.get("battle_horn", 0) < 1:
				pick = "battle_horn"
			elif enemy_poison_rounds <= 0 and enemy_inventory.has("poison_dart") and tracking.get("poison_dart", 0) < 1:
				pick = "poison_dart"
			elif not player_cursed and enemy_inventory.has("weaken_totem") and tracking.get("weaken_totem", 0) < 1 and randf() < 0.6:
				pick = "weaken_totem"
			elif not player_items_locked and enemy_inventory.has("static_field") and tracking.get("static_field", 0) < 1 and randf() < 0.45:
				pick = "static_field"
			elif player_inventory.size() >= 2 and enemy_inventory.has("chain_hook") and tracking.get("chain_hook", 0) < 1:
				pick = "chain_hook"
			elif player_inventory.size() > 0 and enemy_inventory.has("magnet") and tracking.get("magnet", 0) < 1:
				pick = "magnet"
			elif enemy_health <= enemy_max_health * 0.3 and enemy_inventory.has("overcharge") and tracking.get("overcharge", 0) < 1:
				pick = "overcharge"

			if pick != "":
				await _enemy_execute_item(pick, tracking)
				if not is_in_combat: return
				await get_tree().create_timer(ACTION_PAUSE).timeout
			else:
				going = false

	if not is_in_combat: return

	var raw = 20 + enemy_damage_bonus
	enemy_damage_bonus = 0; enemy_sharpened = false; enemy_overcharged = false
	if enemy_weakened:
		raw = maxi(0, raw - 20)
		enemy_weakened = false

	var actual_dmg_to_player := 0

	if enemy_cursed:
		enemy_cursed = false
		enemy_lifesteal_active = false
		QuestManager.player_health = clampi(QuestManager.player_health + 20, 0, QuestManager.MAX_HEALTH)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("enemy", Color(0.70, 0.20, 1.0, 1.0))
		await _fx_heal("player")
		if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed — 0 dmg, you healed 20 HP!", false)
	elif player_dodge_active:
		player_dodge_active = false
		enemy_lifesteal_active = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("player", Color(0.30, 0.90, 1.0, 1.0), "💨")
		if combat_ui: combat_ui.display_round_history("💨 DODGED — enemy attack missed!", false)
	elif player_reflect_active:
		player_reflect_active = false
		enemy_lifesteal_active = false
		enemy_health = clampi(enemy_health - raw, 0, enemy_max_health)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("player", Color(1.0, 0.90, 0.22, 1.0), "🪞")
		await _fx_damage("enemy")
		if combat_ui: combat_ui.display_round_history(
			"🪞 REFLECTED — %d dmg bounced back at the enemy!" % raw, false)
	elif player_active_armor and not enemy_piercing:
		player_active_armor = false
		enemy_lifesteal_active = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("player", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Your shield blocked the hit!", false)
	elif enemy_piercing:
		enemy_piercing = false
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		actual_dmg_to_player = raw
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("📌 Enemy needle pierced for %d dmg!" % raw, false)
	else:
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		actual_dmg_to_player = raw
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d damage!" % raw, false)

	if enemy_lifesteal_active:
		enemy_lifesteal_active = false
		if actual_dmg_to_player > 0:
			var steal_heal = actual_dmg_to_player / 2
			enemy_health = clampi(enemy_health + steal_heal, 0, enemy_max_health)
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history("🩸 Enemy lifesteal — healed %d HP!" % steal_heal, false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	await _conclude_round_cycle_ticks()

# =============================================================================
#  ENEMY ITEM EXECUTION
# =============================================================================

func _enemy_execute_item(item_type: String, tracking: Dictionary) -> void:
	if not enemy_inventory.has(item_type): return
	enemy_inventory.erase(item_type)
	tracking[item_type] = tracking.get(item_type, 0) + 1

	match item_type:
		"potion":
			enemy_health = clampi(enemy_health + 20, 0, enemy_max_health)
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history("🧪 Enemy Potion (+20 HP)", false)
		"shield":
			enemy_active_armor = true
			await _fx_status("enemy", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Enemy Shield raised", false)
		"grindstone":
			enemy_sharpened = true
			enemy_damage_bonus += 20
			await _fx_status("enemy", Color(1.0, 0.58, 0.10, 1.0), "🪨")
			if combat_ui: combat_ui.display_round_history(
				"🪨 Enemy Grindstone — +20 damage (total: +%d)" % enemy_damage_bonus, false)
		"whip":
			player_is_disarmed = true
			await _fx_status("player", Color(1.0, 0.68, 0.10, 1.0), "💥")
			if combat_ui: combat_ui.display_round_history("💥 Enemy Whip — YOUR turn skipped!", false)
		"needle":
			enemy_piercing = true
			await _fx_status("enemy", Color(0.80, 0.55, 1.0, 1.0), "📌")
			if combat_ui: combat_ui.display_round_history("📌 Enemy Needle — next hit pierces armor", false)
		"bandage":
			enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
			enemy_regen_rounds = 2
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history("🩹 Enemy Bandage (+10 HP + regen ×2)", false)
		"poison_dart":
			player_poison_rounds = 3
			await _fx_status("player", Color(0.22, 0.72, 0.22, 1.0), "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Enemy poisoned you! (10/round ×3)", false)
		"battle_horn":
			enemy_lifesteal_active = true
			await _fx_status("enemy", Color(0.90, 0.20, 0.40, 1.0), "🩸")
			if combat_ui: combat_ui.display_round_history(
				"🩸 Enemy Lifesteal Vial — their next attack heals them 50%!", false)
		"mirror_ward":
			enemy_reflect_active = true
			await _fx_status("enemy", Color(1.0, 0.90, 0.22, 1.0), "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Enemy Mirror Ward — your next hit reflected!", false)
		"smoke_bomb":
			enemy_dodge_active = true
			await _fx_status("enemy", Color(0.30, 0.90, 1.0, 1.0), "💨")
			if combat_ui: combat_ui.display_round_history("💨 Enemy Smoke Bomb — your next attack misses!", false)
		"weaken_totem":
			player_cursed = true
			await _fx_status("player", Color(0.70, 0.20, 1.0, 1.0), "🗿")
			if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed your next attack!", false)
		"static_field":
			player_items_locked = true
			await _fx_status("player", Color(0.70, 0.90, 1.0, 1.0), "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Enemy locked your items next turn!", false)
		"time_warp":
			player_is_disarmed = true; player_stun_extra_turns += 1
			await _fx_status("player", Color(0.70, 1.0, 0.95, 1.0), "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Enemy Time Warp — you skip 2 turns!", false)
		"overcharge":
			enemy_overcharged = true
			enemy_damage_bonus += 20
			enemy_piercing = true
			await _fx_status("enemy", Color(1.0, 0.52, 0.10, 1.0), "🔥")
			if combat_ui: combat_ui.display_round_history("🔥 Enemy Overcharge — +20 damage + pierces armor!", false)
		"chain_hook":
			var valid = player_inventory.filter(func(i: String) -> bool:
				return i != "chain_hook" and i != "magnet" and i in enemy_item_pool
			)
			player_weakened = true
			if valid.size() > 0:
				var st = valid.pick_random()
				player_inventory.erase(st); enemy_inventory.append(st)
				await _fx_steal("player")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Enemy Chain Hook stole [%s] + your next attack -20!" % st, false)
			else:
				await _fx_status("player", Color(1.0, 0.65, 0.1, 1.0), "⛓️")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Enemy Chain Hook — nothing stealable, your next attack -20.", false)
		"magnet":
			var valid = player_inventory.filter(func(i: String) -> bool:
				return i != "magnet" and i != "chain_hook" and i in enemy_item_pool
			)
			if valid.size() > 0:
				var st := ""
				if valid.has("needle"):       st = "needle"
				elif valid.has("grindstone"): st = "grindstone"
				elif valid.has("shield"):     st = "shield"
				else:                         st = valid.pick_random()
				player_inventory.erase(st); enemy_inventory.append(st)
				await _fx_steal("player")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet stole [%s]!" % st, false)
			else:
				enemy_inventory.append("magnet")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet fizzled.", false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()

# =============================================================================
#  ROUND TICKS
# =============================================================================

func _conclude_round_cycle_ticks() -> void:
	await _process_dot_hot_ticks()
	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	if await _check_combat_end_conditions(): return
	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		if combat_ui: combat_ui.display_round_history("📦 Supply drop — new items!", true)
	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()

func _process_dot_hot_ticks() -> void:
	if player_poison_rounds > 0:
		player_poison_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health - 10, 0, QuestManager.MAX_HEALTH)
		await _fx_poison_tick("player")
		if combat_ui: combat_ui.display_round_history(
			"☠️ Poison ticked — 10 dmg (%d left)" % player_poison_rounds, true)
	if enemy_poison_rounds > 0:
		enemy_poison_rounds -= 1
		enemy_health = clampi(enemy_health - 10, 0, enemy_max_health)
		await _fx_poison_tick("enemy")
		if combat_ui: combat_ui.display_round_history(
			"☠️ Enemy poison ticked — 10 dmg (%d left)" % enemy_poison_rounds, true)
	if player_regen_rounds > 0:
		player_regen_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health + 10, 0, QuestManager.MAX_HEALTH)
		await _fx_heal("player")
		if combat_ui: combat_ui.display_round_history(
			"🩹 Regen healed 10 HP (%d left)" % player_regen_rounds, true)
	if enemy_regen_rounds > 0:
		enemy_regen_rounds -= 1
		enemy_health = clampi(enemy_health + 10, 0, enemy_max_health)
		await _fx_heal("enemy")
		if combat_ui: combat_ui.display_round_history(
			"🩹 Enemy regen +10 HP (%d left)" % enemy_regen_rounds, true)
	if (player_poison_rounds + enemy_poison_rounds + player_regen_rounds + enemy_regen_rounds) > 0:
		await get_tree().create_timer(0.30).timeout

func _apply_supply_drop_rewards() -> void:
	drop_round_index += 1
	var items_this_drop = min(drop_round_index, 6)
	current_items_per_deal = items_this_drop
	const DROP_SCHEDULE = [1, 2, 4, 6, 8]
	cycles_until_drop = DROP_SCHEDULE[min(drop_round_index, DROP_SCHEDULE.size() - 1)]
	for _i in range(items_this_drop):
		if QuestManager.equipped_items.size() > 0:
			player_inventory.append(QuestManager.equipped_items.pick_random())
		if enemy_item_pool.size() > 0:
			enemy_inventory.append(enemy_item_pool.pick_random())

func _reset_all_combat_modifiers() -> void:
	player_active_armor   = false;  enemy_active_armor   = false
	player_sharpened      = false;  enemy_sharpened      = false
	player_overcharged    = false;  enemy_overcharged    = false
	player_piercing       = false;  enemy_piercing       = false
	player_is_disarmed    = false;  enemy_is_disarmed    = false
	player_weakened       = false;  enemy_weakened       = false
	player_cursed         = false;  enemy_cursed         = false
	player_reflect_active = false;  enemy_reflect_active = false
	player_dodge_active   = false;  enemy_dodge_active   = false
	player_items_locked   = false;  enemy_items_locked   = false
	player_lifesteal_active = false; enemy_lifesteal_active = false
	player_damage_bonus   = 0;      enemy_damage_bonus   = 0
	player_regen_rounds   = 0;      enemy_regen_rounds   = 0
	player_poison_rounds  = 0;      enemy_poison_rounds  = 0
	player_stun_extra_turns = 0;    enemy_stun_extra_turns = 0

func _switch_to_combat_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam):
		cam.enabled = true
		cam.make_current()

func _switch_to_overworld_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam):
		cam.enabled = false
	if is_instance_valid(player_ref):
		var pcam = player_ref.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(pcam):
			pcam.enabled = true
			pcam.make_current()

func _check_combat_end_conditions() -> bool:
	if QuestManager.player_health <= 0:
		# Set is_in_combat false FIRST so any in-flight fx coroutines bail out
		# on their next resume instead of re-applying a stale tint.
		is_in_combat = false; QuestManager.is_in_combat = false
		_reset_sprite_modulates()
		_clear_ground_fx_visibility()
		if is_instance_valid(combat_ui): combat_ui.visible = false
		self.global_position = enemy_overworld_position
		_switch_to_overworld_camera()
		if is_instance_valid(lose_ui) and lose_ui.has_method("show_death_screen"):
			lose_ui.show_death_screen()
		return true

	if enemy_health <= 0:
		is_in_combat = false; QuestManager.is_in_combat = false
		_reset_sprite_modulates()
		_clear_ground_fx_visibility()
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

		# Hard reset once more after the death-animation wait, defensive
		# against anything that may have queued during that 1s window.
		_reset_sprite_modulates()

		# ── Graveyard respawn instead of permanent removal ─────────────────────
		QuestManager.defeated_enemies[enemy_id] = QuestManager.play_time_seconds
		_is_defeated_waiting_respawn = true
		_hide_and_disable_at_graveyard()
		return true

	return false
