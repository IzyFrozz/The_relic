extends CharacterBody2D

signal life_changed(new_life)

@export var max_speed: float = 150.0
@export var acceleration: float = 900.0
@export var friction: float = 1200.0
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
		sprite.stop()
		sprite.animation = "default"

	move_and_slide()

func face_up() -> void:
	last_input_dir = Vector2.UP
	sprite.flip_h = false
	sprite.stop()
	sprite.animation = "default"
	sprite.frame = 0

func _play_walk_animation(dir: Vector2) -> void:
	if abs(dir.x) >= abs(dir.y):
		sprite.flip_h = dir.x < 0
		sprite.play("WalkSide")
	elif dir.y < 0:
		sprite.flip_h = false
		sprite.play("WalkUp")
	else:
		sprite.flip_h = false
		sprite.play("WalkDown")

# Called by CombatUI after confirm
# enemy_node is passed so we can shake it too
func do_attack_lunge(enemy_pos: Vector2, enemy_node: Node2D = null) -> void:
	var start_pos = global_position
	var lunge_target = start_pos.lerp(enemy_pos, 0.45)

	# Face up and play attack animation once
	sprite.flip_h = false
	sprite.play("AttackUp")

	# Lunge toward enemy
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", lunge_target, 0.18)
	await tween.finished

	# Shake player AND enemy simultaneously
	var shake_time = 0.32
	var elapsed = 0.0
	var enemy_start_pos = enemy_node.global_position if is_instance_valid(enemy_node) else Vector2.ZERO
	while elapsed < shake_time:
		var offset = Vector2(randf_range(-5, 5), randf_range(-4, 4))
		global_position = lunge_target + offset
		if is_instance_valid(enemy_node):
			enemy_node.global_position = enemy_start_pos + Vector2(randf_range(-4, 4), randf_range(-3, 3))
		await get_tree().create_timer(0.04).timeout
		elapsed += 0.04

	# Snap both back to exact positions
	global_position = lunge_target
	if is_instance_valid(enemy_node):
		enemy_node.global_position = enemy_start_pos

	# Wait for rest of attack animation
	await get_tree().create_timer(0.25).timeout

	# Return to start — still facing up (WalkUp frame 0)
	var tween2 = create_tween()
	tween2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween2.tween_property(self, "global_position", start_pos, 0.15)
	await tween2.finished

	# Stay facing up after lunge completes
	sprite.flip_h = false
	sprite.stop()
	sprite.animation = "default"
	sprite.frame = 0
	last_input_dir = Vector2.UP

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
