extends CanvasLayer

var current_enemy = null
var is_waiting_on_action: bool = false

var turn_title_label: Label
var drop_countdown_label: Label
var fight_button: Button

var player_hp: Label
var player_buffs_lbl: Label
var enemy_hp: Label
var enemy_buffs_lbl: Label

var history_label: Label
var history_scroll: ScrollContainer
var combined_history_text: String = ""

# Player item buttons — now an ordered array matching equipped_items slots
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

# ─── ITEM META ────────────────────────────────────────────────────────────────
# Centralized in QuestManager.ITEM_META — see that file for the single source
# of truth on every item's emoji/label/description.

const SLOT_KEYS := ["1","2","3","4","5","6"]

# ─── READY ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	visible = false
	_find_nodes_automatically()
	_connect_fight_button()
	_build_dynamic_popup_window()
	_disable_engine_focus_modes()

func _find_nodes_automatically() -> void:
	turn_title_label      = find_child("TurnTitleLabel") as Label
	drop_countdown_label  = find_child("DropCountdownLabel") as Label
	fight_button          = find_child("fight_button") as Button

	player_hp             = find_child("PlayerHPLabel") as Label
	player_buffs_lbl      = find_child("PlayerBuffsLabel") as Label
	enemy_hp              = find_child("EnemyHPLabel") as Label
	enemy_buffs_lbl       = find_child("EnemyBuffsLabel") as Label

	history_label         = find_child("HistoryLabel") as Label
	if is_instance_valid(history_label):
		var p = history_label.get_parent()
		while p and not p is ScrollContainer:
			p = p.get_parent()
		if p is ScrollContainer:
			history_scroll = p as ScrollContainer

	enemy_inventory_container = find_child("EnemyItemsGrid") as GridContainer

func _connect_fight_button() -> void:
	if fight_button:
		for c in fight_button.pressed.get_connections():
			fight_button.pressed.disconnect(c.callable)
		fight_button.pressed.connect(_on_fight_pressed)

func _disable_engine_focus_modes() -> void:
	var items = [fight_button, popup_confirm_btn, popup_cancel_btn]
	for btn in items:
		if is_instance_valid(btn): btn.focus_mode = Control.FOCUS_NONE

# ─── DYNAMIC ITEM BUTTONS ─────────────────────────────────────────────────────
# Called each time combat opens — rebuilds slot buttons to match equipped_items order
func _build_item_buttons() -> void:
	# Remove old buttons
	for btn in item_buttons:
		if is_instance_valid(btn): btn.queue_free()
	item_buttons.clear()

	# Find the container (a GridContainer or HBoxContainer named "PlayerItemsGrid")
	var grid = find_child("PlayerItemsGrid") as Control
	if not is_instance_valid(grid): return

	var slots = QuestManager.equipped_items
	for i in range(slots.size()):
		var item_id = slots[i]
		var meta = QuestManager.ITEM_META.get(item_id, {"emoji":"❓","label":item_id.capitalize(),"desc":""})

		var btn = Button.new()
		btn.name = "ItemBtn_%d" % i
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(110, 60)
		btn.tooltip_text = "%s %s\n%s\n[%s]" % [meta["emoji"], meta["label"], meta["desc"], SLOT_KEYS[i] if i < SLOT_KEYS.size() else ""]

		# Style
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.14, 0.18, 0.95)
		style.set_corner_radius_all(6)
		style.set_border_width_all(1)
		style.border_color = Color(0.4, 0.4, 0.55)
		btn.add_theme_stylebox_override("normal", style)

		var hover_style = style.duplicate()
		hover_style.border_color = Color(0.7, 0.7, 1.0)
		hover_style.bg_color = Color(0.18, 0.20, 0.28, 0.95)
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.add_theme_font_size_override("font_size", 13)

		var captured_id = item_id
		btn.pressed.connect(func(): _on_item_used(captured_id))
		grid.add_child(btn)
		item_buttons.append(btn)

# ─── POPUP ────────────────────────────────────────────────────────────────────
func _build_dynamic_popup_window() -> void:
	popup_overlay = ColorRect.new()
	popup_overlay.color = Color(0, 0, 0, 0.6)
	popup_overlay.visible = false
	add_child(popup_overlay)
	popup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	popup_panel = Panel.new()
	popup_panel.custom_minimum_size = Vector2(480, 260)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15, 0.98)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.40, 0.60, 1.0)
	popup_panel.add_theme_stylebox_override("panel", style)

	popup_overlay.add_child(popup_panel)
	popup_panel.set_anchors_preset(Control.PRESET_CENTER)
	popup_panel.set_offsets_preset(Control.PRESET_CENTER)
	popup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	popup_panel.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 22)

	popup_title_lbl = Label.new()
	popup_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title_lbl.add_theme_font_size_override("font_size", 20)
	popup_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(popup_title_lbl)

	var divider = HSeparator.new()
	vbox.add_child(divider)

	popup_label = Label.new()
	popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(popup_label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	popup_confirm_btn = Button.new()
	popup_confirm_btn.text = "✅  Confirm"
	popup_confirm_btn.focus_mode = Control.FOCUS_NONE
	popup_confirm_btn.custom_minimum_size = Vector2(150, 44)
	popup_confirm_btn.add_theme_font_size_override("font_size", 14)
	popup_confirm_btn.pressed.connect(func(): _resolve_popup(true))
	hbox.add_child(popup_confirm_btn)

	popup_cancel_btn = Button.new()
	popup_cancel_btn.text = "❌  Cancel"
	popup_cancel_btn.focus_mode = Control.FOCUS_NONE
	popup_cancel_btn.custom_minimum_size = Vector2(150, 44)
	popup_cancel_btn.add_theme_font_size_override("font_size", 14)
	popup_cancel_btn.pressed.connect(func(): _resolve_popup(false))
	hbox.add_child(popup_cancel_btn)

# ─── INPUT ────────────────────────────────────────────────────────────────────
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
						if commit_btn and not commit_btn.disabled: commit_btn.pressed.emit()
					KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
						get_viewport().set_input_as_handled()
						var idx = event.keycode - KEY_1
						if dynamic_grid and idx < dynamic_grid.get_child_count():
							var target_btn = dynamic_grid.get_child(idx) as Button
							if target_btn and not target_btn.disabled: target_btn.pressed.emit()
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

	# Only process combat keybinds when actively in combat with a valid enemy
	if not current_enemy or not QuestManager.is_in_combat:
		return

	if is_waiting_on_action:
		if event is InputEventKey: get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if fight_button and not fight_button.disabled:
					get_viewport().set_input_as_handled()
					_on_fight_pressed()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var idx = event.keycode - KEY_1
				if idx < item_buttons.size():
					var btn = item_buttons[idx] as Button
					if is_instance_valid(btn) and not btn.disabled:
						get_viewport().set_input_as_handled()
						_on_item_used(QuestManager.equipped_items[idx])

# ─── COMBAT OPEN ──────────────────────────────────────────────────────────────
func open_combat_screen(enemy_node: Object) -> void:
	current_enemy = enemy_node
	visible = true
	is_waiting_on_action = false
	popup_overlay.visible = false
	combined_history_text = ""
	_update_history_displays()
	_build_item_buttons()
	_refresh_ui_states()

func start_player_turn() -> void:
	is_waiting_on_action = false
	if turn_title_label:
		turn_title_label.text = "👉  YOUR TURN  —  Use items or press Attack!"
	_refresh_ui_states()

func start_enemy_turn_visuals() -> void:
	if turn_title_label:
		turn_title_label.text = "💀  ENEMY TURN  —  Thinking..."
	_lock_all_player_inputs()

# ─── HISTORY LOG ──────────────────────────────────────────────────────────────
func display_round_history(summary_text: String, target_player_log: bool = true) -> void:
	var tag = "▶ YOU: " if target_player_log else "◀ ENEMY: "
	combined_history_text += tag + summary_text + "\n"
	_update_history_displays()
	_auto_scroll_to_latest_log()

func _update_history_displays() -> void:
	if is_instance_valid(history_label):
		history_label.text = combined_history_text.strip_edges() if combined_history_text.strip_edges() != "" else ""

func _auto_scroll_to_latest_log() -> void:
	if is_instance_valid(history_scroll):
		await get_tree().process_frame
		var vbar = history_scroll.get_v_scroll_bar()
		if vbar: vbar.value = vbar.max_value

# ─── HP HEARTS ────────────────────────────────────────────────────────────────
func _parse_hp_to_hearts(hp: int, max_hp: int) -> String:
	if hp <= 0: return "💀 DEAD"
	var hp_per_heart = 20
	var total_slots = int(ceil(float(max_hp) / float(hp_per_heart)))
	if total_slots <= 0: total_slots = 1
	var full_count = int(hp / hp_per_heart)
	var remainder = hp % hp_per_heart
	if full_count > total_slots: full_count = total_slots; remainder = 0
	var s = ""
	for i in range(full_count): s += "❤️"
	var used = full_count
	if remainder > 0 and used < total_slots: s += "💔"; used += 1
	while used < total_slots: s += "🖤"; used += 1
	return s + "  %d / %d HP" % [hp, max_hp]

# ─── MAIN UI REFRESH ──────────────────────────────────────────────────────────
func _refresh_ui_states() -> void:
	if not current_enemy: return
	if is_waiting_on_action:
		_lock_all_player_inputs()
		return

	if fight_button: fight_button.disabled = false

	var is_disarmed: bool = current_enemy.player_is_disarmed if "player_is_disarmed" in current_enemy else false

	# --- Status bars ---
	if player_buffs_lbl:
		var s = ""
		if current_enemy.player_active_armor: s += "🛡️ ARMOR  "
		if current_enemy.player_sharpened:    s += "🪨 SHARP  "
		if current_enemy.player_piercing:     s += "📌 PIERCE  "
		if is_disarmed:                       s += "❌ DISARMED  "
		if "player_regen_rounds" in current_enemy and current_enemy.player_regen_rounds > 0: s += "🩹 REGEN×%d  " % current_enemy.player_regen_rounds
		if "player_horn_charges" in current_enemy and current_enemy.player_horn_charges > 0: s += "📯 HORN×%d  " % current_enemy.player_horn_charges
		if "player_reflect_active" in current_enemy and current_enemy.player_reflect_active: s += "🪞 REFLECT  "
		if "player_dodge_active" in current_enemy and current_enemy.player_dodge_active: s += "💨 DODGE  "
		if "player_weakened" in current_enemy and current_enemy.player_weakened: s += "🗿 WEAKENED  "
		if "player_counter_active" in current_enemy and current_enemy.player_counter_active: s += "⚡ COUNTER  "
		player_buffs_lbl.text = s if s != "" else "● Normal"

	if enemy_buffs_lbl:
		var s = ""
		if current_enemy.enemy_active_armor:  s += "🛡️ ARMOR  "
		if current_enemy.enemy_sharpened:     s += "🪨 SHARP  "
		if current_enemy.enemy_piercing:      s += "📌 PIERCE  "
		if current_enemy.enemy_is_disarmed:   s += "❌ DISARMED  "
		if "enemy_regen_rounds" in current_enemy and current_enemy.enemy_regen_rounds > 0: s += "🩹 REGEN×%d  " % current_enemy.enemy_regen_rounds
		if "enemy_poison_rounds" in current_enemy and current_enemy.enemy_poison_rounds > 0: s += "☠️ POISON×%d  " % current_enemy.enemy_poison_rounds
		if "enemy_horn_charges" in current_enemy and current_enemy.enemy_horn_charges > 0: s += "📯 HORN×%d  " % current_enemy.enemy_horn_charges
		if "enemy_reflect_active" in current_enemy and current_enemy.enemy_reflect_active: s += "🪞 REFLECT  "
		if "enemy_dodge_active" in current_enemy and current_enemy.enemy_dodge_active: s += "💨 DODGE  "
		if "enemy_weakened" in current_enemy and current_enemy.enemy_weakened: s += "🗿 WEAKENED  "
		if "enemy_counter_active" in current_enemy and current_enemy.enemy_counter_active: s += "⚡ COUNTER  "
		enemy_buffs_lbl.text = s if s != "" else "● Normal"

	if player_hp:
		player_hp.text = "YOU  " + _parse_hp_to_hearts(QuestManager.player_health, QuestManager.MAX_HEALTH)

	if enemy_hp:
		var emax = current_enemy.enemy_max_health if "enemy_max_health" in current_enemy else 100
		enemy_hp.text = "ENEMY LV.%d  " % current_enemy.enemy_level + _parse_hp_to_hearts(current_enemy.enemy_health, emax)

	# --- Drop countdown label — matches MobEnemy schedule exactly ---
	if drop_countdown_label:
		var next_item_count = min(current_enemy.drop_round_index + 1, 6)
		if current_enemy.cycles_until_drop <= 1:
			drop_countdown_label.text = "📦  Drop next round!  (+%d items)" % next_item_count
		else:
			drop_countdown_label.text = "📦  Drop in %d rounds  (+%d items)" % [current_enemy.cycles_until_drop, next_item_count]

	# --- Rebuild item buttons to reflect current inventory counts + equipped order ---
	var slots = QuestManager.equipped_items
	for i in range(item_buttons.size()):
		var btn = item_buttons[i] as Button
		if not is_instance_valid(btn): continue

		var item_id = slots[i] if i < slots.size() else ""
		if item_id == "":
			btn.visible = false
			continue

		btn.visible = true
		var meta = QuestManager.ITEM_META.get(item_id, {"emoji":"❓","label":item_id.capitalize(),"desc":""})
		var count = current_enemy.player_inventory.count(item_id)
		var slot_key = SLOT_KEYS[i] if i < SLOT_KEYS.size() else ""

		btn.text = "%s  %s\n[%s]  ×%d" % [meta["emoji"], meta["label"], slot_key, count]
		btn.tooltip_text = "%s %s\n%s" % [meta["emoji"], meta["label"], meta["desc"]]

		var is_usable = count > 0 and not is_disarmed
		# Per-item extra disable conditions
		if item_id == "potion" and QuestManager.player_health >= QuestManager.MAX_HEALTH:
			is_usable = false
		if item_id == "shield" and current_enemy.player_active_armor:
			is_usable = false
		if item_id == "grindstone" and current_enemy.player_sharpened:
			is_usable = false
		if item_id == "whip" and current_enemy.enemy_is_disarmed:
			is_usable = false
		if item_id == "needle" and current_enemy.player_piercing:
			is_usable = false
		if item_id == "bandage" and current_enemy.player_regen_rounds > 0:
			is_usable = false
		if item_id == "poison_dart" and current_enemy.enemy_poison_rounds > 0:
			is_usable = false
		if item_id == "battle_horn" and current_enemy.player_horn_charges > 0:
			is_usable = false
		if item_id == "mirror_ward" and current_enemy.player_reflect_active:
			is_usable = false
		if item_id == "smoke_bomb" and current_enemy.player_dodge_active:
			is_usable = false
		if item_id == "weaken_totem" and current_enemy.enemy_weakened:
			is_usable = false
		if item_id == "static_field" and current_enemy.player_counter_active:
			is_usable = false

		btn.disabled = not is_usable
		btn.modulate.a = 1.0 if is_usable else 0.38

	# --- Enemy inventory labels: hide items enemy can't have at their level ---
	_update_enemy_inventory_grid()

func _update_enemy_inventory_grid() -> void:
	if not current_enemy: return
	var pool = current_enemy.enemy_item_pool if "enemy_item_pool" in current_enemy else []

	if not is_instance_valid(enemy_inventory_container):
		enemy_inventory_container = find_child("EnemyItemsGrid") as GridContainer
	if not is_instance_valid(enemy_inventory_container): return

	# Rebuild dynamic labels to exactly match the enemy's pool, in pool order.
	# (Scales to any number of items without needing fixed scene nodes.)
	if enemy_item_labels.size() != pool.size() or enemy_item_labels_pool_ref != pool:
		for lbl in enemy_item_labels:
			if is_instance_valid(lbl): lbl.queue_free()
		enemy_item_labels.clear()
		for id in pool:
			var lbl = Label.new()
			lbl.name = "EnemyItemLabel_%s" % id
			lbl.add_theme_font_size_override("font_size", 13)
			enemy_inventory_container.add_child(lbl)
			enemy_item_labels.append(lbl)
		enemy_item_labels_pool_ref = pool.duplicate()

	for i in range(pool.size()):
		var id = pool[i]
		var lbl = enemy_item_labels[i]
		if not is_instance_valid(lbl): continue
		var meta = QuestManager.ITEM_META.get(id, {"emoji":"❓","label":id.capitalize()})
		var count = current_enemy.enemy_inventory.count(id)
		lbl.text = "%s %s  ×%d" % [meta["emoji"], meta["label"], count]
		lbl.modulate.a = 1.0 if count > 0 else 0.32

func _lock_all_player_inputs() -> void:
	if fight_button: fight_button.disabled = true
	for btn in item_buttons:
		if is_instance_valid(btn): btn.disabled = true

# ─── FIGHT BUTTON ─────────────────────────────────────────────────────────────
func _on_fight_pressed() -> void:
	if not visible: return
	if not QuestManager.is_in_combat: return
	if not is_instance_valid(current_enemy): return
	if is_waiting_on_action: return
	is_waiting_on_action = true
	_lock_all_player_inputs()

	# Step 1: Confirm first
	var confirmed = await show_blocking_popup("⚔️  ATTACK", "Commit to your attack phase?", true)
	if not confirmed:
		is_waiting_on_action = false
		_refresh_ui_states()
		return

	# Step 2: Player lunges — skip attack anim if disarmed
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		player = get_tree().root.find_child("mainplayer", true, false)
	if is_instance_valid(player) and player.has_method("do_attack_lunge"):
		var enemy_pos = current_enemy.global_position if is_instance_valid(current_enemy) else player.global_position
		var is_disarmed = current_enemy.player_is_disarmed if "player_is_disarmed" in current_enemy else false
		await player.do_attack_lunge(enemy_pos, current_enemy, is_disarmed)

	# Step 3: Process the actual attack
	if current_enemy.has_method("process_player_attack_phase"):
		await current_enemy.process_player_attack_phase()

	if turn_title_label and not "ENEMY TURN" in turn_title_label.text:
		is_waiting_on_action = false
		_refresh_ui_states()

# ─── ITEM USE ─────────────────────────────────────────────────────────────────
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

	var meta = QuestManager.ITEM_META.get(item_type, {"emoji":"❓","label":item_type.capitalize(),"desc":""})
	var confirmed = await show_blocking_popup(
		"%s  USE ITEM" % meta["emoji"],
		"Activate  [%s]?\n\n%s" % [meta["label"].to_upper(), meta["desc"]],
		true
	)
	if confirmed:
		if current_enemy.has_method("use_player_item"):
			await current_enemy.use_player_item(item_type)
		if turn_title_label and not "ENEMY TURN" in turn_title_label.text:
			is_waiting_on_action = false
			_refresh_ui_states()
	else:
		is_waiting_on_action = false
		_refresh_ui_states()

# ─── POPUP ────────────────────────────────────────────────────────────────────
func show_blocking_popup(header_title: String, message: String, require_confirmation: bool = false) -> bool:
	popup_title_lbl.text = header_title
	popup_label.text = message
	popup_overlay.visible = true

	# Clean any leftover magnet layout
	for child in popup_panel.get_children():
		if child.name == "MagnetLayoutVBox": child.queue_free()
	popup_panel.get_child(0).visible = true

	if require_confirmation:
		popup_confirm_btn.text = "✅  Confirm  (Enter)"
		popup_cancel_btn.text  = "❌  Cancel  (Esc)"
		popup_cancel_btn.visible = true
	else:
		popup_confirm_btn.text = "▶  Continue  (Enter)"
		popup_cancel_btn.visible = false

	var user_choice = await popup_resolved
	popup_overlay.visible = false
	return user_choice

func show_magnet_choice_popup(enemy_inv: Array) -> String:
	popup_overlay.visible = true
	magnet_currently_selected_item = ""

	var default_vbox = popup_panel.get_child(0)
	default_vbox.visible = false

	var magnet_vbox = VBoxContainer.new()
	magnet_vbox.name = "MagnetLayoutVBox"
	magnet_vbox.add_theme_constant_override("separation", 12)
	magnet_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	popup_panel.add_child(magnet_vbox)

	var title_lbl = Label.new()
	title_lbl.text = "🧲  MAGNET — Choose item to steal"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	magnet_vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = "Press [1–5] or click, then Commit"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	magnet_vbox.add_child(desc_lbl)

	var dynamic_grid = GridContainer.new()
	dynamic_grid.name = "MagnetGridContainer"
	dynamic_grid.columns = 3
	dynamic_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_grid.add_theme_constant_override("h_separation", 10)
	dynamic_grid.add_theme_constant_override("v_separation", 10)
	magnet_vbox.add_child(dynamic_grid)

	var unique_items: Array = []
	for item in enemy_inv:
		if item != "magnet" and not item in unique_items:
			unique_items.append(item)

	# ── Declare commit_btn FIRST so item button lambdas can close over it ──
	var commit_btn := Button.new()
	commit_btn.name = "CommitButton"
	commit_btn.text = "✅  Commit  (Enter)"
	commit_btn.focus_mode = Control.FOCUS_NONE
	commit_btn.custom_minimum_size = Vector2(0, 44)
	commit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commit_btn.disabled = true

	# ── Now build the item choice buttons (they reference commit_btn safely) ──
	var choice_btns: Array = []
	for i in range(unique_items.size()):
		var item = unique_items[i]
		var meta = QuestManager.ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var btn = Button.new()
		btn.text = "[%d]  %s  %s" % [i + 1, meta["emoji"], meta["label"]]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(130, 44)
		dynamic_grid.add_child(btn)
		choice_btns.append(btn)
		btn.pressed.connect(func():
			magnet_currently_selected_item = item
			for b in choice_btns: b.remove_theme_color_override("font_color")
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			commit_btn.disabled = false
		)

	if unique_items.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Enemy has no stealable items."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dynamic_grid.add_child(empty_lbl)

	# ── Action row: add commit + cancel ──
	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 12)
	magnet_vbox.add_child(action_hbox)
	action_hbox.add_child(commit_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "❌  Cancel  (Esc)"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): magnet_choice_resolved.emit(""))
	action_hbox.add_child(cancel_btn)

	commit_btn.pressed.connect(func():
		if magnet_currently_selected_item != "" and popup_overlay.visible:
			commit_btn.disabled = true
			magnet_choice_resolved.emit(magnet_currently_selected_item)
	)

	var chosen = await magnet_choice_resolved
	magnet_vbox.queue_free()
	popup_overlay.visible = false
	return chosen

func _resolve_popup(confirmed: bool) -> void:
	popup_resolved.emit(confirmed)
