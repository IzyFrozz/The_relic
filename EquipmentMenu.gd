extends CanvasLayer

# ── Node refs ──────────────────────────────────────────────────────────────────
var unlocked_grid: GridContainer = null
var equipped_grid: GridContainer = null
var close_button: Button = null
var title_label: Label = null
var bg_overlay: ColorRect = null   # dimmed background behind panel
var panel: Panel = null

# Item metadata centralized in QuestManager.ITEM_META

const COL_PANEL   := Color(0.09, 0.10, 0.15, 0.97)
const COL_BORDER  := Color(0.30, 0.35, 0.55, 1.0)
const COL_GOLD    := Color(1.00, 0.85, 0.30, 1.0)
const COL_GREEN   := Color(0.25, 0.90, 0.45, 1.0)
const COL_DIM     := Color(0.50, 0.50, 0.60, 1.0)
const COL_BTN_BG  := Color(0.13, 0.15, 0.21, 1.0)
const COL_BTN_HOV := Color(0.20, 0.23, 0.33, 1.0)
const COL_SECTION := Color(0.14, 0.16, 0.24, 1.0)

func _s(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8;   s.content_margin_bottom = 8
	return s

func _btn_s(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(5)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 8;   s.content_margin_bottom = 8
	return s

func _ready() -> void:
	visible = false

	# ── Wire scene nodes ──
	panel         = find_child("Panel",         true, false) as Panel
	title_label   = find_child("TitleLabel",    true, false) as Label
	unlocked_grid = find_child("UnlockedGrid",  true, false) as GridContainer
	equipped_grid = find_child("EquippedGrid",  true, false) as GridContainer
	close_button  = find_child("CloseButton",   true, false) as Button

	# ── Inject a full-screen dim overlay behind everything ──
	bg_overlay = ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.60)
	bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_overlay)
	move_child(bg_overlay, 0)

	# ── Add dark background inside the panel ──
	if is_instance_valid(panel):
		var panel_bg = ColorRect.new()
		panel_bg.name = "DarkBG"
		panel_bg.color = Color(0.07, 0.08, 0.12, 1.0)
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(panel_bg)
		panel.move_child(panel_bg, 0)

	# ── Style the main panel — solid dark with border ──
	if is_instance_valid(panel):
		var ps = StyleBoxFlat.new()
		ps.bg_color = Color(0.07, 0.08, 0.12, 1.0)
		ps.set_corner_radius_all(12)
		ps.set_border_width_all(2)
		ps.border_color = COL_BORDER
		ps.content_margin_left = 16; ps.content_margin_right = 16
		ps.content_margin_top = 14;  ps.content_margin_bottom = 14
		panel.add_theme_stylebox_override("panel", ps)

	# ── Title ──
	if is_instance_valid(title_label):
		title_label.text = "⚙️  LOADOUT CONFIGURATION"
		title_label.add_theme_font_size_override("font_size", 22)
		title_label.add_theme_color_override("font_color", COL_GOLD)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ── Close button — now gated: only enabled once loadout is full for level ──
	if is_instance_valid(close_button):
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.pressed.connect(_try_close)

	# ── Style section containers if they exist ──
	_style_section_container("UnlockedSection")
	_style_section_container("EquippedSection")

func _style_section_container(child_name: String) -> void:
	var node = find_child(child_name, true, false) as PanelContainer
	if is_instance_valid(node):
		node.add_theme_stylebox_override("panel", _s(COL_SECTION, Color(0.22, 0.26, 0.42), 8))

func _process(_delta: float) -> void:
	# Safety net: if a Win/Lose screen pops up while this menu happens to be
	# open, force it closed so it can never sit on top of an end screen.
	if visible and _is_end_screen_active():
		visible = false


func _is_end_screen_active() -> bool:
	for n in ["LoseUI", "WinUI"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node.visible:
			return true
	return false


func _try_close() -> void:
	var max_slots = QuestManager.get_max_equip_slots()
	var current = QuestManager.equipped_items.size()
	if current == max_slots:
		visible = false
		return
	# Not full — refuse to close, flash a warning on the button instead.
	if is_instance_valid(close_button):
		close_button.text = "⚠️  Fill all %d slots first!" % max_slots
		await get_tree().create_timer(1.1).timeout
		if is_instance_valid(close_button):
			_update_close_button()


func _update_close_button() -> void:
	if not is_instance_valid(close_button): return
	var max_slots = QuestManager.get_max_equip_slots()
	var current = QuestManager.equipped_items.size()
	var ready = current == max_slots
	if ready:
		close_button.text = "✓  Save & Exit  (Esc)"
		close_button.disabled = false
		close_button.modulate.a = 1.0
		close_button.add_theme_stylebox_override("normal", _btn_s(Color(0.08, 0.20, 0.10), Color(0.25, 0.60, 0.30)))
		close_button.add_theme_stylebox_override("hover",  _btn_s(Color(0.10, 0.30, 0.14), COL_GREEN))
		close_button.add_theme_color_override("font_color", COL_GREEN)
	else:
		close_button.text = "🔒  Need %d more item%s to Save & Exit" % [max_slots - current, "" if max_slots - current == 1 else "s"]
		close_button.disabled = false  # stays clickable so _try_close can show the warning flash
		close_button.modulate.a = 0.85
		close_button.add_theme_stylebox_override("normal", _btn_s(Color(0.22, 0.16, 0.06), Color(0.55, 0.40, 0.15)))
		close_button.add_theme_stylebox_override("hover",  _btn_s(Color(0.30, 0.22, 0.08), COL_GOLD))
		close_button.add_theme_color_override("font_color", COL_GOLD)
	close_button.add_theme_font_size_override("font_size", 14)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_try_close()
		get_viewport().set_input_as_handled()

func refresh_display() -> void:
	_build_unlocked_list()
	_build_equipped_list()
	_update_close_button()

func _section_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COL_DIM)
	return lbl

func _build_unlocked_list() -> void:
	if not is_instance_valid(unlocked_grid): return
	for child in unlocked_grid.get_children(): child.queue_free()

	# Find or inject a section header label above the grid
	_inject_header_above(unlocked_grid, "🔓  UNLOCKED ITEMS")

	for item in QuestManager.unlocked_items:
		var meta = QuestManager.ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var already = QuestManager.equipped_items.has(item)
		var full    = QuestManager.equipped_items.size() >= QuestManager.get_max_equip_slots()

		var btn = Button.new()
		btn.text = "%s  %s%s" % [meta["emoji"], meta["label"], "  ✓" if already else ""]
		btn.tooltip_text = meta["desc"] + ("\n(Already in loadout)" if already else "\nClick to equip")
		btn.disabled = already or full
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(155, 50)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal",   _btn_s(COL_BTN_BG, COL_BORDER if not already else COL_GREEN))
		btn.add_theme_stylebox_override("hover",    _btn_s(COL_BTN_HOV, COL_GOLD))
		btn.add_theme_stylebox_override("disabled", _btn_s(Color(0.10,0.10,0.14), Color(0.22,0.22,0.30)))
		btn.add_theme_color_override("font_color", COL_GREEN if already else Color(0.92, 0.92, 1.0))
		btn.add_theme_color_override("font_disabled_color", COL_DIM)
		btn.modulate.a = 0.5 if already else 1.0
		var captured = item
		btn.pressed.connect(func(): _equip_item(captured))
		unlocked_grid.add_child(btn)

func _build_equipped_list() -> void:
	if not is_instance_valid(equipped_grid): return
	for child in equipped_grid.get_children(): child.queue_free()

	var max_slots = QuestManager.get_max_equip_slots()
	var current = QuestManager.equipped_items.size()
	var header_color_hint = "✓" if current == max_slots else "…"
	_inject_header_above(equipped_grid, "⚔️  ACTIVE LOADOUT  (%d / %d)  %s" % [current, max_slots, header_color_hint])

	for i in range(QuestManager.equipped_items.size()):
		var item   = QuestManager.equipped_items[i]
		var meta   = QuestManager.ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})

		var btn = Button.new()
		btn.text = "[%d]  %s  %s  ✕" % [i + 1, meta["emoji"], meta["label"]]
		btn.tooltip_text = "Slot %d — %s\nClick to remove" % [i + 1, meta["desc"]]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(175, 50)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal",   _btn_s(COL_BTN_BG, COL_BORDER))
		btn.add_theme_stylebox_override("hover",    _btn_s(Color(0.22, 0.09, 0.09), Color(0.80, 0.28, 0.28)))
		btn.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
		var captured = item
		btn.pressed.connect(func(): _unequip_item(captured))
		equipped_grid.add_child(btn)

	# Show empty placeholder slots for what's still needed to reach max
	for i in range(current, max_slots):
		var empty_btn = Button.new()
		empty_btn.text = "[%d]  — empty slot —" % (i + 1)
		empty_btn.tooltip_text = "Equip an item from the Unlocked list to fill this slot"
		empty_btn.disabled = true
		empty_btn.custom_minimum_size = Vector2(175, 50)
		empty_btn.add_theme_font_size_override("font_size", 13)
		empty_btn.add_theme_stylebox_override("disabled", _btn_s(Color(0.09,0.09,0.12), Color(0.45,0.35,0.15)))
		empty_btn.add_theme_color_override("font_disabled_color", COL_GOLD)
		empty_btn.modulate.a = 0.55
		equipped_grid.add_child(empty_btn)

func _inject_header_above(grid: GridContainer, header_text: String) -> void:
	# Walk up to parent to insert a label sibling above the grid
	var parent = grid.get_parent()
	if not is_instance_valid(parent): return
	var grid_idx = grid.get_index()
	# Check if label already exists above
	if grid_idx > 0:
		var above = parent.get_child(grid_idx - 1)
		if above is Label:
			(above as Label).text = header_text
			return
	var lbl = Label.new()
	lbl.text = header_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	parent.add_child(lbl)
	parent.move_child(lbl, grid_idx)

func _equip_item(item: String) -> void:
	if QuestManager.equipped_items.has(item): return
	if QuestManager.equipped_items.size() >= QuestManager.get_max_equip_slots(): return
	QuestManager.equipped_items.append(item)
	QuestManager.has_unsaved_progress = true
	refresh_display()

func _unequip_item(item: String) -> void:
	QuestManager.equipped_items.erase(item)
	QuestManager.has_unsaved_progress = true
	refresh_display()
