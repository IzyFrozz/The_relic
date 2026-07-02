extends CanvasLayer

# ── Event toast ─────────────────────────────────────────────────────────────
# A brief top-centre pop-up that announces things as they happen (quest
# accepted, key/relic obtained, XP gained, level up, …). Fades in, holds for a
# few seconds, fades out. Any script can call:
#     Toast.show_toast("⚔️  Victory!  +40 XP")
# Non-blocking and non-interactive.

const COL_BG     := Color(0.08, 0.09, 0.13, 0.96)
const COL_BORDER := Color(1.00, 0.85, 0.30, 0.95)

var _panel: Panel = null
var _label: Label = null
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

	_panel = Panel.new()
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 0.0;  _panel.anchor_bottom = 0.0
	_panel.offset_left = -300; _panel.offset_right = 300
	_panel.offset_top = 70;    _panel.offset_bottom = 116
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(9); s.set_border_width_all(2)
	s.border_color = COL_BORDER
	_panel.add_theme_stylebox_override("panel", s)
	root.add_child(_panel)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82))
	_panel.add_child(_label)

func show_toast(text: String, duration: float = 4.0) -> void:
	if not is_instance_valid(_label):
		return
	_label.text = text
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
