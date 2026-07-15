extends CanvasLayer

# ── Fishing minigame (Stardew-style) ─────────────────────────────────────────
# A vertical "tank": the player raises a green catch-bar by HOLDING interact
# (gravity pulls it down when released) and tries to keep the bar over a bobbing
# fish. While the fish is inside the bar the catch meter fills; when it slips out
# the meter drains. Fill to full → caught; drain to empty → it got away.
#
# The fish has a hidden TIER (see SIZES) that only changes how fast/erratically it
# moves and how fast the meter leaks — the player never sees it, they just feel the
# difficulty. A bigger fish is worth far more XP (revealed only after the catch).
#
# Instanced by the fishing spot:
#     var mg = preload("res://FishingMinigame.gd").new()
#     mg.difficulty = 1.0
#     get_tree().current_scene.add_child(mg)
#     mg.finished.connect(_on_fish_result)
# Emits `finished(success, size_name, xp_mult)` then frees itself.

signal finished(success: bool, size_name: String, xp_mult: float)

# Extra difficulty from the fisherman (nudges fish speed up as the player levels).
var difficulty: float = 1.0

const TANK_H := 460.0
const TANK_W := 96.0
const BAR_FRAC := 0.26           # catch-bar height as a fraction of the tank
const GRAVITY := -1.05           # normalized units / s^2 while not lifting
const LIFT := 2.0                # upward accel while holding interact
const MAX_VEL := 1.15
const BOUNCE := -0.30
const GAIN := 0.55               # meter fill rate while on the fish
const LOSS := 0.22               # meter drain rate while off the fish
const START_PROGRESS := 0.45     # meter starts a touch under half
# Reaction window right after the countdown: the meter can FILL but never drain
# for this long, so a fast fish can't end the round before you've touched a key.
const GRACE := 0.8
# Keeps the fish off the very edges so it never clips the tank border.
const FISH_MIN := 0.07
const FISH_MAX := 0.93
const FISH_PX := 30.0            # constant on-screen size: never reveals the tier

# Hidden fish tiers — FIFTEEN rungs, so difficulty and reward spread right out.
# The early rungs are relaxed; the middle takes focus; the top ones are fast,
# twitchy and leak the meter hard — rare trophies worth many times a tiddler.
#   speed      — how fast it chases its target
#   rt_min/max — how often it re-targets (lower = twitchier)
#   xp         — XP multiplier (revealed only after the catch)
#   drain      — meter drain multiplier while off the fish (harder = leakier)
#   weight     — relative spawn weight (chance = weight / sum of all weights)
# Tier keys must match the fish_<tier> ids in IconDB and _lead_for in FishingSpot.
const SIZES := {
	"tiny":      { "speed": 0.42, "rt_min": 0.90, "rt_max": 1.75, "xp": 0.5,  "drain": 0.75, "weight": 10 },
	"minnow":    { "speed": 0.50, "rt_min": 0.85, "rt_max": 1.62, "xp": 0.8,  "drain": 0.80, "weight": 10 },
	"small":     { "speed": 0.58, "rt_min": 0.78, "rt_max": 1.50, "xp": 1.0,  "drain": 0.85, "weight": 10 },
	"modest":    { "speed": 0.68, "rt_min": 0.72, "rt_max": 1.38, "xp": 1.4,  "drain": 0.92, "weight": 10 },
	"medium":    { "speed": 0.78, "rt_min": 0.66, "rt_max": 1.26, "xp": 1.8,  "drain": 1.00, "weight": 10 },
	"good":      { "speed": 0.88, "rt_min": 0.60, "rt_max": 1.15, "xp": 2.3,  "drain": 1.06, "weight": 10 },
	"large":     { "speed": 1.00, "rt_min": 0.55, "rt_max": 1.05, "xp": 2.8,  "drain": 1.12, "weight": 9  },
	"big":       { "speed": 1.12, "rt_min": 0.50, "rt_max": 0.96, "xp": 3.4,  "drain": 1.20, "weight": 9  },
	"huge":      { "speed": 1.25, "rt_min": 0.45, "rt_max": 0.88, "xp": 4.0,  "drain": 1.28, "weight": 9  },
	"giant":     { "speed": 1.40, "rt_min": 0.41, "rt_max": 0.80, "xp": 5.5,  "drain": 1.36, "weight": 8  },
	"massive":   { "speed": 1.55, "rt_min": 0.37, "rt_max": 0.73, "xp": 6.5,  "drain": 1.44, "weight": 8  },
	"trophy":    { "speed": 1.70, "rt_min": 0.34, "rt_max": 0.67, "xp": 8.0,  "drain": 1.52, "weight": 6  },
	"exotic":    { "speed": 1.85, "rt_min": 0.31, "rt_max": 0.62, "xp": 9.5,  "drain": 1.60, "weight": 6  },
	"rare":      { "speed": 2.00, "rt_min": 0.28, "rt_max": 0.57, "xp": 11.0, "drain": 1.68, "weight": 5  },
	"legendary": { "speed": 2.20, "rt_min": 0.25, "rt_max": 0.52, "xp": 14.0, "drain": 1.78, "weight": 4  },
}

# The bar starts at the tank floor and the fish bolts immediately — otherwise you
# could just park the bar mid-tank from frame one and win before the fish moved.
# GRACE (no drain, see _process) is what buys the reaction time instead.
var _bar_pos := 0.08             # bottom edge of the catch bar, 0..(1-BAR_FRAC)
var _bar_vel := 0.0
var _fish_pos := 0.5
var _fish_target := 0.5
var _fish_retarget := 0.6
var _progress := START_PROGRESS
var _grace := GRACE
var _ended := false

var _size_name := "small"
var _fish_speed := 0.6
var _rt_min := 0.7
var _rt_max := 1.4
var _xp_mult := 1.0
var _loss := LOSS

var _tank: Control
var _bar: Panel
var _fish: Control
var _prog_fill: ColorRect
var _result: Label

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	QuestManager.is_fishing = true
	_pick_size()

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

	_tank = Control.new()
	_tank.custom_minimum_size = Vector2(TANK_W, TANK_H)
	row.add_child(_tank)

	var water := Panel.new()
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color(0.08, 0.20, 0.34, 1.0)
	ws.set_corner_radius_all(10)
	ws.set_border_width_all(3)
	ws.border_color = Color(0.25, 0.45, 0.65)
	water.add_theme_stylebox_override("panel", ws)
	_tank.add_child(water)

	_bar = Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.30, 0.85, 0.40, 0.45)
	bs.set_corner_radius_all(6)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.45, 1.0, 0.55, 0.9)
	_bar.add_theme_stylebox_override("panel", bs)
	_tank.add_child(_bar)

	# Always the same fish art at the same size — it must never hint at the tier.
	var ftex := IconDB.tex("fish_hooked")
	if ftex:
		var fr := TextureRect.new()
		fr.texture = ftex
		fr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fr.custom_minimum_size = Vector2(FISH_PX, FISH_PX)
		fr.size = Vector2(FISH_PX, FISH_PX)
		_fish = fr
	else:
		var fl := Label.new()
		fl.text = "🐟"
		fl.add_theme_font_size_override("font_size", 30)
		_fish = fl
	_tank.add_child(_fish)

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
	help.text = "Hold  [%s]  to raise the bar — keep it on the fish" % KeybindManager.key_display("fish_reel")
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

func _pick_size() -> void:
	var total := 0
	for k in SIZES:
		total += int(SIZES[k]["weight"])
	var roll := randi() % total
	var acc := 0
	for k in SIZES:
		acc += int(SIZES[k]["weight"])
		if roll < acc:
			_size_name = k
			break
	var s: Dictionary = SIZES[_size_name]
	_fish_speed = float(s["speed"]) * (1.0 + max(0.0, difficulty - 1.0))
	_rt_min = float(s["rt_min"])
	_rt_max = float(s["rt_max"])
	_xp_mult = float(s["xp"])
	_loss = LOSS * float(s.get("drain", 1.0))
	_fish_retarget = randf_range(_rt_min, _rt_max)
	# Pick a real target up front so the fish bolts on the FIRST frame. Leaving it
	# parked on its spawn point handed the player a free head start.
	_fish_target = randf_range(FISH_MIN, FISH_MAX)

func _process(delta: float) -> void:
	if _ended:
		return

	var lifting := Input.is_action_pressed("fish_reel")
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

	_fish_retarget -= delta
	if _fish_retarget <= 0.0:
		_fish_target = randf_range(FISH_MIN, FISH_MAX)   # stays off the tank edges
		_fish_retarget = randf_range(_rt_min, _rt_max)
	_fish_pos = move_toward(_fish_pos, _fish_target, _fish_speed * delta)

	if _grace > 0.0:
		_grace -= delta
	var on_fish: bool = _fish_pos >= _bar_pos and _fish_pos <= _bar_pos + BAR_FRAC
	if on_fish:
		_progress += GAIN * delta
	elif _grace <= 0.0:
		_progress -= _loss * delta   # no bleeding during the reaction window
	_progress = clamp(_progress, 0.0, 1.0)

	_layout()

	if _progress >= 1.0:
		_finish(true)
	elif _progress <= 0.0:
		_finish(false)

func _layout() -> void:
	var bar_h := TANK_H * BAR_FRAC
	var bar_top := TANK_H * (1.0 - (_bar_pos + BAR_FRAC))
	_bar.position = Vector2(4, bar_top)
	_bar.size = Vector2(TANK_W - 8, bar_h)
	if _fish is Label:
		_fish.reset_size()
	var fs: Vector2 = _fish.size
	# Clamp inside the tank's 3px border so the fish never pokes out of the box.
	var fy: float = clampf(TANK_H * (1.0 - _fish_pos) - fs.y * 0.5, 4.0, TANK_H - fs.y - 4.0)
	_fish.position = Vector2((TANK_W - fs.x) * 0.5, fy)
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
	await get_tree().create_timer(1.0).timeout
	QuestManager.is_fishing = false
	finished.emit(success, _size_name, _xp_mult)
	queue_free()
