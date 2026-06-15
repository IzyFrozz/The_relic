extends CanvasLayer

# ── Node refs ──────────────────────────────────────────────────────────────────
var unlocked_grid: GridContainer = null
var equipped_grid: GridContainer = null
var close_button: Button = null
var title_label: Label = null
var bg_overlay: ColorRect = null   # dimmed background behind panel
var panel: Panel = null

const ITEM_META := {
	"potion":     { "emoji": "🧪", "label": "Potion",     "desc": "Restores 20 HP instantly." },
	"shield":     { "emoji": "🛡️", "label": "Shield",     "desc": "Blocks the next incoming hit." },
	"grindstone": { "emoji": "🪨", "label": "Grindstone", "desc": "Next attack deals 2× damage." },
	"whip":       { "emoji": "💥", "label": "Whip",       "desc": "Enemy skips their entire turn." },
	"needle":     { "emoji": "📌", "label": "Needle",     "desc": "Next strike pierces enemy armor." },
	"magnet":     { "emoji": "🧲", "label": "Magnet",     "desc": "Steal one item from the enemy." },
}

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
	# (insert as first child of this CanvasLayer so it renders under Panel)
	bg_overlay = ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.60)
	bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_overlay)
	move_child(bg_overlay, 0)

	# ── Style the main panel ──
	if is_instance_valid(panel):
		panel.add_theme_stylebox_override("panel", _s(COL_PANEL, COL_BORDER, 12))

	# ── Title ──
	if is_instance_valid(title_label):
		title_label.text = "⚙️  LOADOUT CONFIGURATION"
		title_label.add_theme_font_size_override("font_size", 22)
		title_label.add_theme_color_override("font_color", COL_GOLD)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ── Close button ──
	if is_instance_valid(close_button):
		close_button.text = "✖  Close  (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.add_theme_stylebox_override("normal", _btn_s(Color(0.22, 0.07, 0.07), Color(0.55, 0.18, 0.18)))
		close_button.add_theme_stylebox_override("hover",  _btn_s(Color(0.38, 0.10, 0.10), Color(0.85, 0.28, 0.28)))
		close_button.add_theme_color_override("font_color", Color(1.0, 0.50, 0.50))
		close_button.add_theme_font_size_override("font_size", 14)
		close_button.pressed.connect(func(): visible = false)

	# ── Style section containers if they exist ──
	_style_section_container("UnlockedSection")
	_style_section_container("EquippedSection")

func _style_section_container(child_name: String) -> void:
	var node = find_child(child_name, true, false) as Panel
	if is_instance_valid(node):
		node.add_theme_stylebox_override("panel", _s(COL_SECTION, Color(0.22, 0.26, 0.42), 8))

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func refresh_display() -> void:
	_build_unlocked_list()
	_build_equipped_list()

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
		var meta = ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var already = QuestManager.equipped_items.has(item)
		var full    = QuestManager.equipped_items.size() >= 6

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

	_inject_header_above(equipped_grid, "⚔️  ACTIVE LOADOUT  (%d / 6)" % QuestManager.equipped_items.size())

	for i in range(QuestManager.equipped_items.size()):
		var item   = QuestManager.equipped_items[i]
		var meta   = ITEM_META.get(item, {"emoji":"❓","label":item.capitalize(),"desc":""})
		var locked = QuestManager.equipped_items.size() <= 2

		var btn = Button.new()
		btn.text = "[%d]  %s  %s%s" % [i + 1, meta["emoji"], meta["label"], "" if locked else "  ✕"]
		btn.tooltip_text = "Slot %d — %s%s" % [i + 1, meta["desc"], "\n(Min 2 required)" if locked else "\nClick to remove"]
		btn.disabled = locked
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(175, 50)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal",   _btn_s(COL_BTN_BG, COL_BORDER))
		btn.add_theme_stylebox_override("hover",    _btn_s(Color(0.22, 0.09, 0.09), Color(0.80, 0.28, 0.28)))
		btn.add_theme_stylebox_override("disabled", _btn_s(Color(0.10,0.11,0.15), Color(0.22,0.22,0.28)))
		btn.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
		btn.add_theme_color_override("font_disabled_color", COL_DIM)
		btn.modulate.a = 0.5 if locked else 1.0
		var captured = item
		btn.pressed.connect(func(): _unequip_item(captured))
		equipped_grid.add_child(btn)

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
	if QuestManager.equipped_items.size() >= 6: return
	QuestManager.equipped_items.append(item)
	refresh_display()

func _unequip_item(item: String) -> void:
	if QuestManager.equipped_items.size() <= 2: return
	QuestManager.equipped_items.erase(item)
	refresh_display()
