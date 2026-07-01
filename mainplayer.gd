extends CharacterBody2D

signal life_changed(new_life)

@export var max_speed: float = 100.0
@export var acceleration: float = 600.0
@export var friction: float = 900.0
var life = 3

var is_knocked_back: bool = false
@export var knockback_force: float = 300.0
@export var knockback_duration: float = 0.25

var is_dashing: bool = false
var can_dash: bool = true
var last_input_dir: Vector2 = Vector2.UP

@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0

# Distance to stop short of the target when lunging — keeps the characters
# standing next to each other instead of overlapping or stopping halfway.
# Lowered from 70 -> 28 so both fighters actually close the gap and end up
# standing right next to each other instead of stopping far apart.
const ATTACK_REACH := 28.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	life_changed.emit(life)

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

	if is_dashing:
		move_and_slide()
		return

	if is_knocked_back:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		last_input_dir = input_dir.normalized()

	if Input.is_action_just_pressed("dash") and can_dash:
		execute_dash()
		return

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
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
	sprite.speed_scale = 1.0   # un-freeze in case we were idle/combat-frozen
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

func execute_dash() -> void:
	can_dash = false
	is_dashing = true
	velocity = last_input_dir * dash_speed
	sprite.modulate.a = 0.5
	await get_tree().create_timer(dash_duration).timeout
	is_dashing = false
	sprite.modulate.a = 1.0
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

func apply_velocity_knockback() -> void:
	is_knocked_back = true
	var bounce_dir = -last_input_dir
	if bounce_dir == Vector2.ZERO:
		bounce_dir = Vector2.UP
	velocity = bounce_dir * knockback_force
	await get_tree().create_timer(knockback_duration).timeout
	is_knocked_back = false
