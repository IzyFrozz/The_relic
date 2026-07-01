extends CanvasLayer

# ── Global dialogue overlay ─────────────────────────────────────────────────
# Autoloaded. Any NPC can drive a conversation:
#     DialogueManager.say("Elder", "Hello, traveller.")
#     DialogueManager.start([{ "name": "Kid", "text": "..." }, { ... }])
# Space / Enter advances. While a line is still typing, the first press snaps it
# to full; the next press advances. Emits `dialogue_finished` when the last line
# is dismissed. `is_active` is true for the whole conversation so the player /
# NPCs can pause themselves.

signal dialogue_finished

var is_active: bool = false

var _lines: Array = []
var _index: int = 0
var _typing: bool = false
var _char_progress: float = 0.0
var _total_chars: int = 0

var _root: Control
var _panel: Panel
var _name_label: Label
var _body_label: RichTextLabel
var _hint_label: Label

const COL_BG     := Color(0.06, 0.07, 0.11, 0.98)
const COL_BORDER := Color(0.35, 0.40, 0.60, 1.0)
const COL_GOLD   := Color(1.00, 0.85, 0.30, 1.0)
const COL_TEXT   := Color(0.92, 0.93, 1.00, 1.0)
const TYPE_CPS   := 48.0   # characters revealed per second

func _ready() -> void:
	layer = 120                       # above HUD, below hard end-screens
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide_box()

# ── Public API ──────────────────────────────────────────────────────────────
func say(speaker: String, text: String) -> void:
	start([{ "name": speaker, "text": text }])

func start(lines: Array) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_index = 0
	is_active = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.12)
	_show_line()

# ── Build UI (code-driven, resolution-independent) ──────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	# Anchored to the bottom of the safe area (kept clear of the screen edges).
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 210; _panel.offset_right = -210
	_panel.offset_top = -232; _panel.offset_bottom = -96
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps = StyleBoxFlat.new()
	ps.bg_color = COL_BG
	ps.set_corner_radius_all(14); ps.set_border_width_all(2)
	ps.border_color = COL_BORDER
	ps.content_margin_left = 28; ps.content_margin_right = 28
	ps.content_margin_top = 40;  ps.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", ps)
	_root.add_child(_panel)

	# Speaker name tag — sits on the top-left edge of the panel.
	_name_label = Label.new()
	_name_label.position = Vector2(20, -16)
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.add_theme_color_override("font_color", COL_GOLD)
	var ns = StyleBoxFlat.new()
	ns.bg_color = Color(0.12, 0.14, 0.22, 1.0)
	ns.set_corner_radius_all(8); ns.set_border_width_all(1)
	ns.border_color = COL_GOLD
	ns.content_margin_left = 14; ns.content_margin_right = 14
	ns.content_margin_top = 5;   ns.content_margin_bottom = 5
	_name_label.add_theme_stylebox_override("normal", ns)
	_panel.add_child(_name_label)

	var vb = VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 19)
	_body_label.add_theme_color_override("default_color", COL_TEXT)
	vb.add_child(_body_label)

	_hint_label = Label.new()
	_hint_label.text = "▸  Space"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.82))
	vb.add_child(_hint_label)

# ── Line flow ────────────────────────────────────────────────────────────────
func _show_line() -> void:
	var line = _lines[_index]
	_name_label.text = str(line.get("name", ""))
	_name_label.visible = _name_label.text != ""
	_body_label.text = str(line.get("text", ""))
	_total_chars = _body_label.get_total_character_count()
	_body_label.visible_characters = 0
	_char_progress = 0.0
	_typing = _total_chars > 0
	_hint_label.text = "▸  Space" if not _typing else "…"

func _process(delta: float) -> void:
	if not _typing:
		return
	_char_progress += TYPE_CPS * delta
	var shown = int(_char_progress)
	if shown >= _total_chars:
		_finish_typing()
	else:
		_body_label.visible_characters = shown

func _finish_typing() -> void:
	_typing = false
	_body_label.visible_characters = -1
	_hint_label.text = "▸  Space" if _index < _lines.size() - 1 else "✓  Space"

func _advance() -> void:
	if _typing:
		_finish_typing()
		return
	_index += 1
	if _index >= _lines.size():
		_close()
	else:
		_show_line()

func _close() -> void:
	is_active = false
	var tw = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.10)
	tw.tween_callback(_hide_box)
	dialogue_finished.emit()

func _hide_box() -> void:
	_root.visible = false

func _input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				_advance()
			KEY_ESCAPE:
				# Esc fast-forwards to the end of the whole conversation.
				get_viewport().set_input_as_handled()
				_index = _lines.size() - 1
				_finish_typing()
				_close()
