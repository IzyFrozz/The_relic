extends CanvasLayer

# ── Event toast ─────────────────────────────────────────────────────────────
# A brief top-centre pop-up that announces things as they happen (quest
# accepted, key/relic obtained, XP gained, level up, …). Fades in, holds for a
# few seconds, fades out. Any script can call:
#     Toast.show_toast("⚔️  Victory!  +40 XP")
# Non-blocking and non-interactive.

const COL_BG     := Color(0.08, 0.09, 0.13, 0.96)
const COL_BORDER := Color(1.00, 0.85, 0.30, 0.95)

# Text column width. The panel is this plus padding, and anything longer WRAPS to
# another line instead of running past the border — the toast takes arbitrary
# caller strings ("Obtained the Ancient Relic — equip it in your Loadout, or
# return it to win!" is ~690px at this font size), so it can never assume the
# message fits on one line.
const TOAST_TEXT_W := 720.0
const PAD_H := 18
const PAD_V := 11

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _timer: float = 0.0
var _fading: bool = false

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# PanelContainer, not Panel: its HEIGHT follows the label, so a message that
	# wraps to two lines grows the box instead of spilling out of it. The width is
	# fixed so the toast doesn't jitter between messages.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 0.0;  _panel.anchor_bottom = 0.0
	_panel.offset_left  = -(TOAST_TEXT_W * 0.5 + PAD_H)
	_panel.offset_right =  (TOAST_TEXT_W * 0.5 + PAD_H)
	_panel.offset_top = 70;   _panel.offset_bottom = 70   # zero height; grows down
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(9); s.set_border_width_all(2)
	s.border_color = COL_BORDER
	_panel.add_theme_stylebox_override("panel", s)
	root.add_child(_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", PAD_H)
	pad.add_theme_constant_override("margin_right", PAD_H)
	pad.add_theme_constant_override("margin_top", PAD_V)
	pad.add_theme_constant_override("margin_bottom", PAD_V)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	# WRAP, not OFF. This is the whole fix: the label now spans the panel's text
	# column and folds long messages onto a second line.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 17)
	_label.add_theme_color_override("default_color", Color(0.98, 0.94, 0.82))
	pad.add_child(_label)

func show_toast(text: String, duration: float = 4.0) -> void:
	if not is_instance_valid(_label):
		return
	# Swap any emoji that has a real icon for an inline [img]; unmapped glyphs stay.
	# [center] is required now that the label spans the full text column — the old
	# CenterContainer centred a shrink-to-fit label, which no longer applies.
	_label.text = "[center]%s[/center]" % IconDB.iconify(text, 22)
	_panel.visible = true
	_fading = false
	_timer = duration
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.20)

func _process(delta: float) -> void:
	if not _panel.visible or _fading:
		return
	_timer -= delta
	if _timer <= 0.0:
		_fading = true
		var tw = create_tween()
		tw.tween_property(_panel, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): _panel.visible = false)
