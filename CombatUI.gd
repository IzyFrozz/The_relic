extends CanvasLayer

var current_enemy = null
var is_waiting_on_action: bool = false
var _is_enemy_turn: bool = false

var drop_countdown_label: Label
var fight_button: Button
var player_hp: Label
var player_buffs_lbl: Label
var enemy_hp: Label
var enemy_buffs_lbl: Label

var item_buttons: Array = []
var enemy_inventory_container: GridContainer
var enemy_item_labels: Array = []
var enemy_item_labels_pool_ref: Array = []

var popup_overlay: ColorRect
var popup_panel: Panel
var popup_title_lbl: Label
var popup_label: Label
var popup_confirm_btn: Button
var popup_cancel_btn: Button
var magnet_currently_selected_item: String = ""

signal popup_resolved(confirmed: bool)
signal magnet_choice_resolved(chosen_item_id: String)

const SLOT_KEYS := ["1","2","3","4","5","6"]

func _ready() -> void:
	visible = false
	_find_nodes_automatically()
	_connect_fight_button()
	_apply_card_styles()
	_build_dynamic_popup_window()
	_disable_engine_focus_modes()

func _find_nodes_automatically() -> void:
	drop_countdown_label      = find_child("DropCountdownLabel") as Label
	fight_button              = find_child("fight_button") as Button
	player_hp                 = find_child("PlayerHPLabel") as Label
	player_buffs_lbl          = find_child("PlayerBuffsLabel") as Label
	enemy_hp                  = find_child("EnemyHPLabel") as Label
	enemy_buffs_lbl           = find_child("EnemyBuffsLabel") as Label
	enemy_inventory_container = find_child("EnemyItemsGrid") as GridContainer

func _apply_card_styles() -> void:
	var _make := func() -> StyleBoxFlat:
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.07, 0.08, 0.13, 0.93)
		s.set_corner_radius_all(8); s.set_border_width_all(2)
		s.border_color = Color(0.28, 0.33, 0.52, 1.0)
		s.content_margin_left = 12; s.content_margin_right  = 12
		s.content_margin_top  = 10; s.content_margin_bottom = 10
		return s
	var tl = find_child("TopLeftCard")  as Panel
	var tr = find_child("TopRightCard") as Panel
	var bp = find_child("BottomPanel")  as Panel
	if is_instance_valid(tl): tl.add_theme_stylebox_override("panel", _make.call())
	if is_instance_valid(tr): tr.add_theme_stylebox_override("panel", _make.call())
	if is_instance_valid(bp):
		var bs = StyleBoxFlat.new(); bs.bg_color = Color(0.06, 0.07, 0.11, 0.93)
		bs.set_border_width_all(0); bp.add_theme_stylebox_override("panel", bs)
	if is_instance_valid(player_hp):
		player_hp.add_theme_font_size_override("font_size", 14)
		player_hp.add_theme_color_override("font_color", Color(1.00, 0.92, 0.86))
		player_hp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(enemy_hp):
		enemy_hp.add_theme_font_size_override("font_size", 14)
		enemy_hp.add_theme_color_override("font_color", Color(1.00, 0.75, 0.75))
		enemy_hp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for lbl in [player_buffs_lbl, enemy_buffs_lbl]:
		if is_instance_valid(lbl):
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(drop_countdown_label):
		drop_countdown_label.add_theme_font_size_override("font_size", 14)
		drop_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		drop_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _connect_fight_button() -> void:
	if fight_button:
		for c in fight_button.pressed.get_connections():
			fight_button.pressed.disconnect(c.callable)
		fight_button.pressed.connect(_on_fight_pressed)
		_style_fight_button()

func _style_fight_button() -> void:
	if not is_instance_valid(fight_button): return
	fight_button.focus_mode = Control.FOCUS_NONE
	fight_button.add_theme_font_size_override("font_size", 22)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.13, 0.21, 0.95); s.set_corner_radius_all(10); s.set_border_width_all(2)
	s.border_color = Color(0.50, 0.42, 0.80)
	fight_button.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = Color(0.17, 0.19, 0.32, 0.95); sh.border_color = Color(0.72, 0.62, 1.0)
	fight_button.add_theme_stylebox_override("hover", sh)
	var sd = s.duplicate(); sd.bg_color = Color(0.08, 0.09, 0.14, 0.80); sd.border_color = Color(0.22, 0.22, 0.36)
	fight_button.add_theme_stylebox_override("disabled", sd)

func _disable_engine_focus_modes() -> void:
	for btn in [fight_button, popup_confirm_btn, popup_cancel_btn]:
		if is_instance_valid(btn): btn.focus_mode = Control.FOCUS_NONE

func start_player_turn() -> void:
	_is_enemy_turn = false; is_waiting_on_action = false; _refresh_ui_states()

func start_enemy_turn_visuals() -> void:
	_is_enemy_turn = true; _lock_all_player_inputs()

func display_round_history(summary_text: String, target_player_log: bool = true) -> void:
	print("[COMBAT] ", "▶ YOU: " if target_player_log else "◀ ENEMY: ", summary_text)

func _build_item_buttons() -> void:
	for btn in item_buttons:
		if is_instance_valid(btn): btn.queue_free()
	item_buttons.clear()
	var grid = find_child("PlayerItemsGrid")
	if not is_instance_valid(grid): return
	if grid is GridContainer: (grid as GridContainer).columns = 2
	var slots = QuestManager.equipped_items
	for i in range(slots.size()):
		var item_id = slots[i]
		var meta = QuestManager.ITEM_META.get(item_id, {"emoji":"❓","label":item_id.capitalize(),"desc":""})
		var btn = Button.new()
		btn.name = "ItemBtn_%d" % i; btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(148, 70)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = "%s %s\n%s\n[%s]" % [meta["emoji"], meta["label"], meta["desc"],
			SLOT_KEYS[i] if i < SLOT_KEYS.size() else ""]
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.11, 0.16, 0.96); style.set_corner_radius_all(7); style.set_border_width_all(1)
		style.border_color = Color(0.32, 0.32, 0.50)
		style.content_margin_left = 8; style.content_margin_right = 8
		style.content_margin_top  = 6; style.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", style)
		var hs = style.duplicate(); hs.border_color = Color(0.62, 0.62, 1.0); hs.bg_color = Color(0.15, 0.17, 0.26, 0.96)
		btn.add_theme_stylebox_override("hover", hs)
		var ds = style.duplicate(); ds.bg_color = Color(0.08, 0.08, 0.12, 0.70); ds.border_color = Color(0.20, 0.20, 0.30)
		btn.add_theme_stylebox_override("disabled", ds)
		btn.add_theme_font_size_override("font_size", 13)
		var cid = item_id
		btn.pressed.connect(func(): _on_item_used(cid))
		grid.add_child(btn); item_buttons.append(btn)

func _update_enemy_inventory_grid() -> void:
	if not current_enemy: return
	var pool = current_enemy.enemy_item_pool if "enemy_item_pool" in current_enemy else []
	if not is_instance_valid(enemy_inventory_container):
		enemy_inventory_container = find_child("EnemyItemsGrid") as GridContainer
	if not is_instance_valid(enemy_inventory_container): return
	enemy_inventory_container.columns = 2
	if enemy_item_labels.size() != pool.size() or enemy_item_labels_pool_ref != pool:
		for lbl in enemy_item_labels:
			if is_instance_valid(lbl): lbl.queue_free()
		enemy_item_labels.clear()
		for id in pool:
			var lbl = Button.new()
			lbl.name = "EnemyItemLbl_%s" % id; lbl.focus_mode = Control.FOCUS_NONE
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; lbl.disabled = true
			lbl.custom_minimum_size = Vector2(148, 70)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 13)
			var st = StyleBoxFlat.new()
			st.bg_color = Color(0.13, 0.09, 0.09, 0.96); st.set_corner_radius_all(7); st.set_border_width_all(1)
			st.border_color = Color(0.42, 0.26, 0.26)
			st.content_margin_left = 8; st.content_margin_right = 8
			st.content_margin_top  = 6; st.content_margin_bottom = 6
			lbl.add_theme_stylebox_override("normal",   st)
			lbl.add_theme_stylebox_override("disabled", st)
			enemy_inventory_container.add_child(lbl); enemy_item_labels.append(lbl)
		enemy_item_labels_pool_ref = pool.duplicate()
	for i in range(pool.size()):
		var id  = pool[i]; var lbl = enemy_item_labels[i] as Button
		if not is_instance_valid(lbl): continue
		var meta  = QuestManager.ITEM_META.get(id, {"emoji":"❓","label":id.capitalize()})
		var count = current_enemy.enemy_inventory.count(id)
		lbl.text = "%s  %s\n×%d" % [meta["emoji"], meta["label"], count]
		lbl.modulate.a = 1.0 if count > 0 else 0.28

func _build_dynamic_popup_window() -> void:
	popup_overlay = ColorRect.new(); popup_overlay.color = Color(0,0,0,0.60); popup_overlay.visible = false
	add_child(popup_overlay); popup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_panel = Panel.new(); popup_panel.custom_minimum_size = Vector2(480, 260)
	var ps = StyleBoxFlat.new(); ps.bg_color = Color(0.10, 0.11, 0.15, 0.98)
	ps.set_corner_radius_all(10); ps.set_border_width_all(2); ps.border_color = Color(0.35, 0.40, 0.60, 1.0)
	popup_panel.add_theme_stylebox_override("panel", ps); popup_overlay.add_child(popup_panel)
	popup_panel.set_anchors_preset(Control.PRESET_CENTER); popup_panel.set_offsets_preset(Control.PRESET_CENTER)
	popup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH; popup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 14)
	popup_panel.add_child(vbox); vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 22)
	popup_title_lbl = Label.new(); popup_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title_lbl.add_theme_font_size_override("font_size", 20)
	popup_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)); vbox.add_child(popup_title_lbl)
	vbox.add_child(HSeparator.new())
	popup_label = Label.new(); popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_label.add_theme_font_size_override("font_size", 15); vbox.add_child(popup_label)
	var hbox = HBoxContainer.new(); hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16); vbox.add_child(hbox)
	popup_confirm_btn = Button.new(); popup_confirm_btn.text = "✅  Confirm"
	popup_confirm_btn.focus_mode = Control.FOCUS_NONE; popup_confirm_btn.custom_minimum_size = Vector2(150, 44)
	popup_confirm_btn.add_theme_font_size_override("font_size", 14)
	popup_confirm_btn.pressed.connect(func(): _resolve_popup(true)); hbox.add_child(popup_confirm_btn)
	popup_cancel_btn = Button.new(); popup_cancel_btn.text = "❌  Cancel"
	popup_cancel_btn.focus_mode = Control.FOCUS_NONE; popup_cancel_btn.custom_minimum_size = Vector2(150, 44)
	popup_cancel_btn.add_theme_font_size_override("font_size", 14)
	popup_cancel_btn.pressed.connect(func(): _resolve_popup(false)); hbox.add_child(popup_cancel_btn)

func _input(event: InputEvent) -> void:
	if not visible: return
	if popup_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var ml = popup_panel.get_node_or_null("MagnetLayoutVBox")
			if is_instance_valid(ml):
				var dg = ml.find_child("MagnetGridContainer") as GridContainer
				match event.keycode:
					KEY_ESCAPE:
						get_viewport().set_input_as_handled(); magnet_choice_resolved.emit("")
					KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
						get_viewport().set_input_as_handled()
						var cb = ml.find_child("CommitButton") as Button
						if cb and not cb.disabled: cb.pressed.emit()
					KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
						get_viewport().set_input_as_handled()
						var idx = event.keycode - KEY_1
						if dg and idx < dg.get_child_count():
							var tb = dg.get_child(idx) as Button
							if tb and not tb.disabled: tb.pressed.emit()
				return
			match event.keycode:
				KEY_ESCAPE:
					get_viewport().set_input_as_handled()
					if popup_cancel_btn.visible: _resolve_popup(false)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if popup_confirm_btn.visible:
						get_viewport().set_input_as_handled(); _resolve_popup(true)
		elif event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if not current_enemy or not QuestManager.is_in_combat: return
	if is_waiting_on_action:
		if event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if fight_button and not fight_button.disabled:
					get_viewport().set_input_as_handled(); _on_fight_pressed()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var idx = event.keycode - KEY_1
				if idx < item_buttons.size():
					var btn = item_buttons[idx] as Button
					if is_instance_valid(btn) and not btn.disabled:
						get_viewport().set_input_as_handled()
						_on_item_used(QuestManager.equipped_items[idx])

func open_combat_screen(enemy_node: Object) -> void:
	current_enemy = enemy_node; visible = true; _is_enemy_turn = false
	is_waiting_on_action = false; popup_overlay.visible = false
	_build_item_buttons(); _refresh_ui_states()

func _parse_hp_line(hp: int, max_hp: int) -> String:
	if hp <= 0: return "💀 DEAD"
	return QuestManager.hp_to_hearts(hp, max_hp) + "\n%d / %d HP" % [hp, max_hp]

func _get_sprite(target: String) -> AnimatedSprite2D:
	if target == "player":
		var p = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(p): p = get_tree().root.find_child("mainplayer", true, false)
		if is_instance_valid(p): return p.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	elif target == "enemy":
		if is_instance_valid(current_enemy):
			return current_enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _apply_status_tints() -> void:
	if not current_enemy: return
	var p_poison = "player_poison_rounds" in current_enemy and current_enemy.player_poison_rounds > 0
	var p_regen  = "player_regen_rounds"  in current_enemy and current_enemy.player_regen_rounds  > 0
	var p_cursed = "player_cursed"        in current_enemy and current_enemy.player_cursed
	var ps = _get_sprite("player")
	if is_instance_valid(ps):
		if   p_poison: ps.modulate = Color(0.30, 0.75, 0.30, 1.0)
		elif p_regen:  ps.modulate = Color(0.55, 1.00, 0.55, 1.0)
		elif p_cursed: ps.modulate = Color(0.65, 0.30, 0.80, 1.0)
		else:          ps.modulate = Color.WHITE
	var e_poison = "enemy_poison_rounds" in current_enemy and current_enemy.enemy_poison_rounds > 0
	var e_regen  = "enemy_regen_rounds"  in current_enemy and current_enemy.enemy_regen_rounds  > 0
	var e_cursed = "enemy_cursed"        in current_enemy and current_enemy.enemy_cursed
	var es = _get_sprite("enemy")
	if is_instance_valid(es):
		if   e_poison: es.modulate = Color(0.30, 0.75, 0.30, 1.0)
		elif e_regen:  es.modulate = Color(0.55, 1.00, 0.55, 1.0)
		elif e_cursed: es.modulate = Color(0.65, 0.30, 0.80, 1.0)
		else:          es.modulate = Color.WHITE

# ─── MAIN UI REFRESH ──────────────────────────────────────────────────────────
func _refresh_ui_states() -> void:
	if not current_enemy: return
	if is_waiting_on_action: _lock_all_player_inputs(); return
	if fight_button: fight_button.disabled = false
	var is_disarmed: bool = current_enemy.player_is_disarmed if "player_is_disarmed" in current_enemy else false

	# ── Player buffs ──
	if player_buffs_lbl:
		var s = ""
		if current_enemy.player_active_armor: s += "🛡️ "
		if current_enemy.player_sharpened:    s += "🪨 "
		if "player_overcharged"   in current_enemy and current_enemy.player_overcharged:        s += "🔥 "
		if current_enemy.player_piercing:     s += "📌 "
		if is_disarmed:                       s += "❌ "
		if "player_lifesteal_active" in current_enemy and current_enemy.player_lifesteal_active: s += "🩸 "
		if "player_damage_bonus"  in current_enemy and current_enemy.player_damage_bonus > 0:   s += "+%ddmg " % current_enemy.player_damage_bonus
		if "player_regen_rounds"  in current_enemy and current_enemy.player_regen_rounds  > 0:  s += "🩹×%d " % current_enemy.player_regen_rounds
		if "player_poison_rounds" in current_enemy and current_enemy.player_poison_rounds > 0:  s += "☠️×%d " % current_enemy.player_poison_rounds
		if "player_reflect_active"   in current_enemy and current_enemy.player_reflect_active:  s += "🪞 "
		if "player_dodge_active"     in current_enemy and current_enemy.player_dodge_active:    s += "💨 "
		if "player_weakened"         in current_enemy and current_enemy.player_weakened:         s += "🗿 "
		if "player_cursed"           in current_enemy and current_enemy.player_cursed:           s += "💀 "
		if "player_items_locked"     in current_enemy and current_enemy.player_items_locked:     s += "⚡ "
		if "player_stun_extra_turns" in current_enemy and current_enemy.player_stun_extra_turns > 0: s += "⏳×%d " % current_enemy.player_stun_extra_turns
		player_buffs_lbl.text = s.strip_edges() if s.strip_edges() != "" else "● Normal"

	# ── Enemy buffs ──
	if enemy_buffs_lbl:
		var s = ""
		if current_enemy.enemy_active_armor: s += "🛡️ "
		if current_enemy.enemy_sharpened:    s += "🪨 "
		if "enemy_overcharged"   in current_enemy and current_enemy.enemy_overcharged:          s += "🔥 "
		if current_enemy.enemy_piercing:     s += "📌 "
		if current_enemy.enemy_is_disarmed:  s += "❌ "
		if "enemy_lifesteal_active" in current_enemy and current_enemy.enemy_lifesteal_active:  s += "🩸 "
		if "enemy_damage_bonus"  in current_enemy and current_enemy.enemy_damage_bonus > 0:     s += "+%ddmg " % current_enemy.enemy_damage_bonus
		if "enemy_regen_rounds"  in current_enemy and current_enemy.enemy_regen_rounds  > 0:    s += "🩹×%d " % current_enemy.enemy_regen_rounds
		if "enemy_poison_rounds" in current_enemy and current_enemy.enemy_poison_rounds > 0:    s += "☠️×%d " % current_enemy.enemy_poison_rounds
		if "enemy_reflect_active"    in current_enemy and current_enemy.enemy_reflect_active:   s += "🪞 "
		if "enemy_dodge_active"      in current_enemy and current_enemy.enemy_dodge_active:     s += "💨 "
		if "enemy_weakened"          in current_enemy and current_enemy.enemy_weakened:          s += "🗿 "
		if "enemy_cursed"            in current_enemy and current_enemy.enemy_cursed:            s += "💀 "
		if "enemy_items_locked"      in current_enemy and current_enemy.enemy_items_locked:      s += "⚡ "
		if "enemy_stun_extra_turns"  in current_enemy and current_enemy.enemy_stun_extra_turns > 0: s += "⏳×%d " % current_enemy.enemy_stun_extra_turns
		enemy_buffs_lbl.text = s.strip_edges() if s.strip_edges() != "" else "● Normal"

	if player_hp:
		player_hp.text = "⚔️  YOU\n" + _parse_hp_line(QuestManager.player_health, QuestManager.MAX_HEALTH)
	if enemy_hp:
		var emax = current_enemy.enemy_max_health if "enemy_max_health" in current_enemy else 100
		enemy_hp.text = "💀  ENEMY  LV.%d\n" % current_enemy.enemy_level + _parse_hp_line(current_enemy.enemy_health, emax)

	if drop_countdown_label:
		var next_count = min(current_enemy.drop_round_index + 1, 6)
		if current_enemy.cycles_until_drop <= 1:
			drop_countdown_label.text = "📦  Drop next round!  (+%d items)" % next_count
		else:
			drop_countdown_label.text = "📦  Drop in %d rounds  (+%d items)" % [current_enemy.cycles_until_drop, next_count]

	var slots = QuestManager.equipped_items
	for i in range(item_buttons.size()):
		var btn = item_buttons[i] as Button
		if not is_instance_valid(btn): continue
		var item_id = slots[i] if i < slots.size() else ""
		if item_id == "": btn.visible = false; continue
		btn.visible = true
		var meta     = QuestManager.ITEM_META.get(item_id, {"emoji":"❓","label":item_id.capitalize(),"desc":""})
		var count    = current_enemy.player_inventory.count(item_id)
		var slot_key = SLOT_KEYS[i] if i < SLOT_KEYS.size() else ""
		btn.text         = "%s  %s\n[%s]  ×%d" % [meta["emoji"], meta["label"], slot_key, count]
		btn.tooltip_text = "%s %s\n%s" % [meta["emoji"], meta["label"], meta["desc"]]
		var usable = count > 0 and not is_disarmed
		if "player_items_locked" in current_enemy and current_enemy.player_items_locked: usable = false
		if item_id == "potion"       and QuestManager.player_health >= QuestManager.MAX_HEALTH: usable = false
		if item_id == "shield"       and current_enemy.player_active_armor:   usable = false
		if item_id == "whip"         and current_enemy.enemy_is_disarmed:     usable = false
		if item_id == "needle"       and current_enemy.player_piercing:       usable = false
		if item_id == "bandage"      and current_enemy.player_regen_rounds  > 0: usable = false
		if item_id == "poison_dart"  and current_enemy.enemy_poison_rounds  > 0: usable = false
		if item_id == "battle_horn"  and "player_lifesteal_active" in current_enemy and current_enemy.player_lifesteal_active: usable = false
		if item_id == "mirror_ward"  and current_enemy.player_reflect_active: usable = false
		if item_id == "smoke_bomb"   and current_enemy.player_dodge_active:   usable = false
		if item_id == "weaken_totem" and current_enemy.enemy_cursed:          usable = false
		if item_id == "static_field" and current_enemy.enemy_items_locked:    usable = false
		btn.disabled   = not usable
		btn.modulate.a = 1.0 if usable else 0.36

	_update_enemy_inventory_grid()
	_apply_status_tints()

func _lock_all_player_inputs() -> void:
	if fight_button: fight_button.disabled = true
	for btn in item_buttons:
		if is_instance_valid(btn): btn.disabled = true

func _on_fight_pressed() -> void:
	if not visible or not QuestManager.is_in_combat: return
	if not is_instance_valid(current_enemy): return
	if is_waiting_on_action: return
	is_waiting_on_action = true; _lock_all_player_inputs()
	var confirmed = await show_blocking_popup("⚔️  ATTACK", "Commit to your attack phase?", true)
	if not confirmed:
		is_waiting_on_action = false; _refresh_ui_states(); return
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): player = get_tree().root.find_child("mainplayer", true, false)
	if is_instance_valid(player) and player.has_method("do_attack_lunge"):
		var enemy_pos   = current_enemy.global_position if is_instance_valid(current_enemy) else player.global_position
		var is_dis      = current_enemy.player_is_disarmed if "player_is_disarmed" in current_enemy else false
		await player.do_attack_lunge(enemy_pos, current_enemy, is_dis)
	if current_enemy.has_method("process_player_attack_phase"):
		await current_enemy.process_player_attack_phase()
	if not _is_enemy_turn:
		is_waiting_on_action = false; _refresh_ui_states()

func _on_item_used(item_type: String) -> void:
	if is_waiting_on_action or not current_enemy: return
	if not item_type in current_enemy.player_inventory: return
	is_waiting_on_action = true; _lock_all_player_inputs()
	if item_type == "magnet":
		if current_enemy.has_method("use_player_item"): await current_enemy.use_player_item("magnet")
		if not _is_enemy_turn: is_waiting_on_action = false; _refresh_ui_states()
		return
	var meta      = QuestManager.ITEM_META.get(item_type, {"emoji":"❓","label":item_type.capitalize(),"desc":""})
	var confirmed = await show_blocking_popup("%s  USE ITEM" % meta["emoji"],
		"Activate  [%s]?\n\n%s" % [meta["label"].to_upper(), meta["desc"]], true)
	if confirmed:
		if current_enemy.has_method("use_player_item"): await current_enemy.use_player_item(item_type)
		if not _is_enemy_turn: is_waiting_on_action = false; _refresh_ui_states()
	else:
		is_waiting_on_action = false; _refresh_ui_states()

func show_blocking_popup(header_title: String, message: String, require_confirmation: bool = false) -> bool:
	popup_title_lbl.text = header_title; popup_label.text = message; popup_overlay.visible = true
	for child in popup_panel.get_children():
		if child.name == "MagnetLayoutVBox": child.queue_free()
	popup_panel.get_child(0).visible = true
	if require_confirmation:
		popup_confirm_btn.text = "✅  Confirm  (Enter)"; popup_cancel_btn.text = "❌  Cancel  (Esc)"; popup_cancel_btn.visible = true
	else:
		popup_confirm_btn.text = "▶  Continue  (Enter)"; popup_cancel_btn.visible = false
	var user_choice = await popup_resolved; popup_overlay.visible = false; return user_choice

func show_magnet_choice_popup(stealable_pool: Array) -> String:
	popup_overlay.visible = true; magnet_currently_selected_item = ""
	var default_vbox = popup_panel.get_child(0); default_vbox.visible = false
	var mv = VBoxContainer.new(); mv.name = "MagnetLayoutVBox"
	mv.add_theme_constant_override("separation", 12)
	mv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	popup_panel.add_child(mv)
	var tl = Label.new(); tl.text = "🧲  MAGNET — Choose item to steal"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 18); tl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	mv.add_child(tl)
	var dl = Label.new(); dl.text = "Press [1–5] or click, then Commit"; dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; mv.add_child(dl)
	var dg = GridContainer.new(); dg.name = "MagnetGridContainer"; dg.columns = 3
	dg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dg.add_theme_constant_override("h_separation", 10); dg.add_theme_constant_override("v_separation", 10); mv.add_child(dg)
	var unique_items: Array = []
	for item in stealable_pool:
		if not item in unique_items: unique_items.append(item)
	var commit_btn := Button.new(); commit_btn.name = "CommitButton"; commit_btn.text = "✅  Commit  (Enter)"
	commit_btn.focus_mode = Control.FOCUS_NONE; commit_btn.custom_minimum_size = Vector2(0, 44)
	commit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL; commit_btn.disabled = true
	var choice_btns: Array = []
	for i in range(unique_items.size()):
		var item = unique_items[i]
		var meta = QuestManager.ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var btn  = Button.new(); btn.text = "[%d]  %s  %s" % [i + 1, meta["emoji"], meta["label"]]
		btn.focus_mode = Control.FOCUS_NONE; btn.custom_minimum_size = Vector2(130, 44); dg.add_child(btn)
		choice_btns.append(btn)
		btn.pressed.connect(func():
			magnet_currently_selected_item = item
			for b in choice_btns: b.remove_theme_color_override("font_color")
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4)); commit_btn.disabled = false)
	if unique_items.is_empty():
		var el = Label.new(); el.text = "Nothing stealable — your loadout\ndoesn't overlap this enemy's items."
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dg.add_child(el)
	var ah = HBoxContainer.new(); ah.add_theme_constant_override("separation", 12); mv.add_child(ah); ah.add_child(commit_btn)
	var cancel_btn = Button.new(); cancel_btn.text = "❌  Cancel  (Esc)"; cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size = Vector2(0, 44); cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): magnet_choice_resolved.emit("")); ah.add_child(cancel_btn)
	commit_btn.pressed.connect(func():
		if magnet_currently_selected_item != "" and popup_overlay.visible:
			commit_btn.disabled = true; magnet_choice_resolved.emit(magnet_currently_selected_item))
	var chosen = await magnet_choice_resolved; mv.queue_free(); popup_overlay.visible = false; return chosen

func _resolve_popup(confirmed: bool) -> void:
	popup_resolved.emit(confirmed)
