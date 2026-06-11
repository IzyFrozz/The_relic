extends CanvasLayer

# Loose dynamic typing to prevent asynchronous cross-frame type assertion crashes
var current_enemy = null 
var is_waiting_on_action: bool = false 

var turn_title_label: Label
var drop_countdown_label: Label
var fight_button: Button

var player_hp: Label
var player_buffs_lbl: Label
var enemy_hp: Label
var enemy_buffs_lbl: Label

# Scene-linked Unified History Trackers
var history_label: Label
var history_scroll: ScrollContainer
var combined_history_text: String = ""

var heal_btn: Button
var defend_btn: Button
var sharpen_btn: Button
var disarm_btn: Button
var pierce_btn: Button
var magnet_btn: Button

var enemy_inventory_container: GridContainer
var enemy_potion_lbl: Label
var enemy_shield_lbl: Label
var enemy_grindstone_lbl: Label
var enemy_whip_lbl: Label
var enemy_needle_lbl: Label
var enemy_magnet_lbl: Label

# Modal popup layout components
var popup_overlay: ColorRect
var popup_panel: Panel
var popup_title_lbl: Label
var popup_label: Label
var popup_confirm_btn: Button
var popup_cancel_btn: Button

# Tracker for mid-selection inside the Magnet custom grid flow
var magnet_currently_selected_item: String = ""

# Direct structural signals to bridge confirmation loops smoothly
signal popup_resolved(confirmed: bool)
signal magnet_choice_resolved(chosen_item_id: String)

func _ready() -> void:
	visible = false
	_find_nodes_automatically()
	_connect_button_signals()
	_setup_floating_tooltips()
	_build_dynamic_popup_window()
	_disable_engine_focus_modes()

func _find_nodes_automatically() -> void:
	turn_title_label = find_child("TurnTitleLabel") as Label
	drop_countdown_label = find_child("DropCountdownLabel") as Label
	fight_button = find_child("fight_button") as Button
	
	player_hp = find_child("PlayerHPLabel") as Label
	player_buffs_lbl = find_child("PlayerBuffsLabel") as Label
	enemy_hp = find_child("EnemyHPLabel") as Label
	enemy_buffs_lbl = find_child("EnemyBuffsLabel") as Label
	
	history_label = find_child("HistoryLabel") as Label
	
	if is_instance_valid(history_label):
		var parent_node = history_label.get_parent()
		while parent_node and not parent_node is ScrollContainer:
			parent_node = parent_node.get_parent()
		if parent_node is ScrollContainer:
			history_scroll = parent_node as ScrollContainer
	
	heal_btn = find_child("HealButton") as Button
	defend_btn = find_child("DefendButton") as Button
	sharpen_btn = find_child("SharpenButton") as Button
	disarm_btn = find_child("DisarmButton") as Button
	pierce_btn = find_child("PierceButton") as Button
	magnet_btn = find_child("MagnetButton") as Button 
	
	enemy_inventory_container = find_child("EnemyInventoryGrid") as GridContainer
	enemy_potion_lbl = find_child("EnemyPotionLabel") as Label
	enemy_shield_lbl = find_child("EnemyShieldLabel") as Label
	enemy_grindstone_lbl = find_child("EnemyGrindstoneLabel") as Label
	enemy_whip_lbl = find_child("EnemyWhipLabel") as Label
	enemy_needle_lbl = find_child("EnemyNeedleLabel") as Label
	enemy_magnet_lbl = find_child("EnemyMagnetLabel") as Label 

func _disable_engine_focus_modes() -> void:
	var items = [fight_button, heal_btn, defend_btn, sharpen_btn, disarm_btn, pierce_btn, magnet_btn, popup_confirm_btn, popup_cancel_btn]
	for btn in items:
		if is_instance_valid(btn): btn.focus_mode = Control.FOCUS_NONE

func _connect_button_signals() -> void:
	var clean_connect = func(btn: Button, item_type: String):
		if btn:
			for connection in btn.pressed.get_connections():
				btn.pressed.disconnect(connection.callable)
			btn.pressed.connect(func(): _on_item_used(item_type))
			
	if fight_button:
		for connection in fight_button.pressed.get_connections():
			fight_button.pressed.disconnect(connection.callable)
		fight_button.pressed.connect(_on_fight_pressed)
		
	clean_connect.call(heal_btn, "potion")
	clean_connect.call(defend_btn, "shield")
	clean_connect.call(sharpen_btn, "grindstone")
	clean_connect.call(disarm_btn, "whip")
	clean_connect.call(pierce_btn, "needle")
	clean_connect.call(magnet_btn, "magnet") 

func _setup_floating_tooltips() -> void:
	if heal_btn: heal_btn.tooltip_text = "🧪 POTION\nRestores 20 HP."
	if defend_btn: defend_btn.tooltip_text = "🛡️ SHIELD\nBlocks the next incoming hit."
	if sharpen_btn: sharpen_btn.tooltip_text = "🪨 GRINDSTONE\nNext attack deals 2x DAMAGE."
	if disarm_btn: disarm_btn.tooltip_text = "💥 WHIP\nForces enemy to skip their turn."
	if pierce_btn: pierce_btn.tooltip_text = "🪡 NEEDLE\nNext strike bypasses active shields."
	if magnet_btn: magnet_btn.tooltip_text = "🧲 MAGNET\nSteal a chosen item directly from the enemy."

func _build_dynamic_popup_window() -> void:
	popup_overlay = ColorRect.new()
	popup_overlay.color = Color(0, 0, 0, 0.45)
	popup_overlay.visible = false
	add_child(popup_overlay)
	popup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	popup_panel = Panel.new()
	popup_panel.custom_minimum_size = Vector2(500, 300)
	
	var custom_style = StyleBoxFlat.new()
	custom_style.bg_color = Color(0.15, 0.15, 0.17, 0.98)
	custom_style.set_corner_radius_all(8)
	custom_style.set_border_width_all(2)
	custom_style.border_color = Color(0.45, 0.45, 0.5, 1.0)
	popup_panel.add_theme_stylebox_override("panel", custom_style)
	
	popup_overlay.add_child(popup_panel) 
	popup_panel.set_anchors_preset(Control.PRESET_CENTER)
	popup_panel.set_offsets_preset(Control.PRESET_CENTER)
	popup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var vbox = VBoxContainer.new()
	popup_panel.add_child(vbox) 
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	
	popup_title_lbl = Label.new()
	popup_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(popup_title_lbl)
	
	popup_label = Label.new()
	popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(popup_label)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	popup_confirm_btn = Button.new()
	popup_confirm_btn.text = "Confirm"
	popup_confirm_btn.focus_mode = Control.FOCUS_NONE
	popup_confirm_btn.custom_minimum_size = Vector2(140, 40)
	popup_confirm_btn.pressed.connect(func(): _resolve_popup(true))
	hbox.add_child(popup_confirm_btn)
	
	popup_cancel_btn = Button.new()
	popup_cancel_btn.text = "Cancel"
	popup_cancel_btn.focus_mode = Control.FOCUS_NONE
	popup_cancel_btn.custom_minimum_size = Vector2(140, 40)
	popup_cancel_btn.pressed.connect(func(): _resolve_popup(false))
	hbox.add_child(popup_cancel_btn)

func _input(event: InputEvent) -> void:
	if not visible: return
	
	if popup_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var magnet_layout = popup_panel.get_node_or_null("MagnetLayoutVBox")
			if is_instance_valid(magnet_layout):
				var dynamic_grid = magnet_layout.find_child("MagnetGridContainer") as GridContainer
				match event.keycode:
					KEY_ESCAPE:
						get_viewport().set_input_as_handled()
						magnet_choice_resolved.emit("")
					KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
						get_viewport().set_input_as_handled()
						var commit_btn = magnet_layout.find_child("CommitButton") as Button 
						if commit_btn and not commit_btn.disabled:
							commit_btn.pressed.emit()
					KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
						get_viewport().set_input_as_handled()
						var idx = event.keycode - KEY_1 
						if dynamic_grid and idx < dynamic_grid.get_child_count():
							var target_btn = dynamic_grid.get_child(idx) as Button
							if target_btn and not target_btn.disabled:
								target_btn.pressed.emit()
				return

			match event.keycode:
				KEY_ESCAPE:
					get_viewport().set_input_as_handled()
					if popup_cancel_btn.visible: _resolve_popup(false)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if popup_confirm_btn.visible:
						get_viewport().set_input_as_handled()
						_resolve_popup(true)
		elif event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
		
	if is_waiting_on_action:
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if not fight_button.disabled:
					get_viewport().set_input_as_handled()
					_on_fight_pressed()
			KEY_1: _trigger_shortcut_action("potion", heal_btn)
			KEY_2: _trigger_shortcut_action("shield", defend_btn)
			KEY_3: _trigger_shortcut_action("grindstone", sharpen_btn)
			KEY_4: _trigger_shortcut_action("whip", disarm_btn)
			KEY_5: _trigger_shortcut_action("needle", pierce_btn)
			KEY_6: _trigger_shortcut_action("magnet", magnet_btn)

func _trigger_shortcut_action(item_id: String, target_btn: Button) -> void:
	if is_instance_valid(target_btn) and not target_btn.disabled and target_btn.visible:
		get_viewport().set_input_as_handled()
		_on_item_used(item_id)

func show_blocking_popup(header_title: String, message: String, require_confirmation: bool = false) -> bool:
	popup_title_lbl.text = header_title.to_upper()
	popup_label.text = message
	popup_overlay.visible = true
	
	for child in popup_panel.get_children():
		if child != popup_panel.get_child(0):
			child.queue_free()
	popup_panel.get_child(0).visible = true
	
	if require_confirmation:
		popup_confirm_btn.text = "👍 Confirm (Enter/Space)"
		popup_cancel_btn.text = "❌ Cancel (Esc)"
		popup_cancel_btn.visible = true
	else:
		popup_confirm_btn.text = "👉 Continue (Enter/Space)"
		popup_cancel_btn.visible = false
		
	var user_choice = await popup_resolved
	popup_overlay.visible = false
	return user_choice

func show_magnet_choice_popup(enemy_inventory: Array) -> String:
	popup_title_lbl.text = "🧲 MAGNET EXTRACTION"
	popup_label.text = "Select an item slot using [1-5] or Click, then press Commit to swipe it:"
	popup_overlay.visible = true
	
	magnet_currently_selected_item = ""
	var default_vbox = popup_panel.get_child(0)
	default_vbox.visible = false
	
	var magnet_vbox = VBoxContainer.new()
	magnet_vbox.name = "MagnetLayoutVBox"
	magnet_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	popup_panel.add_child(magnet_vbox)
	
	var title_clone = Label.new()
	title_clone.text = popup_title_lbl.text
	title_clone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	magnet_vbox.add_child(title_clone)
	
	var desc_clone = Label.new()
	desc_clone.text = popup_label.text
	desc_clone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_clone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	magnet_vbox.add_child(desc_clone)
	
	var dynamic_grid = GridContainer.new()
	dynamic_grid.name = "MagnetGridContainer"
	dynamic_grid.columns = 3
	dynamic_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_grid.add_theme_constant_override("h_separation", 12)
	dynamic_grid.add_theme_constant_override("v_separation", 12)
	magnet_vbox.add_child(dynamic_grid)
	
	var unique_items: Array = []
	for item in enemy_inventory:
		if item != "magnet" and not item in unique_items: 
			unique_items.append(item)
			
	var item_buttons: Array = []
	var action_hbox = HBoxContainer.new()
	action_hbox.name = "ActionHBox"
	action_hbox.add_theme_constant_override("separation", 16)
	magnet_vbox.add_child(action_hbox)
	
	var wide_commit_btn = Button.new()
	wide_commit_btn.name = "CommitButton"
	wide_commit_btn.text = "👍 Commit Extraction (Enter)"
	wide_commit_btn.focus_mode = Control.FOCUS_NONE
	wide_commit_btn.custom_minimum_size = Vector2(0, 44)
	wide_commit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wide_commit_btn.disabled = true 
	action_hbox.add_child(wide_commit_btn)
	
	for i in range(unique_items.size()):
		var item = unique_items[i]
		var btn = Button.new()
		btn.text = "[%d] %s" % [(i + 1), item.to_upper()]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 42)
		dynamic_grid.add_child(btn)
		item_buttons.append(btn)
		
		btn.pressed.connect(func():
			magnet_currently_selected_item = item
			wide_commit_btn.disabled = false 
			for b in item_buttons:
				b.remove_theme_color_override("font_color")
			btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2)) 
		)
		
	if unique_items.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "( Enemy possesses no extractable items )"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dynamic_grid.add_child(empty_lbl)
		
	var wide_cancel_btn = Button.new()
	wide_cancel_btn.text = "❌ Cancel (Esc)"
	wide_cancel_btn.focus_mode = Control.FOCUS_NONE
	wide_cancel_btn.custom_minimum_size = Vector2(0, 44)
	wide_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wide_cancel_btn.pressed.connect(func(): magnet_choice_resolved.emit(""))
	action_hbox.add_child(wide_cancel_btn)
	
	wide_commit_btn.pressed.connect(func():
		if magnet_currently_selected_item != "" and popup_overlay.visible:
			wide_commit_btn.disabled = true
			magnet_choice_resolved.emit(magnet_currently_selected_item)
	)
	
	var chosen_item = await magnet_choice_resolved
	magnet_vbox.queue_free()
	popup_overlay.visible = false
	return chosen_item

func _resolve_popup(confirmed: bool) -> void:
	popup_resolved.emit(confirmed)

func open_combat_screen(enemy_node: Object) -> void:
	current_enemy = enemy_node
	visible = true
	is_waiting_on_action = false
	popup_overlay.visible = false
	combined_history_text = ""
	_update_history_displays()
	_refresh_ui_states()

func start_player_turn() -> void:
	is_waiting_on_action = false
	if turn_title_label:
		turn_title_label.text = "👉 YOUR TURN — Use items [1-6] or Attack [Space/Enter]!"
	_refresh_ui_states()

func start_enemy_turn_visuals() -> void:
	if turn_title_label:
		turn_title_label.text = "💀 ENEMY TURN — Thinking of Combos..."
	_lock_all_player_inputs()

func display_round_history(summary_text: String, target_player_log: bool = true) -> void:
	var label_tag = "[PLAYER ACTION]: " if target_player_log else "[ENEMY ACTION]: "
	combined_history_text += label_tag + summary_text + "\n"
	_update_history_displays()
	_auto_scroll_to_latest_log()

func _update_history_displays() -> void:
	if is_instance_valid(history_label):
		if combined_history_text.strip_edges() == "":
			history_label.text = ""
		else:
			history_label.text = combined_history_text.strip_edges()

func _auto_scroll_to_latest_log() -> void:
	if is_instance_valid(history_scroll):
		await get_tree().process_frame
		var v_scrollbar = history_scroll.get_v_scroll_bar()
		if v_scrollbar:
			v_scrollbar.value = v_scrollbar.max_value

func _parse_hp_to_hearts(hp: int, max_hp: int) -> String:
	if hp <= 0: return "💀 DEAD"
	
	var full_heart = "❤️"
	var broken_heart = "💔"
	var empty_heart = "🖤"
	var heart_string = ""
	var hp_per_heart = 20
	
	var total_slots = int(ceil(float(max_hp) / float(hp_per_heart)))
	if total_slots <= 0: total_slots = 1
	
	var full_count = int(hp / hp_per_heart)
	var remainder = hp % hp_per_heart
	
	if full_count > total_slots:
		full_count = total_slots
		remainder = 0
		
	for i in range(full_count):
		heart_string += full_heart
		
	var slots_used = full_count
	if remainder > 0 and slots_used < total_slots:
		heart_string += broken_heart
		slots_used += 1
		
	while slots_used < total_slots:
		heart_string += empty_heart
		slots_used += 1
		
	return heart_string + " (%d HP / %d HP)" % [hp, max_hp]

func _refresh_ui_states() -> void:
	if not current_enemy: return
	if is_waiting_on_action:
		_lock_all_player_inputs()
		return

	if fight_button:
		fight_button.disabled = false

	var is_disarmed: bool = current_enemy.player_is_disarmed if "player_is_disarmed" in current_enemy else false

	if player_buffs_lbl:
		var p_status = ""
		if current_enemy.player_active_armor: p_status += "🛡️[ARMOR] "
		if current_enemy.player_sharpened: p_status += "🪨[SHARPENED] "
		if current_enemy.player_piercing: p_status += "📌[PIERCING] "
		if is_disarmed: p_status += "❌[DISARMED] "
		player_buffs_lbl.text = "Status: " + (p_status if p_status != "" else "NORMAL")
	
	if enemy_buffs_lbl:
		var e_status = ""
		if current_enemy.enemy_active_armor: e_status += "🛡️[ARMOR] "
		if current_enemy.enemy_sharpened: e_status += "🪨[SHARPENED] "
		if current_enemy.enemy_piercing: e_status += "📌[PIERCING] "
		if current_enemy.enemy_is_disarmed: e_status += "❌[DISARMED] "
		enemy_buffs_lbl.text = "Status: " + (e_status if e_status != "" else "NORMAL")
	
	if player_hp:
		player_hp.text = "🟢 YOU: " + _parse_hp_to_hearts(QuestManager.player_health, QuestManager.MAX_HEALTH)
	
	if enemy_hp:
		var enemy_max = current_enemy.enemy_max_health if "enemy_max_health" in current_enemy else 100
		enemy_hp.text = "🔴 ENEMY (LV.%d): " % current_enemy.enemy_level + _parse_hp_to_hearts(current_enemy.enemy_health, enemy_max)
		
	if drop_countdown_label:
		if current_enemy.cycles_until_drop <= 1:
			drop_countdown_label.text = "📦 NEXT SUPPLY DROP: Approaching next round!"
		else:
			drop_countdown_label.text = "📦 ITEM DROP IN: %d rounds (x%d items)" % [current_enemy.cycles_until_drop, current_enemy.current_items_per_deal]
			
	var update_btn = func(btn: Button, item_id: String, prefix: String, backpack_limit: bool, tier_unlocked: bool):
		if btn:
			var count = current_enemy.player_inventory.count(item_id)
			btn.text = "%s (x%d)" % [prefix, count]
			if not tier_unlocked:
				btn.disabled = true
				btn.modulate.a = 0.0
			else:
				btn.disabled = (count <= 0) or backpack_limit or is_disarmed
				btn.modulate.a = 0.4 if (is_disarmed or count <= 0) else 1.0
			btn.focus_mode = Control.FOCUS_NONE

	var tier: int = current_enemy.enemy_level if "enemy_level" in current_enemy else 1
	update_btn.call(heal_btn, "potion", "🧪 Potion [1]", QuestManager.player_health >= QuestManager.MAX_HEALTH, true)
	update_btn.call(defend_btn, "shield", "🛡️ Shield [2]", current_enemy.player_active_armor, true)
	update_btn.call(sharpen_btn, "grindstone", "🪨 Grindstone [3]", current_enemy.player_sharpened, true)
	update_btn.call(disarm_btn, "whip", "💥 Whip [4]", current_enemy.enemy_is_disarmed, tier >= 2)
	update_btn.call(pierce_btn, "needle", "📌 Needle [5]", current_enemy.player_piercing, tier >= 3)
	update_btn.call(magnet_btn, "magnet", "🧲 Magnet [6]", false, tier >= 4) 
	
	if enemy_whip_lbl: enemy_whip_lbl.visible = (tier >= 2)
	if enemy_needle_lbl: enemy_needle_lbl.visible = (tier >= 3)
	if enemy_magnet_lbl: enemy_magnet_lbl.visible = (tier >= 4)
	
	_update_enemy_inventory_grid()

func _update_enemy_inventory_grid() -> void:
	if not current_enemy: return
	var dict_labels = {
		"potion": enemy_potion_lbl, "shield": enemy_shield_lbl, "grindstone": enemy_grindstone_lbl,
		"whip": enemy_whip_lbl, "needle": enemy_needle_lbl, "magnet": enemy_magnet_lbl
	}
	var prefixes = {
		"potion": "🧪 Potion", "shield": "🛡️ Shield", "grindstone": "🪨 Grindstone",
		"whip": "💥 Whip", "needle": "🪡 Needle", "magnet": "🧲 Magnet"
	}
	
	for id in dict_labels:
		var lbl = dict_labels[id]
		if not is_instance_valid(lbl): continue
		var count = current_enemy.enemy_inventory.count(id)
		lbl.text = "%s (x%d)" % [prefixes[id], count]
		lbl.modulate.a = 1.0 if count > 0 else 0.4

func _lock_all_player_inputs() -> void:
	var buttons = [fight_button, heal_btn, defend_btn, sharpen_btn, disarm_btn, pierce_btn, magnet_btn]
	for btn in buttons:
		if btn: btn.disabled = true

func _on_fight_pressed() -> void:
	if is_waiting_on_action or not current_enemy: return
	is_waiting_on_action = true
	_lock_all_player_inputs()
	
	var confirmed = await show_blocking_popup("⚔️ ATTACK", "Commit to your attack phase?", true)
	if not confirmed:
		is_waiting_on_action = false
		_refresh_ui_states()
		return
		
	if current_enemy.has_method("process_player_attack_phase"):
		await current_enemy.process_player_attack_phase()
		
	if turn_title_label and not "ENEMY TURN" in turn_title_label.text:
		is_waiting_on_action = false
		_refresh_ui_states()

func _on_item_used(item_type: String) -> void:
	if is_waiting_on_action or not current_enemy: return
	if not item_type in current_enemy.player_inventory: return
	is_waiting_on_action = true
	_lock_all_player_inputs()
	
	if item_type == "magnet":
		if current_enemy.has_method("use_player_item"):
			await current_enemy.use_player_item("magnet")
		
		if turn_title_label and not "ENEMY TURN" in turn_title_label.text:
			is_waiting_on_action = false
			_refresh_ui_states()
		return

	var confirmed = await show_blocking_popup("🧪 ITEM DEPLOY", "Activate [%s]?" % item_type.to_upper(), true)
	if confirmed:
		if current_enemy.has_method("use_player_item"):
			await current_enemy.use_player_item(item_type)
		
		if turn_title_label and not "ENEMY TURN" in turn_title_label.text:
			is_waiting_on_action = false
			_refresh_ui_states()
	else:
		is_waiting_on_action = false
		_refresh_ui_states()

func apply_victory_max_hp_boost() -> void:
	QuestManager.MAX_HEALTH += 20
	QuestManager.player_health = QuestManager.MAX_HEALTH 
	_refresh_ui_states()
