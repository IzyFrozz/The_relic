extends CanvasLayer

# ── World map + fog of war + compass ─────────────────────────────────────────
# Autoloaded. Reveals the world as the player walks it (fog of war), on a coarse
# grid of cells persisted in the save (QuestManager.explored_cells). Provides:
#   • a always-on corner MINI-MAP,
#   • a full-screen MAP toggled with M,
#   • a COMPASS: a directional arrow + label pointing at the current objective,
#     unlocked by talking to the Navigator (QuestManager.has_compass). Before
#     that it points the player at the Navigator itself so they can't get lost.
#
# All drawing is done in _paint(), forwarded from two MapCanvas child nodes.

const MapCanvas = preload("res://MapCanvas.gd")

const CELL := 96.0                 # world units per fog cell
const REVEAL_RADIUS := 1           # also reveal the ring of cells around the player
const REFRESH_DT := 0.12           # how often we reveal / redraw (seconds)

const MINI_SIZE := Vector2(196, 196)
const MINI_CELL_PX := 11.0         # pixels per cell on the mini-map

# Only the overworld island is mapped. House interiors and the combat arena live
# far off to the side (x ≈ -3000…-4900) — reveals there are ignored so they never
# show up on the world map (houses are found via the [E] door prompt instead).
# Tune this rect if you extend the overworld.
const OVERWORLD_BOUNDS := Rect2(-1200, -900, 2800, 1900)   # x:-1200..1600, y:-900..1000

func _in_overworld(pos: Vector2) -> bool:
	return OVERWORLD_BOUNDS.has_point(pos)

const BG_COLOR       := Color(0.06, 0.07, 0.11, 0.92)
const UNEXPLORED_COL := Color(0.12, 0.13, 0.18, 1.0)
const EXPLORED_COL   := Color(0.24, 0.30, 0.42, 1.0)
const EXPLORED_EDGE  := Color(0.32, 0.40, 0.55, 1.0)
const PLAYER_COL     := Color(0.45, 0.90, 1.0, 1.0)
const OBJ_COLOR      := Color(1.0, 0.82, 0.28, 1.0)
const NAV_COLOR      := Color(0.55, 0.95, 0.55, 1.0)

var _mini_panel: Panel
var _mini_canvas: Control
var _compass_bar: Panel
var _compass_ribbon: Control
var _compass_text: Label

var _full_root: Control
var _full_canvas: Control
var _full_hint: Label

var _accum := 0.0
var _open_full := false

func _ready() -> void:
	layer = 95
	_build_minimap()
	_build_compass_bar()
	_build_fullmap()

# A faked top-center "compass" strip: a directional-tick ribbon (drawn) plus the
# current objective + heading + distance. Stands in for real compass art.
func _build_compass_bar() -> void:
	_compass_bar = Panel.new()
	_compass_bar.anchor_left = 0.5; _compass_bar.anchor_right = 0.5
	_compass_bar.anchor_top = 0.0;  _compass_bar.anchor_bottom = 0.0
	_compass_bar.offset_left = -230; _compass_bar.offset_right = 230
	_compass_bar.offset_top = 12;    _compass_bar.offset_bottom = 62
	_compass_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_compass_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.07, 0.11, 0.92)
	ps.set_corner_radius_all(8); ps.set_border_width_all(2)
	ps.border_color = Color(0.42, 0.48, 0.68)
	_compass_bar.add_theme_stylebox_override("panel", ps)
	add_child(_compass_bar)

	# Drawn N/E/S/W tick ribbon that scrolls with the player's heading.
	_compass_ribbon = MapCanvas.new()
	_compass_ribbon.set("map", self)
	_compass_ribbon.set("full", false)
	_compass_ribbon.name = "CompassRibbon"
	_compass_ribbon.position = Vector2(10, 6)
	_compass_ribbon.size = Vector2(440, 20)
	_compass_ribbon.clip_contents = true
	_compass_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_bar.add_child(_compass_ribbon)

	_compass_text = Label.new()
	_compass_text.position = Vector2(10, 26)
	_compass_text.size = Vector2(440, 20)
	_compass_text.add_theme_font_size_override("font_size", 14)
	_compass_text.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_compass_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_bar.add_child(_compass_text)

# ── UI construction ───────────────────────────────────────────────────────────
func _build_minimap() -> void:
	# Bottom-right corner (out of the way of the top-left menu buttons).
	_mini_panel = Panel.new()
	_mini_panel.anchor_left = 1.0; _mini_panel.anchor_right = 1.0
	_mini_panel.anchor_top = 1.0;  _mini_panel.anchor_bottom = 1.0
	# 8px inner margin around the canvas + room for the hint line below it.
	_mini_panel.offset_left = -(MINI_SIZE.x + 32); _mini_panel.offset_right = -16
	_mini_panel.offset_top = -(MINI_SIZE.y + 58); _mini_panel.offset_bottom = -16
	_mini_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mini_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var ps := StyleBoxFlat.new()
	ps.bg_color = BG_COLOR
	ps.set_corner_radius_all(10); ps.set_border_width_all(2)
	ps.border_color = Color(0.30, 0.36, 0.55)
	_mini_panel.add_theme_stylebox_override("panel", ps)
	add_child(_mini_panel)

	var clip := Control.new()
	clip.position = Vector2(8, 8)
	clip.size = MINI_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_panel.add_child(clip)

	_mini_canvas = MapCanvas.new()
	_mini_canvas.size = MINI_SIZE
	_mini_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_canvas.set("map", self)
	_mini_canvas.set("full", false)
	clip.add_child(_mini_canvas)

	var hint := Label.new()
	hint.position = Vector2(8, MINI_SIZE.y + 9)
	hint.size = Vector2(MINI_SIZE.x, 18)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "press  M  for full map"
	_mini_panel.add_child(hint)

func _build_fullmap() -> void:
	_full_root = Control.new()
	_full_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_root.visible = false
	add_child(_full_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_root.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 620)
	panel.offset_left = -430; panel.offset_right = 430
	panel.offset_top = -310; panel.offset_bottom = 310
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.06, 0.10, 0.99)
	ps.set_corner_radius_all(14); ps.set_border_width_all(2)
	ps.border_color = Color(0.34, 0.40, 0.60)
	panel.add_theme_stylebox_override("panel", ps)
	_full_root.add_child(panel)

	var title := Label.new()
	title.text = "🗺  World Map"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	panel.add_child(title)

	_full_canvas = MapCanvas.new()
	_full_canvas.position = Vector2(24, 58)
	_full_canvas.size = Vector2(812, 496)
	_full_canvas.clip_contents = true
	_full_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_canvas.set("map", self)
	_full_canvas.set("full", true)
	panel.add_child(_full_canvas)

	_full_hint = Label.new()
	_full_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_full_hint.offset_top = -34
	_full_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_hint.add_theme_font_size_override("font_size", 14)
	_full_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	_full_hint.text = "🔵 You    🟡 Objective    ▪ explored    ·  press  M  or  Esc  to close"
	panel.add_child(_full_hint)

# ── Update loop ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	var gate := _map_gate_ok()
	var available := gate and _map_available()
	# The live mini-map + compass only show on the mappable island. In a house or
	# in combat they hide (the full map still opens, to say "Map Unavailable").
	_mini_panel.visible = available
	_compass_bar.visible = available
	if _open_full and not gate:
		_set_full(false)
	if not gate:
		return
	# Map toggle uses the editable "toggle_map" action (default M).
	if Input.is_action_just_pressed("toggle_map"):
		_set_full(not _open_full)
	_accum += delta
	if _accum < REFRESH_DT:
		return
	_accum = 0.0
	if available:
		var player := _player_node()
		if is_instance_valid(player):
			_reveal(player.global_position)
		_update_compass_bar()
		_mini_canvas.queue_redraw()
		_compass_ribbon.queue_redraw()
	if _open_full:
		_full_canvas.queue_redraw()   # draws the map, or the "unavailable" notice

func _input(event: InputEvent) -> void:
	# Esc closes the full map (the toggle itself is polled in _process so it uses
	# the rebindable "toggle_map" action).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _open_full:
			get_viewport().set_input_as_handled()
			_set_full(false)

func _set_full(v: bool) -> void:
	_open_full = v
	_full_root.visible = v
	if v:
		_full_canvas.queue_redraw()

# ── Fog of war reveal ─────────────────────────────────────────────────────────
func _reveal(world_pos: Vector2) -> void:
	# Never reveal cells outside the overworld (house interiors / combat arena).
	if not _in_overworld(world_pos):
		return
	var cx := int(floor(world_pos.x / CELL))
	var cy := int(floor(world_pos.y / CELL))
	var changed := false
	for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			var key := "%d,%d" % [cx + dx, cy + dy]
			if not QuestManager.explored_cells.has(key):
				QuestManager.explored_cells[key] = true
				changed = true
	if changed:
		QuestManager.has_unsaved_progress = true

# ── Painting (called from MapCanvas._draw) ────────────────────────────────────
func _paint(canvas: Control, full: bool) -> void:
	if canvas == _compass_ribbon:
		_paint_compass(canvas)
		return
	var size: Vector2 = canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	# Full map opened somewhere it can't map (a house interior, or combat) — say so.
	if full and not _map_available():
		var font := ThemeDB.fallback_font
		if font:
			var msg := "🚫  Map Unavailable"
			var sub := "(No map inside buildings or during combat.)"
			var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			canvas.draw_string(font, Vector2((size.x - mw) * 0.5, size.y * 0.5 - 8),
				msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.9, 0.6, 0.55))
			canvas.draw_string(font, Vector2((size.x - sw) * 0.5, size.y * 0.5 + 24),
				sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.62, 0.72))
		return
	var player := _player_node()
	var ppos: Vector2 = player.global_position if is_instance_valid(player) else Vector2.ZERO

	var scale: float
	var offset: Vector2
	if full:
		var b := _explored_world_bounds(ppos)
		var pad := 30.0
		var sx := (size.x - pad * 2) / maxf(b.size.x, CELL)
		var sy := (size.y - pad * 2) / maxf(b.size.y, CELL)
		scale = minf(sx, sy)
		scale = clampf(scale, 0.02, 0.6)
		var drawn := b.size * scale
		offset = (size - drawn) * 0.5 - b.position * scale
	else:
		scale = MINI_CELL_PX / CELL
		offset = size * 0.5 - ppos * scale

	# Explored cells.
	var cell_draw := Vector2(CELL * scale + 1.0, CELL * scale + 1.0)
	for key in QuestManager.explored_cells.keys():
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() != 2:
			continue
		var wx := float(int(parts[0])) * CELL
		var wy := float(int(parts[1])) * CELL
		# Skip any off-island cells baked into older saves (interiors / arena).
		if not _in_overworld(Vector2(wx + CELL * 0.5, wy + CELL * 0.5)):
			continue
		var cp := Vector2(wx, wy) * scale + offset
		if cp.x < -cell_draw.x or cp.y < -cell_draw.y or cp.x > size.x or cp.y > size.y:
			continue
		canvas.draw_rect(Rect2(cp, cell_draw), EXPLORED_COL)

	# Objective marker + compass arrow.
	var obj := _objective()
	if not obj.is_empty():
		var ocol: Color = obj.get("color", OBJ_COLOR)
		var op: Vector2 = obj["pos"] * scale + offset
		var inside := op.x >= 0 and op.y >= 0 and op.x <= size.x and op.y <= size.y
		if inside:
			canvas.draw_circle(op, 5.0, ocol)
			canvas.draw_arc(op, 8.0, 0, TAU, 20, ocol, 1.5)
		else:
			# Clamp to the edge and draw an arrow pointing outward toward it.
			var centre := size * 0.5
			var dir := (op - centre).normalized()
			var edge := centre + dir * (minf(size.x, size.y) * 0.5 - 12.0)
			_draw_arrow(canvas, edge, dir, ocol)

	# Player marker (drawn last, on top).
	var pc: Vector2 = ppos * scale + offset
	if full:
		pc = ppos * scale + offset
	canvas.draw_circle(pc, 4.5, PLAYER_COL)
	canvas.draw_arc(pc, 7.0, 0, TAU, 18, Color(1, 1, 1, 0.8), 1.5)

# Faked compass ribbon: cardinal ticks/letters scroll so the bearing to the
# current objective sits under the fixed centre pointer.
func _paint_compass(canvas: Control) -> void:
	var w: float = canvas.size.x
	var h: float = canvas.size.y
	var font := ThemeDB.fallback_font
	var bearing := 0.0
	var have := false
	var obj := _objective()
	var player := _player_node()
	if not obj.is_empty() and is_instance_valid(player):
		var d: Vector2 = obj["pos"] - player.global_position
		bearing = rad_to_deg(atan2(d.x, -d.y))   # 0 = North (up), 90 = East
		if bearing < 0: bearing += 360.0
		have = true
	var labels := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	var px_per_deg := w / 160.0   # ~160° span across the ribbon
	for deg in labels.keys():
		var rel: float = wrapf(float(deg) - bearing + 180.0, 0.0, 360.0) - 180.0
		var x := w * 0.5 + rel * px_per_deg
		if x < -18 or x > w + 18:
			continue
		canvas.draw_line(Vector2(x, h * 0.55), Vector2(x, h), Color(0.5, 0.55, 0.7, 0.9), 1.0)
		if font:
			canvas.draw_string(font, Vector2(x - 7, h * 0.5), String(labels[deg]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 1.0))
	# Centre pointer (gold when we actually have a heading).
	var cx := w * 0.5
	var col := OBJ_COLOR if have else Color(0.6, 0.6, 0.7)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(cx - 6, 0), Vector2(cx + 6, 0), Vector2(cx, 9)]), col)

func _draw_arrow(canvas: Control, tip: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var a := tip
	var b := tip - dir * 12.0 + perp * 6.0
	var c := tip - dir * 12.0 - perp * 6.0
	canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), col)

# ── Objective / compass logic ─────────────────────────────────────────────────
# Returns { pos, label, color } for the thing the player should head toward, or
# {} if there's nothing to point at right now.
func _objective() -> Dictionary:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return {}
	# No compass yet → point at the Navigator so the player can find them.
	if not QuestManager.has_compass:
		var nav := scene.find_child("Navigator", true, false)
		if is_instance_valid(nav):
			return {"pos": nav.global_position, "label": "Find the Navigator", "color": NAV_COLOR}
		return {}
	if QuestManager.game_won:
		return {}
	# First major quest steps, in order.
	if not QuestManager.combat_tutorial_done:
		var mob := _tutorial_mob(scene)
		if is_instance_valid(mob):
			return {"pos": mob.global_position, "label": "Learn to fight", "color": OBJ_COLOR}
	if QuestManager.has_key and not QuestManager.chest_unlocked:
		var chest := scene.find_child("DeliveryPoint", true, false)
		if is_instance_valid(chest):
			return {"pos": chest.global_position, "label": "Open the ancient chest", "color": OBJ_COLOR}
	# Default hub: the Street Kid (accept quest, deliver coins, turn in relic…).
	var kid := scene.find_child("QuestNPC", true, false)
	if is_instance_valid(kid):
		var lbl := "Talk to the Street Kid"
		if QuestManager.has_relic:
			lbl = "Turn in the Relic"
		elif QuestManager.quest_accepted and not QuestManager.has_key:
			lbl = "Bring coins to the Street Kid"
		return {"pos": kid.global_position, "label": lbl, "color": OBJ_COLOR}
	return {}

func _tutorial_mob(scene: Node) -> Node:
	var chars := scene.find_child("Character", true, false)
	if not is_instance_valid(chars):
		return null
	for c in chars.get_children():
		if "is_tutorial_mob" in c and c.is_tutorial_mob and c.visible:
			return c
	return null

func _update_compass_bar() -> void:
	var obj := _objective()
	if obj.is_empty():
		_compass_text.text = "🧭  Explore…"
		return
	var player := _player_node()
	var arrow := "•"
	var dist_txt := ""
	if is_instance_valid(player):
		var d: Vector2 = obj["pos"] - player.global_position
		arrow = _dir_arrow(d)
		var m := int(d.length() / 12.0)   # rough "metres"
		dist_txt = "   ~%dm" % m if m > 4 else "   (arrived)"
	_compass_text.text = "%s  %s%s" % [arrow, obj["label"], dist_txt]

func _dir_arrow(d: Vector2) -> String:
	var a := rad_to_deg(atan2(d.y, d.x))
	if a < 0: a += 360.0
	var dirs := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return dirs[int(round(a / 45.0)) % 8]

# ── Helpers ───────────────────────────────────────────────────────────────────
func _explored_world_bounds(ppos: Vector2) -> Rect2:
	var has_any := false
	var min_c := Vector2(INF, INF)
	var max_c := Vector2(-INF, -INF)
	for key in QuestManager.explored_cells.keys():
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() != 2:
			continue
		var wx := float(int(parts[0])) * CELL
		var wy := float(int(parts[1])) * CELL
		if not _in_overworld(Vector2(wx + CELL * 0.5, wy + CELL * 0.5)):
			continue
		min_c.x = minf(min_c.x, wx); min_c.y = minf(min_c.y, wy)
		max_c.x = maxf(max_c.x, wx + CELL); max_c.y = maxf(max_c.y, wy + CELL)
		has_any = true
	# Always include the player position so their marker is on-map.
	min_c.x = minf(min_c.x, ppos.x - CELL); min_c.y = minf(min_c.y, ppos.y - CELL)
	max_c.x = maxf(max_c.x, ppos.x + CELL); max_c.y = maxf(max_c.y, ppos.y + CELL)
	if not has_any:
		return Rect2(ppos - Vector2(CELL, CELL), Vector2(CELL, CELL) * 2)
	return Rect2(min_c, max_c - min_c)

func _player_node() -> Node2D:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return null
	var p := scene.get_node_or_null("mainplayer")
	if is_instance_valid(p):
		return p as Node2D
	return scene.find_child("mainplayer", true, false) as Node2D

# Whether the map SYSTEM is reachable at all: compass unlocked, we're in the game
# (not the menu), and no higher-priority modal (dialogue / pause / end screen) is
# up. This still allows opening the map in combat / inside a house — where it will
# report "Map Unavailable" — so the M key never feels dead.
func _map_gate_ok() -> bool:
	if not QuestManager.has_compass:
		return false
	if not is_instance_valid(_player_node()):
		return false
	if is_instance_valid(DialogueManager) and DialogueManager.is_active:
		return false
	for n in ["LoseUI", "WinUI"]:
		var node := get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and node is CanvasItem and (node as CanvasItem).visible:
			return false
	var pause := get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause) and pause.has_method("is_open") and pause.is_open():
		return false
	return true

# Whether there's an actual map to show right now: on the overworld island, not in
# combat/fishing. House interiors and the combat arena sit OUTSIDE the island
# bounds, so the map is "unavailable" there even though it's technically still
# the overworld scene.
func _map_available() -> bool:
	if QuestManager.is_in_combat or QuestManager.is_fishing:
		return false
	var p := _player_node()
	return is_instance_valid(p) and _in_overworld(p.global_position)
