extends CharacterBody2D

const PlayerSkin = preload("res://PlayerSkin.gd")

signal life_changed(new_life)

var _skin_mat: ShaderMaterial = null

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
var _step_timer: float = 0.0   # counts down to the next footstep while walking
var _bump_cooldown: float = 0.0 # rate-limits the wall-bump thud
var sprint_exhausted: bool = false

# Stamina STATE ICON under the player (built in code, follows the player). Rather
# than a fill bar, a single icon swaps colour by state: green (fine) → yellow
# (running low) → red (exhausted). Icons come from IconDB (stamina_full/low/empty).
@export var stamina_bar_offset: Vector2 = Vector2(0, 20)
var _stamina_icon: Sprite2D = null
var _stamina_state: String = ""   # last-applied icon id, to avoid re-setting the texture

# Distance to stop short of the target when lunging — keeps the characters
# standing next to each other instead of overlapping or stopping halfway.
# Lowered from 70 -> 28 so both fighters actually close the gap and end up
# standing right next to each other instead of stopping far apart.
const ATTACK_REACH := 28.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	life_changed.emit(life)
	_build_stamina_bar()
	# Apply the character-creation body stretch (one sprite, tweaked proportions).
	sprite.scale *= Vector2(QuestManager.player_scale_x, QuestManager.player_scale_y)
	# Apply the chosen Hair / Shirt / Pants / Shoes / Skin colours via the
	# mask-driven palette-swap shader.
	_skin_mat = PlayerSkin.make_material(QuestManager.hair_color, QuestManager.shirt_color, QuestManager.pants_color, QuestManager.shoes_color, QuestManager.skin_color)
	sprite.material = _skin_mat

func _process(delta: float) -> void:
	# Bar visibility/fill is updated here (not in _physics_process) so it still
	# hides correctly while combat has the physics step returning early.
	_update_stamina_bar()
	_recharge_stamina(delta)
	# Safety net: a status tint (poison green, curse purple, …) is only ever valid
	# during a fight. If combat ended by ANY route — win, death, flee, scene reload
	# — clear it here so the tint can't follow the player into the overworld.
	if not QuestManager.is_in_combat and is_instance_valid(sprite) \
			and not sprite.modulate.is_equal_approx(Color.WHITE):
		sprite.modulate = Color.WHITE
	# Disable the recolor while a combat FX tints the sprite (modulate ≠ white)
	# so the FX plays on the base colours, then snap back to the customization.
	if is_instance_valid(_skin_mat):
		var is_white = sprite.modulate.is_equal_approx(Color.WHITE)
		_skin_mat.set_shader_parameter("recolor_on", 1.0 if is_white else 0.0)

func _physics_process(delta: float) -> void:
	if QuestManager.is_in_combat or QuestManager.is_fishing:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if DialogueManager.is_active:
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
		_tick_footsteps(delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_reset_footsteps()
		# Hold the last facing direction's idle frame instead of always
		# snapping to "default" (which is the down-facing pose). This is what
		# was causing the character to always look down on release no matter
		# which way they were last walking.
		_set_idle_facing(last_input_dir)

	move_and_slide()

	# Walked into something solid: pushing toward it but barely moving. Rate-limited
	# so it thuds once instead of buzzing every frame against the wall.
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	if input_dir != Vector2.ZERO and get_slide_collision_count() > 0 \
			and velocity.length() < max_speed * 0.25 and _bump_cooldown <= 0.0:
		SFX.play(SFX.bump, -6.0)
		_bump_cooldown = 0.45

# ── Facing ────────────────────────────────────────────────────────────────────

# Play the idle animation matching the last facing direction (`default` is the
# down-facing idle, plus IdleSide / IdleUp). Falls back to the old behaviour —
# freezing on frame 2 of the matching Walk animation — if the Idle animations
# haven't been added to this AnimatedSprite2D's frames yet, so the scene can
# be saved from the editor at any time without breaking movement.
func _set_idle_facing(dir: Vector2) -> void:
	var frames := sprite.sprite_frames
	var has_idles: bool = frames != null and frames.has_animation("IdleSide") and frames.has_animation("IdleUp")
	if has_idles:
		sprite.speed_scale = 1.0
		if dir != Vector2.ZERO and abs(dir.x) >= abs(dir.y):
			sprite.flip_h = dir.x < 0
			_play_if_changed("IdleSide")
		elif dir != Vector2.ZERO and dir.y < 0:
			sprite.flip_h = false
			_play_if_changed("IdleUp")
		else:
			# Down (and the "no direction yet" spawn case) both use `default`,
			# which holds the down-facing idle frames.
			sprite.flip_h = false
			_play_if_changed("default")
		return
	# Fallback: freeze on frame 2 of the matching Walk animation.
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

# play() only when switching animations so the idle loop isn't restarted every
# physics frame while the player stands still.
func _play_if_changed(anim: StringName) -> void:
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)

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
	if not is_disarmed:
		SFX.play(SFX.player_attack)
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
# Stamina REFILLS from _process rather than _physics_process, because the physics
# step returns early whenever a popup is up (wizard save, loadout, dialogue) — so
# the bar used to sit frozen while you read a menu. A real pause sets
# Engine.time_scale = 0, which makes delta 0, so a genuinely paused game still
# doesn't refill. Combat and fishing block it explicitly.
func _recharge_stamina(delta: float) -> void:
	if QuestManager.is_in_combat or QuestManager.is_fishing:
		return
	# A popup opening mid-sprint would otherwise leave is_sprinting stuck true and
	# stall the refill, since _physics_process (which clears it) never runs.
	if _ui_blocks_movement():
		is_sprinting = false
	if is_sprinting:
		return                       # draining, not refilling
	stamina = minf(SPRINT_MAX, stamina + (SPRINT_MAX / SPRINT_RECHARGE_TIME) * delta)
	if sprint_exhausted and stamina >= SPRINT_MAX:
		sprint_exhausted = false

# True while a menu/popup owns the screen and the player shouldn't be walking.
func _ui_blocks_movement() -> bool:
	if DialogueManager.is_active:
		return true
	for n in ["EquipmentMenu", "SavePopup"]:
		var node = get_tree().root.find_child(n, true, false)
		if is_instance_valid(node) and "visible" in node and node.visible:
			return true
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return true
	return false


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
	# NOTE: the refill itself lives in _recharge_stamina(), driven from _process —
	# see there for why.

func _build_stamina_bar() -> void:
	_stamina_icon = Sprite2D.new()
	_stamina_icon.position = stamina_bar_offset
	_stamina_icon.z_index = 50
	_stamina_icon.visible = false
	_stamina_icon.scale = Vector2(0.4, 0.4)   # 32px icon -> ~13px indicator under the player
	add_child(_stamina_icon)

# ── Footstep loop ────────────────────────────────────────────────────────────────
# Repeats a footstep for as long as the player is actually walking. Sprinting uses
# the same samples at a tighter interval (SFX.step_interval), so the run is just
# the walk sped up. The first step fires immediately so moving off feels instant.
func _tick_footsteps(delta: float) -> void:
	_step_timer -= delta
	if _step_timer <= 0.0:
		SFX.footstep(is_sprinting)
		_step_timer = SFX.step_interval(is_sprinting)

# Standing still re-arms the next step so it lands the moment you move again.
func _reset_footsteps() -> void:
	_step_timer = 0.0

func _update_stamina_bar() -> void:
	if not is_instance_valid(_stamina_icon): return
	# Only show in the overworld, and only when it matters (sprinting or refilling).
	var show_icon = not QuestManager.is_in_combat and (is_sprinting or stamina < SPRINT_MAX)
	_stamina_icon.visible = show_icon
	if not show_icon: return
	# Single icon that swaps by state: green (fine) -> yellow (low) -> red (spent).
	var pct = clampf(stamina / SPRINT_MAX, 0.0, 1.0)
	var id := "stamina_full"
	if sprint_exhausted:   id = "stamina_empty"
	elif pct < 0.34:       id = "stamina_low"
	if id != _stamina_state:
		_stamina_state = id
		var tex = IconDB.tex(id)
		if tex: _stamina_icon.texture = tex

func apply_velocity_knockback() -> void:
	is_knocked_back = true
	var bounce_dir = -last_input_dir
	if bounce_dir == Vector2.ZERO:
		bounce_dir = Vector2.UP
	velocity = bounce_dir * knockback_force
	await get_tree().create_timer(knockback_duration).timeout
	is_knocked_back = false
