extends CanvasLayer

# ── Fishing minigame (Stardew-style) ─────────────────────────────────────────
# A vertical "tank": the player raises a green catch-bar by HOLDING interact
# (gravity pulls it down when released) and tries to keep the bar over a bobbing
# fish. While the fish is inside the bar the catch meter fills; when it slips out
# the meter drains. Fill to full → caught. Drain to empty → it got away.
#
# Fully procedural (emoji + coloured rects, no art). Instanced by the fisherman:
#     var mg = preload("res://FishingMinigame.gd").new()
#     mg.difficulty = 1.0
#     get_tree().current_scene.add_child(mg)
#     mg.finished.connect(_on_fish_result)
# Emits `finished(success)` then frees itself.

signal finished(success: bool)

# Difficulty scales fish speed and how often it darts. 1.0 = normal.
var difficulty: float = 1.0

const TANK_H := 360.0
const TANK_W := 96.0
const BAR_FRAC := 0.24          # catch-bar height as a fraction of the tank
const GRAVITY := -1.7           # normalized units / s^2 while not lifting
const LIFT := 3.3               # upward accel while holding interact
const MAX_VEL := 1.7
const BOUNCE := -0.35
const GAIN := 0.42              # meter fill rate while on the fish
const LOSS := 0.34              # meter drain rate while off the fish

var _bar_pos := 0.08            # bottom edge of the catch bar, 0..(1-BAR_FRAC)
var _bar_vel := 0.0
var _fish_pos := 0.5
var _fish_target := 0.5
var _fish_retarget := 0.6
var _progress := 0.35
var _ended := false

var _tank: Control
var _water: Panel
var _bar: Panel
var _fish: Label
var _prog_fill: ColorRect
var _result: Label

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	QuestManager.is_fishing = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var title := Label.new()
	title.text = "🎣  Reel it in!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
	col.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)

	# The tank (water column) with the catch bar + fish as absolute children.
	_tank = Control.new()
	_tank.custom_minimum_size = Vector2(TANK_W, TANK_H)
	row.add_child(_tank)

	_water = Panel.new()
	_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color(0.08, 0.20, 0.34, 1.0)
	ws.set_corner_radius_all(10)
	ws.set_border_width_all(3)
	ws.border_color = Color(0.25, 0.45, 0.65)
	_water.add_theme_stylebox_override("panel", ws)
	_tank.add_child(_water)

	_bar = Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.30, 0.85, 0.40, 0.45)
	bs.set_corner_radius_all(6)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.45, 1.0, 0.55, 0.9)
	_bar.add_theme_stylebox_override("panel", bs)
	_tank.add_child(_bar)

	_fish = Label.new()
	_fish.text = "🐟"
	_fish.add_theme_font_size_override("font_size", 30)
	_tank.add_child(_fish)

	# Catch meter (vertical) to the right.
	var meter := Panel.new()
	meter.custom_minimum_size = Vector2(24, TANK_H)
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	ms.set_corner_radius_all(6)
	meter.add_theme_stylebox_override("panel", ms)
	row.add_child(meter)
	_prog_fill = ColorRect.new()
	_prog_fill.color = Color(0.35, 0.85, 0.45)
	meter.add_child(_prog_fill)

	var help := Label.new()
	help.text = "Hold  [E]  to raise the bar — keep it on the fish"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	col.add_child(help)

	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 22)
	_result.visible = false
	col.add_child(_result)

	_layout()

func _process(delta: float) -> void:
	if _ended:
		return

	# ── Catch bar physics ──
	var lifting := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept")
	_bar_vel += (LIFT if lifting else GRAVITY) * delta
	_bar_vel = clamp(_bar_vel, -MAX_VEL, MAX_VEL)
	_bar_pos += _bar_vel * delta
	var bar_max := 1.0 - BAR_FRAC
	if _bar_pos < 0.0:
		_bar_pos = 0.0
		_bar_vel *= BOUNCE
	elif _bar_pos > bar_max:
		_bar_pos = bar_max
		_bar_vel *= BOUNCE

	# ── Fish movement: drift toward a target, re-pick target periodically ──
	_fish_retarget -= delta
	if _fish_retarget <= 0.0:
		_fish_target = randf()
		_fish_retarget = randf_range(0.35, 1.0) / difficulty
	var fish_speed := 1.7 * difficulty
	_fish_pos = move_toward(_fish_pos, _fish_target, fish_speed * delta)

	# ── Meter ──
	var on_fish: bool = _fish_pos >= _bar_pos and _fish_pos <= _bar_pos + BAR_FRAC
	_progress += (GAIN if on_fish else -LOSS) * delta
	_progress = clamp(_progress, 0.0, 1.0)

	_layout()

	if _progress >= 1.0:
		_finish(true)
	elif _progress <= 0.0:
		_finish(false)

func _layout() -> void:
	# Catch bar rect within the tank (y grows downward, position is bottom-anchored).
	var bar_h := TANK_H * BAR_FRAC
	var bar_top := TANK_H * (1.0 - (_bar_pos + BAR_FRAC))
	_bar.position = Vector2(4, bar_top)
	_bar.size = Vector2(TANK_W - 8, bar_h)
	# Fish centered on its position.
	_fish.reset_size()
	_fish.position = Vector2((TANK_W - _fish.size.x) * 0.5, TANK_H * (1.0 - _fish_pos) - _fish.size.y * 0.5)
	# Meter fill from the bottom.
	var fh := TANK_H * _progress
	_prog_fill.position = Vector2(0, TANK_H - fh)
	_prog_fill.size = Vector2(24, fh)
	_prog_fill.color = Color(0.85, 0.55, 0.30).lerp(Color(0.35, 0.85, 0.45), _progress)

func _finish(success: bool) -> void:
	if _ended:
		return
	_ended = true
	_result.visible = true
	if success:
		_result.text = "✅  Caught it!"
		_result.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	else:
		_result.text = "…it got away."
		_result.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	await get_tree().create_timer(1.1).timeout
	QuestManager.is_fishing = false
	finished.emit(success)
	queue_free()
