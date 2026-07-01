extends CharacterBody2D

signal life_changed(new_life)

@export var max_speed: float = 85.0   # base overworld speed (sprint multiplies this)
@export var acceleration: float = 600.0
@export var friction: float = 900.0
var life = 3

var is_knocked_back: bool = false
@export var knockback_force: float = 300.0
@export var knockback_duration: float = 0.25

var last_input_dir: Vector2 = Vector2.UP

# ── Sprint (overworld only) ─────────────────────────────────────────────────
# Hold Sprint to move 30% faster with a 30% faster walk animation. A full
# stamina bar drains in SPRINT_MAX seconds; once emptied the player is
# "exhausted" and can't sprint again until the bar fully refills over
# SPRINT_RECHARGE_TIME seconds. Sprint is gated to the overworld — the combat
# guard at the top of _physics_process returns before any sprint logic runs.
const SPRINT_SPEED_MULT := 1.30
const SPRINT_ANIM_MULT := 1.30
const SPRINT_MAX := 3.0             # seconds of sprint on a full bar
const SPRINT_RECHARGE_TIME := 6.0   # seconds to refill from empty

var stamina: float = SPRINT_MAX
var is_sprinting: bool = false
var sprint_exhausted: bool = false

# Stamina bar drawn under the player (built in code, follows the player).
# Styled to match the rest of the UI: dark rounded panel + border, like the
# HUD stat panels / pop-ups, with a themed fill (green → gold when low → red
# when exhausted).
const STAMINA_BAR_SIZE := Vector2(38, 6)
@export var stamina_bar_offset: Vector2 = Vector2(0, 22)
const BAR_BG_COL       := Color(0.08, 0.09, 0.13, 0.92)   # COL_PANEL family
const BAR_BORDER_COL   := Color(0.30, 0.35, 0.55, 1.0)    # COL_BORDER family
const BAR_FILL_FULL    := Color(0.32, 0.85, 0.45, 1.0)    # COL_GREEN family
const BAR_FILL_LOW     := Color(1.00, 0.80, 0.28, 1.0)    # COL_GOLD family
const BAR_FILL_EMPTY   := Color(0.90, 0.34, 0.28, 1.0)    # exhausted red
var _stamina_bar_bg: Panel = null
var _stamina_bar_fill: Panel = null
var _stamina_fill_style: StyleBoxFlat = null

# Distance to stop short of the target when lunging — keeps the characters
# standing next to each other instead of overlapping or stopping halfway.
# Lowered from 70 -> 28 so both fighters actually close the gap and end up
# standing right next to each other instead of stopping far apart.
const ATTACK_REACH := 28.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	life_changed.emit(life)
	_build_stamina_bar()

func _process(_delta: float) -> void:
	# Bar visibility/fill is updated here (not in _physics_process) so it still
	# hides correctly while combat has the physics step returning early.
	_update_stamina_bar()

func _physics_process(delta: float) -> void:
	if QuestManager.is_in_combat:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var equipment_menu = get_tree().root.find_child("EquipmentMenu", true, false)
	if is_instance_valid(equipment_menu) and equipment_menu.visible:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var save_popup = get_tree().root.find_child("SavePopup", true, false)
	if is_instance_valid(save_popup) and save_popup.visible:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_knocked_back:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		last_input_dir = input_dir.normalized()

	_update_sprint(input_dir, delta)

	if input_dir != Vector2.ZERO:
		var target_speed = max_speed * (SPRINT_SPEED_MULT if is_sprinting else 1.0)
		velocity = velocity.move_toward(input_dir * target_speed, acceleration * delta)
		_play_walk_animation(input_dir)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		# Hold the last facing direction's idle frame instead of always
		# snapping to "default" (which is the down-facing pose). This is what
		# was causing the character to always look down on release no matter
		# which way they were last walking.
		_set_idle_facing(last_input_dir)

	move_and_slide()

# ── Facing ────────────────────────────────────────────────────────────────────

# Freeze on frame 2 of the animation matching `dir`, without resetting modulate
# or losing the direction. speed_scale = 0 freezes without using pause()
# (AnimatedSprite2D has no pause() method in Godot 4). Frame 2 is used as the
# idle pose for every walking direction (matches the confirmed best idle
# frame in the sprite sheet) instead of frame 0.
func _set_idle_facing(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		sprite.flip_h = false
		sprite.play("default")
		sprite.frame = 0
	elif abs(dir.x) >= abs(dir.y):
		sprite.flip_h = dir.x < 0
		sprite.play("WalkSide")
		sprite.frame = 2
	elif dir.y < 0:
		sprite.flip_h = false
		sprite.play("WalkUp")
		sprite.frame = 2
	else:
		sprite.flip_h = false
		sprite.play("WalkDown")
		sprite.frame = 2
	sprite.speed_scale = 0.0

func face_up() -> void:
	last_input_dir = Vector2.UP
	sprite.flip_h = false
	sprite.speed_scale = 1.0
	sprite.stop()
	sprite.animation = "WalkUp"
	sprite.frame = 0

# Combat idle: freeze on frame 2 of WalkSide.
func face_right() -> void:
	last_input_dir = Vector2.RIGHT
	sprite.flip_h  = false      # WalkSide natural dir = right
	sprite.play("WalkSide")
	sprite.frame   = 2          # best idle combat frame
	sprite.speed_scale = 0.0    # freeze without resetting frame

func _play_walk_animation(dir: Vector2) -> void:
	# Un-freeze (in case we were idle/combat-frozen); sprint speeds the anim +30%.
	sprite.speed_scale = SPRINT_ANIM_MULT if is_sprinting else 1.0
	if abs(dir.x) >= abs(dir.y):
		sprite.flip_h = dir.x < 0
		sprite.play("WalkSide")
	elif dir.y < 0:
		sprite.flip_h = false
		sprite.play("WalkUp")
	else:
		sprite.flip_h = false
		sprite.play("WalkDown")

# ── Player attack lunge ───────────────────────────────────────────────────────
func do_attack_lunge(enemy_pos: Vector2, enemy_node: Node2D = null, is_disarmed: bool = false) -> void:
	var start_pos       = global_position
	var enemy_start_pos = enemy_node.global_position if is_instance_valid(enemy_node) else enemy_pos

	# Lunge to within ATTACK_REACH of the enemy — not a percentage of the gap.
	# This way the player always ends up standing right next to the enemy
	# regardless of how far apart the combat markers are.
	var to_enemy   = enemy_pos - start_pos
	var total_dist = to_enemy.length()
	var travel_dist = max(total_dist - ATTACK_REACH, 0.0)
	var lunge_target = start_pos + (to_enemy.normalized() * travel_dist if total_dist > 0.001 else Vector2.ZERO)

	if is_disarmed:
		await _shake_node(self, start_pos, 0.32)
		face_right()
		return

	sprite.flip_h = false
	sprite.speed_scale = 1.0
	sprite.play("AttackSide")

	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", lunge_target, 0.18)
	await tw.finished

	var elapsed := 0.0
	while elapsed < 0.32:
		global_position = lunge_target + Vector2(randf_range(-5, 5), randf_range(-4, 4))
		if is_instance_valid(enemy_node):
			enemy_node.global_position = enemy_start_pos + Vector2(randf_range(-4, 4), randf_range(-3, 3))
		await get_tree().create_timer(0.04).timeout
		elapsed += 0.04

	global_position = lunge_target
	if is_instance_valid(enemy_node):
		enemy_node.global_position = enemy_start_pos

	await get_tree().create_timer(0.20).timeout

	var tw2 = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw2.tween_property(self, "global_position", start_pos, 0.15)
	await tw2.finished

	# Return to frozen combat idle pose
	face_right()

# ── Enemy lunge ───────────────────────────────────────────────────────────────
func do_enemy_lunge(enemy_node: Node2D, player_pos: Vector2, is_disarmed: bool = false) -> void:
	if not is_instance_valid(enemy_node): return
	var enemy_start_pos  = enemy_node.global_position
	var player_start_pos = global_position

	if is_disarmed:
		await _shake_node(enemy_node, enemy_start_pos, 0.32)
		return

	# Same fixed-reach logic as the player lunge, mirrored: enemy walks to
	# within ATTACK_REACH of the player instead of stopping at a percentage.
	var to_player   = player_pos - enemy_start_pos
	var total_dist  = to_player.length()
	var travel_dist = max(total_dist - ATTACK_REACH, 0.0)
	var lunge_target = enemy_start_pos + (to_player.normalized() * travel_dist if total_dist > 0.001 else Vector2.ZERO)

	var espr = enemy_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(espr):
		espr.flip_h = true

	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(enemy_node, "global_position", lunge_target, 0.20)
	await tw.finished

	var elapsed := 0.0
	while elapsed < 0.32:
		enemy_node.global_position = lunge_target + Vector2(randf_range(-5, 5), randf_range(-4, 4))
		global_position = player_start_pos + Vector2(randf_range(-3, 3), randf_range(-2, 2))
		await get_tree().create_timer(0.04).timeout
		elapsed += 0.04

	enemy_node.global_position = lunge_target
	global_position = player_start_pos

	await get_tree().create_timer(0.15).timeout

	var tw2 = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw2.tween_property(enemy_node, "global_position", enemy_start_pos, 0.15)
	await tw2.finished

	if is_instance_valid(espr):
		espr.flip_h = true

	face_right()

# ── Utility ───────────────────────────────────────────────────────────────────
func _shake_node(node: Node2D, origin: Vector2, duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		node.global_position = origin + Vector2(randf_range(-5, 5), randf_range(-4, 4))
		await get_tree().create_timer(0.04).timeout
		elapsed += 0.04
	node.global_position = origin

# ── Sprint helpers ─────────────────────────────────────────────────────────────
func _update_sprint(input_dir: Vector2, delta: float) -> void:
	var wants_sprint = Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO and not sprint_exhausted and stamina > 0.0
	if wants_sprint:
		is_sprinting = true
		stamina = maxf(0.0, stamina - delta)          # full bar drains in SPRINT_MAX secs
		if stamina <= 0.0:
			is_sprinting = false
			sprint_exhausted = true                    # locked out until fully refilled
	else:
		is_sprinting = false
		stamina = minf(SPRINT_MAX, stamina + (SPRINT_MAX / SPRINT_RECHARGE_TIME) * delta)
		if sprint_exhausted and stamina >= SPRINT_MAX:
			sprint_exhausted = false

func _build_stamina_bar() -> void:
	_stamina_bar_bg = Panel.new()
	_stamina_bar_bg.size = STAMINA_BAR_SIZE
	_stamina_bar_bg.position = stamina_bar_offset - Vector2(STAMINA_BAR_SIZE.x * 0.5, 0.0)
	_stamina_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bar_bg.z_index = 50
	_stamina_bar_bg.visible = false
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG_COL
	bg_style.set_corner_radius_all(3)
	bg_style.set_border_width_all(1)
	bg_style.border_color = BAR_BORDER_COL
	_stamina_bar_bg.add_theme_stylebox_override("panel", bg_style)
	add_child(_stamina_bar_bg)

	# Fill is a child Panel (inset 1px) so it inherits position/visibility and
	# gets its own rounded stylebox that we recolor as stamina changes.
	_stamina_bar_fill = Panel.new()
	_stamina_bar_fill.position = Vector2(1, 1)
	_stamina_bar_fill.size = STAMINA_BAR_SIZE - Vector2(2, 2)
	_stamina_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_fill_style = StyleBoxFlat.new()
	_stamina_fill_style.bg_color = BAR_FILL_FULL
	_stamina_fill_style.set_corner_radius_all(2)
	_stamina_bar_fill.add_theme_stylebox_override("panel", _stamina_fill_style)
	_stamina_bar_bg.add_child(_stamina_bar_fill)

func _update_stamina_bar() -> void:
	if not is_instance_valid(_stamina_bar_bg): return
	# Only show in the overworld, and only when it matters (sprinting or refilling).
	var show_bar = not QuestManager.is_in_combat and (is_sprinting or stamina < SPRINT_MAX)
	_stamina_bar_bg.visible = show_bar
	if not show_bar: return
	var pct = clampf(stamina / SPRINT_MAX, 0.0, 1.0)
	var inner_w = STAMINA_BAR_SIZE.x - 2.0
	_stamina_bar_fill.size = Vector2(maxf(0.0, inner_w * pct), STAMINA_BAR_SIZE.y - 2.0)
	if sprint_exhausted:   _stamina_fill_style.bg_color = BAR_FILL_EMPTY
	elif pct < 0.34:       _stamina_fill_style.bg_color = BAR_FILL_LOW
	else:                  _stamina_fill_style.bg_color = BAR_FILL_FULL

func apply_velocity_knockback() -> void:
	is_knocked_back = true
	var bounce_dir = -last_input_dir
	if bounce_dir == Vector2.ZERO:
		bounce_dir = Vector2.UP
	velocity = bounce_dir * knockback_force
	await get_tree().create_timer(knockback_duration).timeout
	is_knocked_back = false
