extends CharacterBody2D

# --- UI Signal ---
signal life_changed(new_life)

# --- Movement Variables ---
@export var max_speed: float = 150.0
@export var acceleration: float = 900.0
@export var friction: float = 1200.0
var life = 3

# --- Knockback Variables ---
var is_knocked_back: bool = false
@export var knockback_force: float = 300.0     
@export var knockback_duration: float = 0.25 

# --- Interactive Dash Variables ---
var is_dashing: bool = false
var can_dash: bool = true
var last_input_dir: Vector2 = Vector2.DOWN

@export var dash_speed: float = 400.0      
@export var dash_duration: float = 0.2     
@export var dash_cooldown: float = 1.0     

# Grabs a reference to your AnimatedSprite2D node
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# Broadcast the starting health right when the game loads
	life_changed.emit(life)

func _physics_process(delta: float) -> void:
	# ⚠️ FREEZE CONTROL: If we are fighting an enemy, lock inputs and stop moving!
	if QuestManager.is_in_combat:
		velocity = Vector2.ZERO
		move_and_slide()
		return
		
	# ... your existing movement code (Input.get_vector, move_and_slide, etc.) continues below ...
	var equipment_menu = get_tree().root.find_child("EquipmentMenu", true, false)
	if is_instance_valid(equipment_menu) and equipment_menu.visible:
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
		sprite.play("default")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		sprite.stop()
		
	move_and_slide()


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


# Handles the physics calculation locally without needing node paths
func apply_velocity_knockback() -> void:
	is_knocked_back = true
	var bounce_dir = -last_input_dir
	if bounce_dir == Vector2.ZERO:
		bounce_dir = Vector2.UP 
		
	velocity = bounce_dir * knockback_force
	
	await get_tree().create_timer(knockback_duration).timeout
	is_knocked_back = false
	
# --- Fixed Trigger Check ---
#func _on_deadzone_body_entered(body: Node2D) -> void:
	## Check if the body entering the deadzone is named exactly "mainplayer"
	#if body.name == "mainplayer":
		#if is_dashing:
			#return # Invulnerable while dashing
			#
		#life -= 1
		#life_changed.emit(life)
		#
		#if life <= 0:
			#get_tree().reload_current_scene()
		#else:
			#apply_velocity_knockback()
