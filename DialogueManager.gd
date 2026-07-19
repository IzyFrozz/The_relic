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
signal choice_selected(index: int)

var is_active: bool = false
var _awaiting_choice: bool = false
var _choice_row: HBoxContainer

var _lines: Array = []
var _index: int = 0
var _typing: bool = false
var _char_progress: float = 0.0
var _total_chars: int = 0
var _last_blip_char: int = 0   # throttles the typewriter blip

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
const BLIP_EVERY := 3      # play the typewriter blip once per N revealed chars

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

# Present a prompt with clickable options and await the player's pick. Returns
# the chosen option index. Click a button, or press the number keys 1..N.
#     var choice = await DialogueManager.ask("Kid", "Turn it in?", ["Yes", "No"])
func ask(speaker: String, prompt: String, options: Array) -> int:
	is_active = true
	_awaiting_choice = true
	_typing = false
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.12)
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_body_label.text = IconDB.iconify(prompt, 22)
	_body_label.visible_characters = -1
	_hint_label.visible = false
	for c in _choice_row.get_children():
		c.queue_free()
	_choice_row.visible = true
	for i in range(options.size()):
		var b = Button.new()
		b.text = "%d.  %s" % [i + 1, options[i]]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(0.14, 0.16, 0.24, 1.0)
		bs.set_corner_radius_all(8); bs.set_border_width_all(2)
		bs.border_color = COL_BORDER
		bs.content_margin_left = 16; bs.content_margin_right = 16
		bs.content_margin_top = 8;   bs.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", bs)
		var bh = bs.duplicate() as StyleBoxFlat
		bh.border_color = COL_GOLD
		b.add_theme_stylebox_override("hover", bh)
		var idx := i
		b.pressed.connect(func(): _pick_choice(idx))
		_choice_row.add_child(b)
	var chosen = await choice_selected
	return chosen

func _pick_choice(idx: int) -> void:
	if not _awaiting_choice:
		return
	_awaiting_choice = false
	_choice_row.visible = false
	_hint_label.visible = true
	is_active = false
	var tw = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.10)
	tw.tween_callback(_hide_box)
	choice_selected.emit(idx)

# ── Build UI (code-driven, resolution-independent) ──────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	# Anchored to the bottom of the safe area (kept clear of the screen edges).
	# Taller box, extended upward.
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 210; _panel.offset_right = -210
	_panel.offset_top = -300; _panel.offset_bottom = -96
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps = StyleBoxFlat.new()
	ps.bg_color = COL_BG
	ps.set_corner_radius_all(14); ps.set_border_width_all(2)
	ps.border_color = COL_BORDER
	_panel.add_theme_stylebox_override("panel", ps)
	_root.add_child(_panel)

	# Speaker name tag — sits on the top-left edge, clear of the body text.
	_name_label = Label.new()
	_name_label.position = Vector2(26, -20)
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.add_theme_color_override("font_color", COL_GOLD)
	var ns = StyleBoxFlat.new()
	ns.bg_color = Color(0.12, 0.14, 0.22, 1.0)
	ns.set_corner_radius_all(8); ns.set_border_width_all(2)
	ns.border_color = COL_GOLD
	ns.content_margin_left = 16; ns.content_margin_right = 16
	ns.content_margin_top = 6;   ns.content_margin_bottom = 6
	_name_label.add_theme_stylebox_override("normal", ns)
	_panel.add_child(_name_label)

	# Body text — explicitly inset from the panel so it sits BELOW the name tag.
	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 28; vb.offset_right = -28
	vb.offset_top = 42;  vb.offset_bottom = -14
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 23)
	_body_label.add_theme_color_override("default_color", COL_TEXT)
	vb.add_child(_body_label)

	# Choice buttons (hidden unless ask() is showing options).
	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 16)
	_choice_row.visible = false
	vb.add_child(_choice_row)

	_hint_label = Label.new()
	_hint_label.text = "▸  Space"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.86))
	vb.add_child(_hint_label)

# ── Line flow ────────────────────────────────────────────────────────────────
func _show_line() -> void:
	var line = _lines[_index]
	_name_label.text = str(line.get("name", ""))
	_name_label.visible = _name_label.text != ""
	# Swap any item/world emoji in the line for real icons (🏺 relic, 🧭 compass, …).
	_body_label.text = IconDB.iconify(str(line.get("text", "")), 22)
	_total_chars = _body_label.get_total_character_count()
	_body_label.visible_characters = 0
	_char_progress = 0.0
	_last_blip_char = 0
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
		# Blip every few revealed characters — one per char would be a machine-gun.
		if shown > _last_blip_char and (shown - _last_blip_char) >= BLIP_EVERY:
			_last_blip_char = shown
			SFX.play(SFX.dialogue_blip, -8.0, 0.12)
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
	# While a choice is on screen, number keys pick an option; advance/close keys
	# are ignored so the prompt can't be dismissed without choosing.
	if _awaiting_choice:
		if event is InputEventKey and event.pressed and not event.echo:
			var n: int = (event as InputEventKey).keycode - KEY_1
			if n >= 0 and n < _choice_row.get_child_count():
				get_viewport().set_input_as_handled()
				_pick_choice(n)
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
