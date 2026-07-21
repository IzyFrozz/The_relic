extends CharacterBody2D

@export var enemy_level: int = 1
@export var enemy_id: String = ""   # stable id for save/respawn tracking — auto-generated if blank
# Marks the one guided-tutorial mob (set on "mob1" in character.tscn): its first
# pull shows a short "how combat works" dialogue, and once defeated it never
# respawns (unlike every other mob, which respawns after RESPAWN_COOLDOWN_SECONDS).
@export var is_tutorial_mob: bool = false

@export var battle_player_marker: Marker2D
@export var battle_enemy_marker:  Marker2D
@export var graveyard_marker:     Marker2D
@export var combat_ui:  CanvasLayer
@export var lose_ui:    CanvasLayer

var enemy_health:     int = 100
var enemy_max_health: int = 100
var enemy_inventory:  Array[String] = []
var player_inventory: Array[String] = []
var enemy_item_pool:  Array = []

# Each non-healing item may be used only ONCE per player turn (reset every turn).
# Different buff items still stack — you just can't spam the same one. Healing
# items are exempt (see HEAL_ITEMS).
var items_used_this_turn: Dictionary = {}
const HEAL_ITEMS := ["potion", "bandage", "phoenix_feather"]
# Items that can only ever have ONE copy in the player's bag at a time.
const MAX_ONE_ITEMS := ["relic", "phoenix_feather"]

# ── Overhead level label ─────────────────────────────────────────────────────
# Built entirely in code (not scene-authored) so it applies uniformly to every
# hand-placed mob instance without editing character.tscn's node tree by hand.
# A second, LARGER Area2D ("sight range") purely toggles the label's visibility;
# the original small "deadzone" Area2D remains the sole combat trigger.
var _level_label: Label = null
var _sight_area: Area2D = null
var _player_in_sight: bool = false

var cycles_until_drop:    int = 1
var drop_round_index:     int = 0
var current_items_per_deal: int = 1

var player_active_armor:   bool = false;  var enemy_active_armor:   bool = false
var player_sharpened:      bool = false;  var enemy_sharpened:      bool = false
var player_overcharged:    bool = false;  var enemy_overcharged:    bool = false
var player_piercing:       bool = false;  var enemy_piercing:       bool = false
var player_is_disarmed:    bool = false;  var enemy_is_disarmed:    bool = false
var player_weakened:       bool = false;  var enemy_weakened:       bool = false
var player_cursed:         bool = false;  var enemy_cursed:         bool = false
var player_reflect_active: bool = false;  var enemy_reflect_active: bool = false
var player_dodge_active:   bool = false;  var enemy_dodge_active:   bool = false
var player_items_locked:   bool = false;  var enemy_items_locked:   bool = false
var player_lifesteal_active: bool = false; var enemy_lifesteal_active: bool = false
var player_god_pierce:       bool = false; var enemy_god_pierce:       bool = false
var player_banner_rounds:    int = 0;  var enemy_banner_rounds:    int = 0   # War Banner: rally aura duration
var player_damage_bonus: int = 0;  var enemy_damage_bonus: int = 0

var player_regen_rounds:     int = 0;  var enemy_regen_rounds:     int = 0
var player_poison_rounds:    int = 0;  var enemy_poison_rounds:    int = 0
var player_stun_extra_turns: int = 0;  var enemy_stun_extra_turns: int = 0

# ── Phoenix Feather (player-only safety net) ──────────────────────────────────
# Reworked away from a game-flipping full heal. It now revives you to a modest
# fixed HP the moment you would die, then locks itself behind a turn cooldown so
# it can't chain-save you. The cooldown base climbs by +1 with every activation
# this fight, so leaning on it repeatedly gets steadily riskier.
const PHOENIX_REVIVE_HP := 40
const PHOENIX_BASE_COOLDOWN := 5
var player_phoenix_cd:   int = 0   # rounds remaining before it can trigger again
var player_phoenix_uses: int = 0   # activations so far this fight (drives the climbing cooldown)

# ── Ancient Relic (player-only signature item) ────────────────────────────────
# The single strongest item, but deliberately NOT a stacking buff and NOT a full
# heal. It's a self-contained burst that charges up from the damage flowing
# through the fight (dealt + taken), independent of the enemy's loadout. Only
# when fully charged does its button light up; firing it spends the charge.
const RELIC_STRIKE_DAMAGE := 40   # fixed, unblockable — does NOT scale with buffs (multiple of 10)
const RELIC_HEAL := 20            # bounded, respects the gold-heart heal cap
var player_relic_charge: int = 0
var _relic_prev_enemy_hp:  int = 0   # snapshots for per-round charge accrual
var _relic_prev_player_hp: int = 0
var _relic_announced_charged: bool = false   # one-shot "it's ready!" callout

# ── Mirror Clone (player-only) ────────────────────────────────────────────────
# A ghostly teal double summoned in front of the player. It strikes first on
# your attack turn (flat 20), then soaks the enemy's next hit and fades.
const CLONE_STRIKE_DAMAGE := 20
var player_clone_active: bool = false
var _clone_node: Node2D = null
var _clone_player_home: Vector2 = Vector2.ZERO

# The charge target climbs with lifetime uses (persisted on QuestManager).
func relic_charge_needed() -> int:
	return QuestManager.relic_charge_needed()

func relic_is_charged() -> bool:
	return player_inventory.has("relic") and player_relic_charge >= relic_charge_needed()

var player_ref: Node2D = null
var is_in_combat: bool = false
var enemy_overworld_position: Vector2 = Vector2.ZERO

const ACTION_PAUSE := 0.90
# The enemy's turn is a spectator moment — the player can only read it, not act
# in it — so its beats are deliberately slower than the player's. At ACTION_PAUSE
# a three-item turn flashed past in under two seconds and read as one blur.
const ENEMY_ACTION_PAUSE := 1.5
const FX_TINT_DUR  := 0.42

var _player_ground_fx: ColorRect = null
var _enemy_ground_fx:  ColorRect = null

# ── Graveyard / respawn state ──────────────────────────────────────────────────
var _is_defeated_waiting_respawn: bool = false
var _permanently_dead: bool = false   # tutorial mob only — never respawns once beaten
var _orig_collision_layer: int = 1
var _orig_collision_mask:  int = 1

# =============================================================================
#  FX SYSTEM
# =============================================================================
# NOTE: every fx function checks `is_in_combat` after each await. Combat can
# end (and call _reset_sprite_modulates()) WHILE one of these coroutines is
# still paused mid-await — e.g. a poison tick that hasn't finished its 0.38s
# timer when the killing blow lands. Without this guard, the stale coroutine
# resumes afterward and overwrites the freshly-reset white modulate with its
# own (now-incorrect) "orig" colour, leaving the sprite tinted after the
# fight ends. The guard makes every fx function a no-op once combat is over.

func _get_sprite(target: String) -> AnimatedSprite2D:
	if target == "player":
		if is_instance_valid(player_ref):
			return player_ref.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	else:
		return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	return null

# Push the current combat state into the HUD right now.
#
# Every fx function calls this on entry. Combat state (HP, buffs, inventories) is
# mutated the instant an action resolves, but the HUD used to be repainted only
# at a few checkpoints — so a whole turn's worth of actions played out visually
# while the bars still showed the values from the START of the round, and the
# numbers all snapped at once at the end. Refreshing as each effect BEGINS means
# the bar moves in lockstep with the thing that caused it: heal sparkle and the
# HP going up are the same beat, and the player can follow the turn action by
# action. Cheap and idempotent, so calling it often is fine.
func _sync_ui() -> void:
	if combat_ui and is_instance_valid(combat_ui):
		combat_ui._refresh_ui_states()

func _fx_heal(target: String) -> void:
	if not is_in_combat: return
	_sync_ui()
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	for _i in 2:
		s.modulate = Color(0.60, 1.45, 0.60, 1.0)
		await get_tree().create_timer(0.15).timeout
		if not is_in_combat: return
		if is_instance_valid(s): s.modulate = orig
		await get_tree().create_timer(0.10).timeout
		if not is_in_combat: return
	_float_icon(target, "✚", Color(0.35, 1.0, 0.45))
	if is_instance_valid(s): s.modulate = orig

func _fx_damage(target: String) -> void:
	if not is_in_combat: return
	_sync_ui()
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(1.75, 0.18, 0.18, 1.0)
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_status(target: String, color: Color, icon: String = "") -> void:
	if not is_in_combat: return
	_sync_ui()
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = color
	if icon != "": _float_icon(target, icon, color)
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_poison_tick(target: String) -> void:
	if not is_in_combat: return
	_sync_ui()
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(0.28, 0.82, 0.28, 1.0)
	# Poison damage has no attack behind it, so this is where the hit sound belongs.
	SFX.play(SFX.player_hit if target == "player" else SFX.enemy_hit)
	_float_icon(target, "☠", Color(0.3, 0.85, 0.3))
	await get_tree().create_timer(0.38).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

func _fx_steal(from_target: String) -> void:
	if not is_in_combat: return
	_sync_ui()
	var s = _get_sprite(from_target)
	if not is_instance_valid(s): return
	var orig = s.modulate
	s.modulate = Color(0.95, 0.38, 1.12, 1.0)
	_float_icon(from_target, "🧲", Color(0.9, 0.4, 1.0))
	await get_tree().create_timer(FX_TINT_DUR).timeout
	if not is_in_combat: return
	if is_instance_valid(s): s.modulate = orig

# ── Ancient Relic beam ───────────────────────────────────────────────────────
# The relic's signature moment: light gathers in the sky ABOVE the enemy, then a
# sustained column slams straight down onto it — the player channels it but the
# beam never comes out of the player. Built from Line2D layers (wide teal glow +
# hot white core) in WORLD space, aimed at the enemy's captured position.
const RELIC_BEAM_CHARGE := 0.60   # wind-up before the beam exists
const RELIC_BEAM_HOLD   := 1.30   # beam sustained on the enemy
const RELIC_BEAM_FADE   := 0.45   # collapse
const RELIC_BEAM_SKY    := 150.0  # world px above the enemy the column falls from
# → ~2.35s total.

# Builds a filled circle polygon of `radius` (Line2D can't draw discs).
func _disc(radius: float, color: Color, segments: int = 24) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = color
	return poly

# ── Relic double cleanse ─────────────────────────────────────────────────────
# The relic doesn't just hit: it wipes the board. Every buff the enemy has built
# up is stripped, and every affliction on the player is lifted. Deliberately
# lopsided — this is the strongest item in the game and it should feel like it.
#
# Note what is NOT touched on the enemy: poison, curse, weaken, disarm, item-lock
# and stun are debuffs the PLAYER inflicted, so clearing them would punish you
# for using your own ultimate.
func _relic_strip_enemy_buffs() -> void:
	enemy_active_armor     = false   # shield
	enemy_reflect_active   = false   # mirror ward
	enemy_dodge_active     = false   # smoke bomb
	enemy_sharpened        = false   # grindstone
	enemy_overcharged      = false   # overcharge
	enemy_piercing         = false   # needle
	enemy_lifesteal_active = false   # lifesteal vial
	enemy_god_pierce       = false
	enemy_banner_rounds    = 0       # rally aura
	enemy_regen_rounds     = 0       # bandage regen
	enemy_damage_bonus     = 0       # accumulated damage buffs

# Lifts every affliction on the player, including the action-denial ones — a
# relic turn can't be wasted by a stun or an item lock.
func _relic_cleanse_player() -> void:
	player_poison_rounds    = 0
	player_cursed           = false
	player_weakened         = false
	player_is_disarmed      = false
	player_items_locked     = false
	player_stun_extra_turns = 0

# `target` is who gets hit ("enemy" for the player's relic, "player" for the
# enemy's Relicbound threat). `beam_col` tints the outer glow, `width_mult`
# scales the whole column so a lesser beam reads as visibly slimmer.
func _fx_beam(target: String, beam_col: Color, width_mult: float = 1.0) -> void:
	if not is_in_combat: return
	var ps = _get_sprite("player" if target == "enemy" else "enemy")   # the channeller
	var es = _get_sprite(target)                                          # the victim
	if not (is_instance_valid(ps) and is_instance_valid(es)): return
	if not is_instance_valid(player_ref): return
	var host = player_ref.get_parent()
	if not is_instance_valid(host): return

	var TEAL := beam_col
	const CORE := Color(1.00, 1.00, 1.00)   # pure white hot centre either way

	# The strike point is captured ONCE, before the enemy starts shaking, so the
	# beam hangs dead straight while the enemy rattles around underneath it.
	var strike: Vector2 = es.global_position
	var sky: Vector2    = strike + Vector2(0, -RELIC_BEAM_SKY)

	# Remember what to put back: the shake moves the sprite and the zap recolours
	# it, and _fx_damage runs straight after this and would otherwise capture the
	# strobed white as the colour to "restore" to.
	var es_home_pos: Vector2 = es.position
	var es_home_mod: Color   = es.modulate

	# Everything lives under one node so a single queue_free cleans the whole FX
	# up — including if combat ends mid-beam.
	var rig := Node2D.new()
	rig.z_index = 80
	host.add_child(rig)

	# ── 1. Wind-up: light gathers in the sky, the ground below is telegraphed ──
	SFX.play(SFX.relic_beam_charge if SFX.relic_beam_charge else SFX.relic_unleash)
	var orb := _disc(4.0 * width_mult, TEAL)
	orb.global_position = sky
	rig.add_child(orb)
	var halo := _disc(9.0 * width_mult, Color(TEAL.r, TEAL.g, TEAL.b, 0.35))
	halo.global_position = sky
	rig.add_child(halo)
	# A pool of light on the enemy so the player can SEE where it is going to land
	# (the gathering orb itself is above the top of the screen).
	var mark := _disc(14.0 * width_mult, Color(TEAL.r, TEAL.g, TEAL.b, 0.0))
	mark.global_position = strike
	mark.scale = Vector2(1.0, 0.42)          # flattened — reads as light on the ground
	rig.add_child(mark)
	var ct := create_tween().set_parallel(true)
	ct.tween_property(orb,  "scale", Vector2(2.4, 2.4), RELIC_BEAM_CHARGE).set_trans(Tween.TRANS_CUBIC)
	ct.tween_property(halo, "scale", Vector2(3.2, 3.2), RELIC_BEAM_CHARGE).set_trans(Tween.TRANS_CUBIC)
	ct.tween_property(halo, "rotation", TAU, RELIC_BEAM_CHARGE)
	ct.tween_property(mark, "color:a", 0.55, RELIC_BEAM_CHARGE)
	ct.tween_property(mark, "scale", Vector2(1.7, 0.7), RELIC_BEAM_CHARGE)
	if is_instance_valid(ps):
		ct.tween_property(ps, "modulate", Color(0.6, 0.6, 0.6) + beam_col, RELIC_BEAM_CHARGE * 0.8)
	# The enemy already trembles a little as the light builds over it.
	var warn := 0.0
	while warn < RELIC_BEAM_CHARGE and is_in_combat and is_instance_valid(es):
		es.position = es_home_pos + Vector2(randf_range(-0.8, 0.8), 0)
		warn += get_process_delta_time()
		await get_tree().process_frame
	if is_instance_valid(es): es.position = es_home_pos
	if not is_in_combat or not is_instance_valid(rig):
		_relic_beam_restore(es, es_home_pos, es_home_mod, ps)
		if is_instance_valid(rig): rig.queue_free()
		return

	# ── 2. Fire: the column slams DOWN out of the sky onto the enemy ───────────
	SFX.start_loop("relic_beam", SFX.relic_beam_fire if SFX.relic_beam_fire else SFX.relic_unleash)
	var glow := Line2D.new()
	glow.default_color = Color(TEAL.r, TEAL.g, TEAL.b, 0.45)
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode   = Line2D.LINE_CAP_ROUND
	glow.width = 2.0
	glow.points = PackedVector2Array([rig.to_local(sky), rig.to_local(sky)])
	rig.add_child(glow)
	var core := Line2D.new()
	core.default_color = CORE
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode   = Line2D.LINE_CAP_ROUND
	core.width = 1.0
	core.points = PackedVector2Array([rig.to_local(sky), rig.to_local(sky)])
	rig.add_child(core)

	# Drops fast — a strike, not a creeping line — widening as it falls.
	var ft := create_tween().set_parallel(true)
	ft.tween_method(func(p: float):
		if is_instance_valid(glow): glow.set_point_position(1, rig.to_local(sky.lerp(strike, p)))
		if is_instance_valid(core): core.set_point_position(1, rig.to_local(sky.lerp(strike, p))),
		0.0, 1.0, 0.12).set_trans(Tween.TRANS_EXPO)
	ft.tween_property(glow, "width", 26.0 * width_mult, 0.12)
	ft.tween_property(core, "width", 9.0 * width_mult, 0.12)
	await ft.finished
	if not is_in_combat or not is_instance_valid(rig):
		SFX.stop_loop("relic_beam")
		_relic_beam_restore(es, es_home_pos, es_home_mod, ps)
		if is_instance_valid(rig): rig.queue_free()
		return

	# Impact burst where it lands.
	var burst := _disc(10.0 * width_mult, Color(1.0, 0.98, 1.0, 0.9))
	burst.global_position = strike
	rig.add_child(burst)
	var bt := create_tween().set_parallel(true)
	bt.tween_property(burst, "scale", Vector2(3.8, 3.8), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bt.tween_property(burst, "modulate:a", 0.0, 0.45)

	# ── 3. Hold: the enemy is pinned under the column — shaken and zapped ──────
	# The shake and the white strobe are what sell it as damage: the beam alone
	# just looks like scenery falling on them.
	var held := 0.0
	var strobe := 0.0
	while held < RELIC_BEAM_HOLD and is_in_combat and is_instance_valid(rig):
		var flicker := randf_range(0.86, 1.16)
		if is_instance_valid(glow): glow.width = 26.0 * width_mult * flicker
		if is_instance_valid(core): core.width = 9.0 * width_mult * randf_range(0.85, 1.2)
		if is_instance_valid(orb):  orb.scale = Vector2.ONE * 2.4 * flicker
		if is_instance_valid(mark): mark.scale = Vector2(1.7, 0.7) * flicker
		if is_instance_valid(es):
			# Getting-hit shake — hard and jittery, around the ORIGINAL position so
			# it can never drift the sprite off its mark.
			es.position = es_home_pos + Vector2(randf_range(-3.5, 3.5), randf_range(-2.5, 2.5))
			# Zapped: strobe between overbright white and a hot teal-white.
			strobe += get_process_delta_time()
			es.modulate = Color(3.0, 3.0, 3.0) if fmod(strobe, 0.10) < 0.05 \
				else Color(1.6, 2.4, 2.4)
		held += get_process_delta_time()
		await get_tree().process_frame

	# ── 4. Collapse ───────────────────────────────────────────────────────────
	SFX.stop_loop("relic_beam")
	if is_instance_valid(es):
		es.position = es_home_pos
	if is_instance_valid(rig):
		var et := create_tween().set_parallel(true)
		if is_instance_valid(glow): et.tween_property(glow, "width", 0.0, RELIC_BEAM_FADE)
		if is_instance_valid(core): et.tween_property(core, "width", 0.0, RELIC_BEAM_FADE)
		if is_instance_valid(mark): et.tween_property(mark, "color:a", 0.0, RELIC_BEAM_FADE)
		et.tween_property(rig, "modulate:a", 0.0, RELIC_BEAM_FADE)
		if is_instance_valid(ps):
			et.tween_property(ps, "modulate", Color.WHITE, RELIC_BEAM_FADE)
		if is_instance_valid(es):
			et.tween_property(es, "modulate", es_home_mod, RELIC_BEAM_FADE)
		await et.finished
	if is_instance_valid(rig): rig.queue_free()
	_relic_beam_restore(es, es_home_pos, es_home_mod, ps)

# Puts the enemy sprite back exactly as we found it (position AND colour) and
# clears the player tint. Called on every exit path — a fight that ends mid-beam
# must not leave the enemy stuck white or nudged off its mark.
const BEAM_TEAL := Color(0.20, 0.95, 0.88)   # player relic: cold ancient light
const BEAM_RED  := Color(1.00, 0.42, 0.12)   # enemy Relicbound: hot red-orange

# The player's Ancient Relic — full-width teal column onto the enemy.
func _fx_relic_beam() -> void:
	await _fx_beam("enemy", BEAM_TEAL, 1.0)

func _relic_beam_restore(es, home_pos: Vector2, home_mod: Color, ps) -> void:
	if is_instance_valid(es):
		es.position = home_pos
		es.modulate = home_mod
	# The player tint is watched by the recolor shader in mainplayer, so leave the
	# sprite exactly as we found it.
	if is_instance_valid(ps):
		ps.modulate = Color.WHITE

func _float_icon(target: String, icon: String, color: Color) -> void:
	if not is_instance_valid(combat_ui): return
	var s = _get_sprite(target)
	if not is_instance_valid(s): return
	var sp  = get_viewport().get_canvas_transform() * s.global_position
	# Prefer a real pixel icon when this emoji is mapped; else fall back to the glyph.
	var node: Control
	var icon_tex: Texture2D = IconDB.tex(IconDB.id_for_emoji(icon))
	if is_instance_valid(icon_tex):
		var tr = TextureRect.new()
		tr.texture = icon_tex
		tr.custom_minimum_size = Vector2(40, 40)
		tr.size = Vector2(40, 40)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.position = sp + Vector2(-20, -60)
		node = tr
	else:
		var lbl = Label.new()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.add_theme_color_override("font_color", color)
		lbl.position = sp + Vector2(-14, -54)
		node = lbl
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.z_index      = 200
	combat_ui.add_child(node)
	var tw = node.create_tween().set_parallel(true)
	tw.tween_property(node, "position:y", node.position.y - 58, 0.88).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 0.0, 0.88).set_delay(0.26)
	get_tree().create_timer(0.96).timeout.connect(
		func(): if is_instance_valid(node): node.queue_free()
	)

func _reset_sprite_modulates() -> void:
	var ps = _get_sprite("player"); if is_instance_valid(ps): ps.modulate = Color.WHITE
	var es = _get_sprite("enemy");  if is_instance_valid(es): es.modulate = Color.WHITE

func _set_ground_fx(target: String, color: Color) -> void:
	var sprite = _get_sprite(target)
	if not is_instance_valid(sprite): return
	var fx: ColorRect
	if target == "player":
		if not is_instance_valid(_player_ground_fx):
			_player_ground_fx = ColorRect.new(); _player_ground_fx.z_index = -1
			sprite.get_parent().add_child(_player_ground_fx)
		fx = _player_ground_fx
	else:
		if not is_instance_valid(_enemy_ground_fx):
			_enemy_ground_fx = ColorRect.new(); _enemy_ground_fx.z_index = -1
			sprite.get_parent().add_child(_enemy_ground_fx)
		fx = _enemy_ground_fx
	if color.a < 0.01:
		fx.visible = false
		return
	fx.color = color; fx.size = Vector2(36, 10)
	fx.position = sprite.position + Vector2(-18, 8); fx.visible = true

func _sync_ground_fx() -> void:
	if player_poison_rounds  > 0: _set_ground_fx("player", Color(0.05, 0.38, 0.05, 0.75))
	elif player_cursed:           _set_ground_fx("player", Color(0.25, 0.05, 0.42, 0.70))
	elif player_regen_rounds > 0: _set_ground_fx("player", Color(0.10, 0.55, 0.10, 0.65))
	elif player_active_armor:     _set_ground_fx("player", Color(0.20, 0.45, 0.90, 0.60))
	elif player_dodge_active:     _set_ground_fx("player", Color(0.20, 0.80, 0.90, 0.55))
	elif player_reflect_active:   _set_ground_fx("player", Color(0.90, 0.80, 0.10, 0.60))
	else:                         _set_ground_fx("player", Color.TRANSPARENT)
	if enemy_poison_rounds  > 0:  _set_ground_fx("enemy", Color(0.05, 0.38, 0.05, 0.75))
	elif enemy_cursed:             _set_ground_fx("enemy", Color(0.25, 0.05, 0.42, 0.70))
	elif enemy_regen_rounds > 0:  _set_ground_fx("enemy", Color(0.10, 0.55, 0.10, 0.65))
	elif enemy_active_armor:      _set_ground_fx("enemy", Color(0.20, 0.45, 0.90, 0.60))
	elif enemy_dodge_active:      _set_ground_fx("enemy", Color(0.20, 0.80, 0.90, 0.55))
	elif enemy_reflect_active:    _set_ground_fx("enemy", Color(0.90, 0.80, 0.10, 0.60))
	else:                         _set_ground_fx("enemy", Color.TRANSPARENT)

func _clear_ground_fx_visibility() -> void:
	if is_instance_valid(_player_ground_fx): _player_ground_fx.visible = false
	if is_instance_valid(_enemy_ground_fx):  _enemy_ground_fx.visible  = false

# =============================================================================
#  INIT
# =============================================================================

func _ready() -> void:
	if enemy_id == "":
		var parent_name = get_parent().name if is_instance_valid(get_parent()) else "root"
		enemy_id = "%s/%s" % [parent_name, name]

	_orig_collision_layer = collision_layer
	_orig_collision_mask  = collision_mask

	_initialize_mob_stats_by_character_tier()
	_auto_wire_overworld_signals()
	_setup_level_display()
	enemy_overworld_position = self.global_position
	if is_tutorial_mob and QuestManager.tutorial_mob_defeated:
		_permanently_dead = true
		_hide_and_disable_at_graveyard()
	else:
		_check_existing_defeat_state()

func _process(_delta: float) -> void:
	if _permanently_dead:
		return
	if _is_defeated_waiting_respawn:
		var death_time = QuestManager.defeated_enemies.get(enemy_id, QuestManager.play_time_seconds)
		var elapsed = QuestManager.play_time_seconds - float(death_time)
		if elapsed >= QuestManager.RESPAWN_COOLDOWN_SECONDS:
			QuestManager.defeated_enemies.erase(enemy_id)
			_respawn_enemy()

func _check_existing_defeat_state() -> void:
	if not QuestManager.defeated_enemies.has(enemy_id):
		return
	var death_time = float(QuestManager.defeated_enemies[enemy_id])
	var elapsed = QuestManager.play_time_seconds - death_time
	if elapsed >= QuestManager.RESPAWN_COOLDOWN_SECONDS:
		QuestManager.defeated_enemies.erase(enemy_id)
	else:
		_is_defeated_waiting_respawn = true
		_hide_and_disable_at_graveyard()

func _hide_and_disable_at_graveyard() -> void:
	visible = false
	collision_layer = 0
	collision_mask  = 0
	_reset_enemy_visual_state()
	var dz = find_child("deadzone")
	if is_instance_valid(dz) and dz is Area2D:
		dz.monitoring  = false
		dz.monitorable = false
	if is_instance_valid(_sight_area):
		_sight_area.monitoring = false
	if is_instance_valid(_level_label):
		_level_label.visible = false
	if is_instance_valid(graveyard_marker):
		self.global_position = graveyard_marker.global_position
	else:
		self.global_position = enemy_overworld_position

func _respawn_enemy() -> void:
	_is_defeated_waiting_respawn = false
	visible = true
	collision_layer = _orig_collision_layer
	collision_mask  = _orig_collision_mask
	var dz = find_child("deadzone")
	if is_instance_valid(dz) and dz is Area2D:
		dz.monitoring  = true
		dz.monitorable = true
	if is_instance_valid(_sight_area):
		_sight_area.monitoring = true
	self.global_position = enemy_overworld_position
	_reset_enemy_visual_state()
	_initialize_mob_stats_by_character_tier()

# Restores the AnimatedSprite2D to its normal idle state. Without this, a
# respawned mob keeps showing whatever frame the "die" animation froze on
# (a different, larger spritesheet region than the idle frames), which is
# what caused the squished/warped look on respawn — the node itself was
# positioned correctly, the sprite was just stuck on the wrong texture.
func _reset_enemy_visual_state() -> void:
	var spr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(spr):
		spr.modulate = Color.WHITE
		spr.speed_scale = 1.0
		if spr.sprite_frames and spr.sprite_frames.has_animation("default"):
			spr.play("default")
		spr.frame = 0

func _auto_wire_overworld_signals() -> void:
	var dz = find_child("deadzone")
	if dz and dz.has_signal("body_entered"):
		if dz.body_entered.is_connected(_on_deadzone_body_entered):
			dz.body_entered.disconnect(_on_deadzone_body_entered)
		dz.body_entered.connect(_on_deadzone_body_entered)

# Builds the overhead "Lv. N" label and its larger sight-range Area2D. The
# sight radius is derived from the existing "deadzone" shape (if a
# CircleShape2D) so bigger enemies naturally get a bigger sight range too.
func _setup_level_display() -> void:
	var dz_radius := 24.0
	var dz = find_child("deadzone")
	if is_instance_valid(dz):
		var dzc = dz.find_child("DZcollison")
		if is_instance_valid(dzc) and dzc is CollisionShape2D and (dzc as CollisionShape2D).shape is CircleShape2D:
			dz_radius = ((dzc as CollisionShape2D).shape as CircleShape2D).radius

	_sight_area = Area2D.new()
	_sight_area.name = "SightZone"
	_sight_area.monitorable = false
	add_child(_sight_area)
	var sight_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = dz_radius * 2.6   # well beyond the deadzone — purely visual
	sight_shape.shape = circle
	_sight_area.add_child(sight_shape)
	_sight_area.body_entered.connect(_on_sight_body_entered)
	_sight_area.body_exited.connect(_on_sight_body_exited)

	# Anchor the label just above the sprite's actual top edge (not the much
	# larger deadzone radius, which floated it way over the head).
	var sprite_top := -dz_radius
	var spr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(spr) and spr.sprite_frames and spr.sprite_frames.has_animation("default"):
		var tex = spr.sprite_frames.get_frame_texture("default", 0)
		if tex != null:
			sprite_top = spr.position.y - tex.get_height() * 0.5 * spr.scale.y

	const LBL_W := 80.0
	const LBL_SCALE := 0.4
	_level_label = Label.new()
	_level_label.text = "Lv. %d" % enemy_level
	_level_label.add_theme_font_size_override("font_size", 20)
	_level_label.scale = Vector2(LBL_SCALE, LBL_SCALE)
	_level_label.size = Vector2(LBL_W, 20)
	# Centre horizontally on the sprite (scale pivots from the top-left corner),
	# and sit a few px above the sprite's head.
	_level_label.position = Vector2(-LBL_W * LBL_SCALE * 0.5, sprite_top - 12.0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_level_label.add_theme_constant_override("shadow_offset_x", 1)
	_level_label.add_theme_constant_override("shadow_offset_y", 1)
	_level_label.visible = false
	add_child(_level_label)
	_update_level_label_color()

# Colour-codes the level label relative to the player's current level so the
# player can judge threat at a glance (green = easy, yellow = even, red = tough).
func _update_level_label_color() -> void:
	if not is_instance_valid(_level_label):
		return
	var diff := enemy_level - QuestManager.player_level
	var col: Color
	if diff <= -3:   col = Color(0.45, 0.95, 0.45)   # much weaker
	elif diff < 0:   col = Color(0.75, 0.95, 0.55)   # weaker
	elif diff == 0:  col = Color(1.0, 0.92, 0.4)     # even
	elif diff <= 2:  col = Color(1.0, 0.65, 0.35)    # stronger
	else:            col = Color(1.0, 0.35, 0.35)    # much stronger
	_level_label.add_theme_color_override("font_color", col)

func _on_sight_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		_player_in_sight = true
		_update_level_label_color()
		_refresh_level_label_visibility()

func _on_sight_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		_player_in_sight = false
		_refresh_level_label_visibility()

# The overhead level tag is an overworld-only affordance: it shows while the
# player is nearby but must never appear once a fight starts (the mob teleports
# to the arena, dragging its label along). Visibility is state-driven so any
# combat start/end path keeps it correct without extra bookkeeping.
func _refresh_level_label_visibility() -> void:
	if not is_instance_valid(_level_label):
		return
	_level_label.visible = _player_in_sight and not is_in_combat and not QuestManager.is_in_combat

const TIER_POOLS_LV6_PLUS := {
	6:  ["potion", "shield", "grindstone", "needle", "magnet", "poison_dart"],
	7:  ["shield", "whip",   "poison_dart", "bandage", "needle", "magnet"],
	8:  ["grindstone", "lifesteal_vial", "needle", "magnet", "potion", "shield"],
	9:  ["shield", "smoke_bomb", "poison_dart", "whip", "bandage", "needle"],
	10: ["mirror_ward", "grindstone", "lifesteal_vial", "needle", "potion", "magnet"],
	11: ["weaken_totem", "shield", "poison_dart", "bandage", "smoke_bomb", "needle"],
	12: ["chain_hook", "magnet", "needle", "smoke_bomb", "lifesteal_vial", "potion"],
	13: ["static_field", "mirror_ward", "weaken_totem", "lifesteal_vial", "bandage", "needle"],
	14: ["time_warp", "chain_hook", "poison_dart", "needle", "shield", "potion"],
	15: ["overcharge", "time_warp", "static_field", "mirror_ward", "chain_hook", "bandage"],
	# 16-20: the late tiers used to reuse level 15's kit verbatim (a placeholder),
	# so a level 20 fight played exactly like a level 15 one. Each rung now fields
	# its own mix of the heaviest items so the battlefield keeps changing.
	16: ["overcharge", "static_field", "lifesteal_vial", "weaken_totem", "needle", "potion"],
	17: ["time_warp", "chain_hook", "mirror_ward", "grindstone", "poison_dart", "bandage"],
	18: ["overcharge", "weaken_totem", "smoke_bomb", "static_field", "magnet", "shield"],
	19: ["time_warp", "overcharge", "mirror_ward", "chain_hook", "lifesteal_vial", "needle"],
	20: ["overcharge", "time_warp", "static_field", "weaken_totem", "chain_hook", "mirror_ward"],
}

# ── Late-tier loadout upgrades ───────────────────────────────────────────────
# A high-level foe has no business throwing a Potion when it has known Bandage
# for ten levels. Once a mob's level has reached an item's UPGRADE, the starter
# version is dropped from its pool entirely — it never brings the weak tool again.
# Gated on QuestManager.unlock_level_of(), so a mob can only ever field something
# its own tier has actually unlocked.
const ITEM_UPGRADES := {
	"potion":      "bandage",       # 20 now  ->  10 now + 20 over two rounds
	"shield":      "mirror_ward",   # block   ->  reflect the whole hit back
	"grindstone":  "overcharge",    # +20     ->  +20 AND pierces armour
	"needle":      "overcharge",    # pierce  ->  pierce AND +20
	"whip":        "time_warp",     # skip 1  ->  skip 2
	"magnet":      "chain_hook",    # steal   ->  steal AND -20 off their next hit
	"poison_dart": "static_field",  # dot     ->  locks the target's items
	"smoke_bomb":  "weaken_totem",  # dodge   ->  curse their next attack
}

# Upgrades can collapse two entries into one (needle and grindstone both become
# overcharge), so the pool is topped back up from the heavy end afterwards — a
# late mob must never end up fielding a THINNER kit than a mid-tier one.
const STRONG_FILL := [
	"overcharge", "time_warp", "static_field", "chain_hook", "mirror_ward",
	"weaken_totem", "lifesteal_vial", "bandage", "smoke_bomb", "poison_dart",
]

func _apply_item_upgrades(pool: Array) -> Array:
	var want: int = pool.size()
	var out: Array = []
	for it in pool:
		var id: String = str(it)
		var up: String = str(ITEM_UPGRADES.get(id, ""))
		if up != "" and enemy_level >= QuestManager.unlock_level_of(up):
			id = up
		if not out.has(id):
			out.append(id)
	for fill in STRONG_FILL:
		if out.size() >= want:
			break
		if not out.has(fill) and enemy_level >= QuestManager.unlock_level_of(fill):
			out.append(fill)
	return out

# ── Enemy threat traits (RELIC difficulty only) ──────────────────────────────
# On "Chosen by the Relic" every mob carries ONE permanent trait, rolled at spawn
# from those its level has reached. The gates mirror the player's own unlock
# ladder — a level 7 mob can be Venomous because poison exists by then — so the
# threat always reads as "this foe fights with what this tier knows".
# All damage numbers stay in multiples of 10: the HP hearts have no half-step art.
# NOTHING here fires automatically — every trait rolls its `proc` chance each time
# it gets an opportunity, so a fight never becomes a guaranteed grind of the same
# effect every single swing.
#
# `proc` follows a deliberate DOWNWARD curve against min_level: the late-tier
# traits are the nastiest, so they land as occasional spikes rather than a
# constant tax, and a level 20 foe carrying four of them still gets a readable
# number of procs a round.
#
# HARD CEILING: no rolled trait may sit at or above 1-in-3 (0.33). The curve used
# to open at 0.50, which meant Brutal fired on half of all swings — that reads as
# the mob's baseline damage rather than as a trait, and it stacked with every
# other trait the mob was carrying. Keep new entries at or below 0.33, and keep
# the ladder descending by min_level.
# The two LOCKOUT traits (jammer / disarming) sit far below the rest — see the
# note above them. `undying` at 1.00 is NOT rolled; its call site uses has_threat.
const ENEMY_THREATS := [
	{ "id": "brutal",     "min_level": 3,  "proc": 0.33, "emoji": "💥", "name": "Brutal",     "desc": "About a third of its swings hit 10 harder." },
	{ "id": "ironhide",   "min_level": 4,  "proc": 0.32, "emoji": "🛡️", "name": "Ironhide",   "desc": "Often shrugs 10 off a hit." },
	{ "id": "cornered",   "min_level": 6,  "proc": 0.31, "emoji": "🔥", "name": "Cornered",   "desc": "Below half health, its swings can hit 10 harder." },
	{ "id": "venomous",   "min_level": 7,  "proc": 0.30, "emoji": "☠️", "name": "Venomous",   "desc": "Its hits can leave you poisoned." },
	{ "id": "leeching",   "min_level": 8,  "proc": 0.29, "emoji": "🩸", "name": "Leeching",   "desc": "Its hits can drain 10 HP back." },
	{ "id": "evasive",    "min_level": 9,  "proc": 0.28, "emoji": "💨", "name": "Evasive",    "desc": "Your attacks sometimes slip past it." },
	{ "id": "warded",     "min_level": 10, "proc": 0.27, "emoji": "🪞", "name": "Warded",     "desc": "May raise a reflecting ward each round." },
	{ "id": "thorned",    "min_level": 11, "proc": 0.26, "emoji": "📌", "name": "Thorned",    "desc": "Landing a hit can cost you 10 HP." },
	{ "id": "hexer",      "min_level": 12, "proc": 0.25, "emoji": "🗿", "name": "Hexer",      "desc": "Its hits can weaken your next attack." },
	# JAMMER + DISARMING are the two LOCKOUT traits — between them they can take
	# away your items and your swing. Individually the anti-lockout rules already
	# stop them landing on the same round, but at their old rates (0.27 / 0.25) a
	# mob carrying both could alternate them almost every round and leave you with
	# nothing to do for most of the fight. Rated well below the other traits so
	# losing a turn stays an occasional setback rather than the default state.
	{ "id": "jammer",     "min_level": 13, "proc": 0.16, "emoji": "⚡", "name": "Jammer",     "desc": "May jam your items for a round." },
	{ "id": "disarming",  "min_level": 14, "proc": 0.14, "emoji": "❌", "name": "Disarming",  "desc": "Its hits can knock your next swing away." },
	{ "id": "relentless", "min_level": 15, "proc": 0.23, "emoji": "⏳", "name": "Relentless", "desc": "Sometimes strikes twice in a round." },
	# UNDYING is GUARANTEED, not rolled: `proc` is 1.0 and the call site uses
	# has_threat. What limits it is the once-per-fight latch (_undying_spent), the
	# same way the player's Phoenix Feather it mirrors is guaranteed but single-use.
	# As a coin flip it was pure noise — you could never plan around whether the
	# killing blow would stick. Always firing makes it a fact you fight around.
	{ "id": "undying",    "min_level": 17, "proc": 1.00, "emoji": "🪶", "name": "Undying",    "desc": "Cheats a killing blow once, rising again with %d HP." % PHOENIX_REVIVE_HP },
	# ── Threshold traits ──────────────────────────────────────────────────────
	# proc = 0 on purpose: these two are NOT rolled. They fire off hard counters,
	# so they're predictable and can be played around, which is what stops a foe
	# carrying both from feeling arbitrary.
	{ "id": "splitter",   "min_level": 12, "proc": 0.0,  "emoji": "👥", "name": "Splitter",   "desc": "Spawns a double for every %d damage it takes." % SPLIT_DAMAGE },
	{ "id": "relicbound", "min_level": 16, "proc": 0.0,  "emoji": "🏺", "name": "Relicbound", "desc": "Calls a searing beam each time its HP falls past a 100 mark." },
]

# Splitter: one clone per this much cumulative damage taken.
const SPLIT_DAMAGE := 80
# Relicbound: fires when current HP drops below each multiple of this.
const BEAM_HP_MARK := 100
const ENEMY_BEAM_DAMAGE := 40   # unblockable, multiple of ten

var _dmg_since_split: int = 0
var _last_beam_mark: int = 0

# A mob gains one trait slot per 5 levels, starting AT level 5 — so levels 1-4
# field none at all, a level 5 foe fields 1, a level 10 foe 2, a level 15 foe 3.
# All are still level-gated individually, so the extra slots can only draw from
# what that tier has actually unlocked.
const THREAT_SLOT_EVERY := 5

var enemy_threats: Array = []        # empty on NORMAL difficulty
var _relentless_extra: bool = false  # re-entry guard for the double-action threat
var _undying_spent: bool = false     # the one-time death save has been used

func has_threat(id: String) -> bool:
	return enemy_threats.has(id)

# ── Threshold threats ────────────────────────────────────────────────────────
# Called from every site that reduces enemy_health. Only tallies; the effects
# themselves fire at the START of the enemy's turn (_run_threshold_threats), so
# a clone can never appear mid-swing and the beam never interrupts your attack.
func _note_enemy_damage(amount: int) -> void:
	if amount > 0:
		_dmg_since_split += amount

func _run_threshold_threats() -> void:
	# SPLITTER — a double for every SPLIT_DAMAGE taken. `while` not `if`, so a
	# single huge hit that crosses two thresholds owes two clones.
	if has_threat("splitter"):
		while _dmg_since_split >= SPLIT_DAMAGE and is_in_combat:
			_dmg_since_split -= SPLIT_DAMAGE
			if enemy_clone_active:
				break                      # only one double at a time
			await _summon_enemy_clone()

	# RELICBOUND — fires ONCE as the enemy's HP first falls past each 100 mark
	# (400, 300, 200, 100 …), and never again for that same mark.
	#
	# `_last_beam_mark` is a RATCHET: it only ever goes down. It used to re-arm
	# when the enemy healed back over a boundary, which meant a mob that heals —
	# potions, lifesteal, LEECHING — could be walked across the same mark over and
	# over and fire a beam every time. That is what made beams look like they were
	# riding along with the Splitter's 80-damage proc instead of tracking HP: both
	# fire in the same pre-turn pass, and a healing mob re-crossing 200 produced a
	# beam at ~140 HP with no new boundary actually reached. Crossing a mark is a
	# one-time event for the whole fight, so healing must NOT re-arm it.
	#
	# Deliberately one beam per turn even when a single hit skips several marks:
	# the ratchet still latches to the new low, so the skipped marks are consumed
	# rather than queued up to fire later.
	if has_threat("relicbound") and is_in_combat:
		var mark := int(floor(float(enemy_health) / float(BEAM_HP_MARK)))
		if mark < _last_beam_mark:
			_last_beam_mark = mark
			await _enemy_relic_beam()

# The enemy's answer to the Ancient Relic: a slimmer red-orange column onto the
# player, using the exact same FX path.
func _enemy_relic_beam() -> void:
	SFX.play(SFX.relic_unleash)
	if combat_ui: combat_ui.display_round_history(
		"🏺 RELICBOUND — a searing beam tears down at you!", false)
	_float_icon("player", "🏺", BEAM_RED)
	await _fx_beam("player", BEAM_RED, 0.55)
	if not is_in_combat: return
	QuestManager.player_health = clampi(
		QuestManager.player_health - ENEMY_BEAM_DAMAGE, 0, QuestManager.MAX_HEALTH)
	await _fx_damage("player")
	if combat_ui:
		combat_ui.display_round_history(
			"🏺 The beam burns you for %d — nothing blocks it." % ENEMY_BEAM_DAMAGE, false)
		combat_ui._refresh_ui_states()

# True when the mob carries `id` AND this opportunity's roll lands. Use this for
# anything that fires during the fight; `has_threat` is only for the display.
func threat_procs(id: String) -> bool:
	if not has_threat(id):
		return false
	for t in ENEMY_THREATS:
		if str(t["id"]) == id:
			return randf() < float(t["proc"])
	return false

# One slot per full THREAT_SLOT_EVERY levels, and ZERO below the first one:
#   1-4 → 0    5-9 → 1    10-14 → 2    15-19 → 3 …
# Levels 1-4 are the low tier and carry no traits at all, so a new character
# meets the difficulty's basic maths before it starts stacking modifiers on top.
# The old formula floored at 1, which handed even a level 1 mob a trait.
func threat_slots() -> int:
	return maxi(0, int(floor(float(enemy_level) / float(THREAT_SLOT_EVERY))))

# Rolls this mob's traits. NORMAL difficulty always yields none, so that mode is
# genuinely the game as it was.
func _roll_enemy_threats() -> void:
	enemy_threats.clear()
	_undying_spent = false
	if not QuestManager.is_relic_difficulty():
		return
	var eligible: Array = []
	for t in ENEMY_THREATS:
		if enemy_level >= int(t["min_level"]):
			eligible.append(str(t["id"]))
	if eligible.is_empty():
		return
	eligible.shuffle()
	var want: int = mini(threat_slots(), eligible.size())
	for i in want:
		enemy_threats.append(eligible[i])

# Metadata rows for every trait this mob carries, in the table's own order so the
# display is stable rather than following the shuffle.
func threat_metas() -> Array:
	var out: Array = []
	for t in ENEMY_THREATS:
		if enemy_threats.has(str(t["id"])):
			out.append(t)
	return out

func _initialize_mob_stats_by_character_tier() -> void:
	enemy_max_health = 80 + (enemy_level * 20)
	if enemy_level <= 1:
		# The very first fight is a teaching fight: the level-1 mob carries no
		# items at all so the player can focus on the Attack/Item basics without
		# the enemy trading blows via a loadout. (The player still gets their own
		# starting items via the supply drop.) Level 2+ is unchanged.
		enemy_item_pool = []
	elif enemy_level <= 5:
		enemy_item_pool = ["potion", "shield"]
		if enemy_level >= 2: enemy_item_pool.append("grindstone")
		if enemy_level >= 3: enemy_item_pool.append("needle")
		if enemy_level >= 4: enemy_item_pool.append("whip")
		if enemy_level >= 5: enemy_item_pool.append("magnet")
	else:
		# Tiers are authored up to 20; anything past that reuses the level 20 kit.
		var pool_key = mini(enemy_level, 20)
		enemy_item_pool = TIER_POOLS_LV6_PLUS.get(
			pool_key, ["potion", "shield", "grindstone", "needle"]).duplicate()
		# Swap every starter tool this tier has outgrown for its upgrade.
		enemy_item_pool = _apply_item_upgrades(enemy_item_pool)
	enemy_health = enemy_max_health
	current_items_per_deal = 1
	_roll_enemy_threats()

func _on_deadzone_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer" and not is_in_combat and not _is_defeated_waiting_respawn:
		player_ref = body
		if is_tutorial_mob and not QuestManager.combat_tutorial_done:
			QuestManager.combat_tutorial_done = true
			QuestManager.has_unsaved_progress = true
			DialogueManager.start([
				{ "name": "", "text": "A fight has started! Combat here is turn-based — you act, then the enemy acts, back and forth." },
				{ "name": "", "text": "On your turn, choose [b]Attack[/b] for basic damage, or use one of your equipped [b]Items[/b] — each does something different: bonus damage, healing, or hindering the enemy." },
				{ "name": "", "text": "Watch both HP bars at the top of the screen. Bring the enemy's to zero before yours hits zero to win!" },
				{ "name": "", "text": "One more thing: a roaming [b]Quartermaster[/b] shadows every brawl in these lands — war is good for their business." },
				{ "name": "", "text": "At set rounds they lob an identical [b]supply crate[/b] to BOTH fighters, keeping it a fair test of skill. Grab what's useful and adapt!" },
				{ "name": "", "text": "Good luck — you've got this!" },
			])
			await DialogueManager.dialogue_finished
		start_combat()

# =============================================================================
#  COMBAT START
# =============================================================================

func start_combat() -> void:
	is_in_combat = true
	QuestManager.is_in_combat = true
	SFX.play(SFX.combat_start)
	SFX.play_combat_music()
	_refresh_level_label_visibility()   # hide the overhead level tag for the fight
	if is_instance_valid(player_ref) and "velocity" in player_ref:
		player_ref.velocity = Vector2.ZERO
	# Fade to black so the camera cut + fighter teleport is hidden.
	await ScreenFade.fade_out()
	enemy_overworld_position = self.global_position
	_initialize_mob_stats_by_character_tier()
	player_inventory.clear(); enemy_inventory.clear()
	_reset_all_combat_modifiers()
	_clear_ground_fx_visibility()
	drop_round_index = 0; cycles_until_drop = 1
	QuestManager.player_health = QuestManager.MAX_HEALTH
	_apply_supply_drop_rewards()
	# Per-fight threat bookkeeping. Set after the modifier reset above, or the
	# reset would wipe it. Nothing is switched ON here — every trait now rolls its
	# own chance when the moment comes (see threat_procs).
	_relentless_extra = false
	_undying_spent = false
	# Threshold-trait counters. The beam mark starts at the enemy's OPENING HP, so
	# the first beam fires when it first falls past a 100 boundary, not instantly.
	_dmg_since_split = 0
	_last_beam_mark = int(floor(float(enemy_health) / float(BEAM_HP_MARK)))
	_dismiss_enemy_clone()
	# Baseline for the Relic's per-round charge accrual (dealt + taken damage).
	_relic_prev_enemy_hp  = enemy_health
	_relic_prev_player_hp = QuestManager.player_health

	if is_instance_valid(player_ref):
		QuestManager.player_overworld_position = player_ref.global_position

	# ── Fighter positioning ───────────────────────────────────────────────────
	# Trust the scene's own authored markers exactly as placed in the editor.
	if is_instance_valid(battle_player_marker):
		player_ref.global_position = battle_player_marker.global_position
	if is_instance_valid(battle_enemy_marker):
		self.global_position = battle_enemy_marker.global_position

	if is_instance_valid(player_ref) and player_ref.has_method("face_right"):
		player_ref.face_right()

	var espr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(espr):
		espr.flip_h = true

	_switch_to_combat_camera()
	if is_instance_valid(combat_ui):
		combat_ui.open_combat_screen(self)
		combat_ui.display_round_history("📦 The Quartermaster tosses both fighters an opening crate.", true)
		combat_ui.start_player_turn()
	# Reveal the combat arena.
	await ScreenFade.fade_in()

# =============================================================================
#  PLAYER ITEM USE
# =============================================================================

func use_player_item(item_type: String) -> void:
	if not item_type in player_inventory: return

	# Phoenix Feather is a PASSIVE charm — it can never be spent by hand, it only
	# fires automatically when you'd die. Refuse without consuming the turn.
	if item_type == "phoenix_feather":
		if combat_ui:
			var msg := "🪶 Phoenix Feather revives you automatically — it can't be used by hand."
			if player_phoenix_cd > 0:
				msg = "🪶 Phoenix Feather is dormant (%d turns) — and it only ever revives you automatically." % player_phoenix_cd
			combat_ui.display_round_history(msg, true)
			combat_ui._refresh_ui_states()
		return

	# A damage buff of a given type can't be stacked with itself in one turn — e.g.
	# using Grindstone again while already sharpened (would let you spam +20s). Same
	# for Overcharge. Refuse without consuming the item/turn.
	if (item_type == "grindstone" and player_sharpened) or (item_type == "overcharge" and player_overcharged):
		if combat_ui:
			var lbl: String = QuestManager.ITEM_META.get(item_type, {}).get("label", item_type.capitalize())
			combat_ui.display_round_history("%s is already active this turn — it can't stack with itself." % lbl, true)
			combat_ui._refresh_ui_states()
		return

	# A second Mirror Clone can't stack on the one already at your side. Refused
	# HERE, before anything is spent — the refusal used to live down in the effect
	# match, by which point a copy had already been erased from the inventory, so
	# a rejected summon silently ate a clone.
	if item_type == "clone" and player_clone_active:
		if combat_ui:
			combat_ui.display_round_history("👥 A clone is already at your side!", true)
			combat_ui._refresh_ui_states()
		return

	# The Relic only fires when its charge is full (its button glows to signal
	# this). Trying early refuses the turn instead of wasting it.
	if item_type == "relic" and not relic_is_charged():
		if combat_ui:
			combat_ui.display_round_history(
				"🏺 The Relic is still gathering power — %d / %d." % [player_relic_charge, relic_charge_needed()], true)
			combat_ui._refresh_ui_states()
		return

	# Per-item use sound (relic also has its unleash cue below). Unfilled slots are
	# silent, so this is safe for every item.
	SFX.item(item_type)

	match item_type:
		"magnet":
			var stealable = enemy_inventory.filter(func(i: String) -> bool:
				return (i in QuestManager.equipped_items) and i != "magnet" and i != "chain_hook"
			)
			if stealable.is_empty():
				if combat_ui:
					combat_ui.display_round_history("🧲 Magnet fizzled — nothing stealable from your loadout!", true)
					combat_ui._refresh_ui_states()
				return
			if combat_ui:
				var chosen = await combat_ui.show_magnet_choice_popup(stealable)
				if chosen != "":
					player_inventory.erase("magnet"); enemy_inventory.erase(chosen)
					player_inventory.append(chosen)
					await _fx_steal("enemy")
					combat_ui.display_round_history("🧲 Magnet swiped [%s]!" % chosen.to_upper(), true)
				else:
					combat_ui.display_round_history("🧲 Magnet cancelled.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return

		"chain_hook":
			player_inventory.erase("chain_hook")
			var valid = enemy_inventory.filter(func(i: String) -> bool:
				return i != "chain_hook" and i != "magnet" and i in QuestManager.equipped_items
			)
			enemy_weakened = true
			if valid.size() > 0:
				var st = valid.pick_random()
				enemy_inventory.erase(st); player_inventory.append(st)
				await _fx_steal("enemy")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Chain Hook yanked [%s] + enemy next attack -20!" % st.to_upper(), true)
			else:
				await _fx_status("enemy", Color(1.0, 0.65, 0.1, 1.0), "⛓️")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Chain Hook — nothing to steal, enemy next attack -20.", true)
			if combat_ui: combat_ui._refresh_ui_states()
			return

		"relic":
			# Signature burst. CONSUMED on use (returns to the crate pool, so the
			# player must hope it drops again). Fixed, unblockable, multiples of
			# ten — never stacks with buffs, never full-heals.
			player_inventory.erase("relic")
			# Double cleanse: strip EVERY enemy buff and EVERY player debuff.
			_relic_strip_enemy_buffs()
			enemy_health = clampi(enemy_health - RELIC_STRIKE_DAMAGE, 0, enemy_max_health)
			_note_enemy_damage(RELIC_STRIKE_DAMAGE)
			QuestManager.heal_player(RELIC_HEAL)   # respects the gold-heart heal cap
			_relic_cleanse_player()
			# Each use raises the future charge requirement (persisted).
			QuestManager.relic_uses += 1          # lifetime stat
			QuestManager.relic_uses_fight += 1    # what actually raises the next charge bar
			QuestManager.has_unsaved_progress = true
			SFX.play(SFX.relic_unleash)
			# The beam IS the relic moment now — a ~2.3s sustained lance in place
			# of the old quarter-second tint flash.
			_float_icon("enemy", "🏺", Color(0.35, 1.0, 0.95))
			await _fx_relic_beam()
			await _fx_damage("enemy")
			await _fx_heal("player")
			# Charge is spent; with the relic gone it won't rebuild until it drops
			# again. Re-baseline so nothing lingering re-adds charge.
			player_relic_charge = 0
			_relic_announced_charged = false
			_relic_prev_enemy_hp  = enemy_health
			_relic_prev_player_hp = QuestManager.player_health
			if combat_ui:
				combat_ui.display_round_history(
					"🏺 ANCIENT RELIC unleashed — %d unblockable damage, +%d HP, your afflictions lifted AND every enemy buff stripped! (spent)" % [RELIC_STRIKE_DAMAGE, RELIC_HEAL], true)
				combat_ui._refresh_ui_states()
			_sync_ground_fx()
			# If that killed the enemy, end the fight right now — no need to also
			# press Attack.
			if await _check_combat_end_conditions(): return
			return

		_:
			player_inventory.erase(item_type)

	match item_type:
		"potion":
			QuestManager.heal_player(20)   # capped at red hearts (no healing gold)
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🧪 Potion (+20 HP)", true)
		"shield":
			player_active_armor = true
			await _fx_status("player", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Shield raised", true)
		"grindstone":
			player_sharpened = true
			player_damage_bonus += 20
			await _fx_status("player", Color(1.0, 0.58, 0.10, 1.0), "🪨")
			if combat_ui: combat_ui.display_round_history(
				"🪨 Grindstone — +20 damage bonus (total bonus: +%d)" % player_damage_bonus, true)
		"whip":
			enemy_is_disarmed = true
			await _fx_status("enemy", Color(1.0, 0.68, 0.10, 1.0), "💥")
			if combat_ui: combat_ui.display_round_history("💥 Whip — enemy turn skipped!", true)
		"needle":
			player_piercing = true
			await _fx_status("player", Color(0.80, 0.55, 1.0, 1.0), "📌")
			if combat_ui: combat_ui.display_round_history("📌 Needle — next hit pierces armor", true)
		"bandage":
			QuestManager.heal_player(10)   # capped at red hearts (no healing gold)
			player_regen_rounds = 2
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🩹 Bandage (+10 HP + regen ×2)", true)
		"poison_dart":
			enemy_poison_rounds = 3
			await _fx_status("enemy", Color(0.22, 0.72, 0.22, 1.0), "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Poison Dart — enemy 10/round ×3", true)
		"lifesteal_vial":
			player_lifesteal_active = true
			await _fx_status("player", Color(0.90, 0.20, 0.40, 1.0), "🩸")
			if combat_ui: combat_ui.display_round_history(
				"🩸 Lifesteal Vial — next attack heals 50% of damage dealt!", true)
		"mirror_ward":
			player_reflect_active = true
			await _fx_status("player", Color(1.0, 0.90, 0.22, 1.0), "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Mirror Ward — next hit fully reflected!", true)
		"smoke_bomb":
			player_dodge_active = true
			await _fx_status("player", Color(0.30, 0.90, 1.0, 1.0), "💨")
			if combat_ui: combat_ui.display_round_history("💨 Smoke Bomb — next attack misses!", true)
		"weaken_totem":
			enemy_cursed = true
			await _fx_status("enemy", Color(0.70, 0.20, 1.0, 1.0), "🗿")
			if combat_ui: combat_ui.display_round_history(
				"🗿 Weaken Totem — enemy attack becomes a 20 HP heal for you!", true)
		"static_field":
			enemy_items_locked = true
			await _fx_status("enemy", Color(0.70, 0.90, 1.0, 1.0), "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Static Field — enemy items locked!", true)
		"time_warp":
			enemy_is_disarmed = true; enemy_stun_extra_turns += 1
			await _fx_status("enemy", Color(0.70, 1.0, 0.95, 1.0), "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Time Warp — enemy skips 2 turns!", true)
		"overcharge":
			player_overcharged = true
			player_damage_bonus += 20
			player_piercing = true
			player_god_pierce = true
			await _fx_status("player", Color(1.0, 0.45, 0.05, 1.0), "🔥")
			if combat_ui: combat_ui.display_round_history(
				"🔥 Overcharge — +20 damage, GUARANTEED hit (pierces shield/dodge/reflect entirely, bonus: +%d)" % player_damage_bonus, true)
		# NOTE: phoenix_feather has no manual case — it's a passive auto-revive
		# only (refused at the top of use_player_item).
		"clone":
			# Mirror Clone: a ghostly double that strikes alongside you next
			# attack (flat 20 first, then your hit) and soaks the enemy's next
			# blow before fading.
			#
			# Do NOT erase "clone" here. The default `_:` arm of the match above
			# already spent one copy — erasing again took a SECOND clone, so
			# using one while holding two dropped you straight to zero.
			await _summon_clone()
			if combat_ui: combat_ui.display_round_history(
				"👥 Mirror Clone summoned — it strikes with you AND shields the next hit!", true)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()

# =============================================================================
#  MIRROR CLONE
# =============================================================================
# ── Enemy clone (Splitter threat) ───────────────────────────────────────────
# The mirror of the player's Mirror Clone: a spectral double that strikes with
# the enemy and soaks the player's next hit before shattering.
var enemy_clone_active: bool = false
var _enemy_clone_node: Node2D = null

func _summon_enemy_clone() -> void:
	var es := _get_sprite("enemy")
	if not is_instance_valid(es) or not is_instance_valid(get_parent()):
		return
	enemy_clone_active = true
	var c := AnimatedSprite2D.new()
	c.sprite_frames = es.sprite_frames
	c.scale = es.scale
	c.animation = es.animation
	c.frame = es.frame
	# Copy the FACING too. The enemy is flipped to face left at combat start; a
	# double built without this looked the wrong way and appeared to attack away
	# from the player.
	c.flip_h = es.flip_h
	c.flip_v = es.flip_v
	c.modulate = Color(1.0, 0.42, 0.42, 0.7)     # spectral RED, to read as "theirs"
	c.z_index = 4
	get_parent().add_child(c)
	_enemy_clone_node = c
	c.global_position = global_position
	SFX.play(SFX.item_clone)
	if combat_ui: combat_ui.display_round_history(
		"👥 SPLITTER — it tears a double out of itself!", false)
	# Steps out toward the player, mirroring how the player's clone advances.
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "global_position", global_position - Vector2(52, 0), 0.22)
	await tw.finished

func _enemy_clone_strike() -> void:
	if not is_instance_valid(_enemy_clone_node):
		return
	var start: Vector2 = _enemy_clone_node.global_position
	var target := start - Vector2(34, 0)
	SFX.mob_attack_snd(enemy_level)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_enemy_clone_node, "global_position", target, 0.14)
	await tw.finished
	QuestManager.player_health = clampi(
		QuestManager.player_health - CLONE_STRIKE_DAMAGE, 0, QuestManager.MAX_HEALTH)
	await _fx_damage("player")
	if combat_ui: combat_ui.display_round_history(
		"👥 Its double strikes for %d!" % CLONE_STRIKE_DAMAGE, false)
	if is_instance_valid(_enemy_clone_node):
		var tw2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_enemy_clone_node, "global_position", start, 0.12)
		await tw2.finished

func _shatter_enemy_clone() -> void:
	if is_instance_valid(_enemy_clone_node):
		SFX.play(SFX.item_clone)
		var c := _enemy_clone_node
		var tw := create_tween().set_parallel(true)
		tw.tween_property(c, "scale", c.scale * 1.5, 0.22)
		tw.tween_property(c, "modulate:a", 0.0, 0.22)
		await tw.finished
		if is_instance_valid(c): c.queue_free()
	_enemy_clone_node = null
	enemy_clone_active = false

func _dismiss_enemy_clone() -> void:
	if is_instance_valid(_enemy_clone_node):
		_enemy_clone_node.queue_free()
	_enemy_clone_node = null
	enemy_clone_active = false

func _summon_clone() -> void:
	if not is_instance_valid(player_ref):
		return
	player_clone_active = true
	_clone_player_home = player_ref.global_position   # the player does NOT move
	# Build the ghostly double from the player's own sprite frames.
	var psprite := player_ref.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_clone_node = AnimatedSprite2D.new()
	if is_instance_valid(psprite):
		_clone_node.sprite_frames = psprite.sprite_frames
		_clone_node.scale = psprite.scale
		_clone_node.animation = psprite.animation
		_clone_node.frame = psprite.frame
		_clone_node.flip_h = false   # face the enemy (to the right)
	_clone_node.modulate = Color(0.35, 0.62, 1.0, 0.7)   # spectral BLUE at 70% opacity
	_clone_node.z_index = 4
	player_ref.get_parent().add_child(_clone_node)
	# Spawn on the player and dash FORWARD toward the enemy — the player stays put.
	_clone_node.global_position = _clone_player_home
	if _clone_node.sprite_frames and _clone_node.sprite_frames.has_animation("WalkSide"):
		_clone_node.play("WalkSide"); _clone_node.speed_scale = 1.0
	var forward := _clone_player_home + Vector2(52, 0)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_clone_node, "global_position", forward, 0.22)
	await tw.finished
	if is_instance_valid(_clone_node) and _clone_node.sprite_frames and _clone_node.sprite_frames.has_animation("WalkSide"):
		_clone_node.play("WalkSide"); _clone_node.frame = 2; _clone_node.speed_scale = 0.0   # idle pose

func _clone_strike() -> void:
	if not is_instance_valid(_clone_node):
		return
	var start := _clone_node.global_position
	var target := global_position - Vector2(30, 0)   # lunge to just left of the enemy
	var spr := _clone_node as AnimatedSprite2D
	# Play the attack swing if the sheet has it (it's a copy of the player frames).
	if spr.sprite_frames and spr.sprite_frames.has_animation("AttackSide"):
		spr.flip_h = false
		spr.speed_scale = 1.0
		spr.play("AttackSide")
	# The clone swings with your attack sound — that impact IS the enemy's hit cue.
	SFX.play(SFX.player_attack, -3.0)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_clone_node, "global_position", target, 0.14)
	await tw.finished
	enemy_health = clampi(enemy_health - CLONE_STRIKE_DAMAGE, 0, enemy_max_health)
	_note_enemy_damage(CLONE_STRIKE_DAMAGE)
	await _fx_damage("enemy")
	if combat_ui: combat_ui.display_round_history("👥 Clone strikes for %d!" % CLONE_STRIKE_DAMAGE, true)
	if is_instance_valid(_clone_node):
		var tw2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw2.tween_property(_clone_node, "global_position", start, 0.12)
		await tw2.finished
		if is_instance_valid(_clone_node) and spr.sprite_frames and spr.sprite_frames.has_animation("WalkSide"):
			spr.play("WalkSide"); spr.frame = 2; spr.speed_scale = 0.0   # back to idle pose

# The clone soaks a hit and shatters (teal flash + expand + fade).
func _shatter_clone() -> void:
	if is_instance_valid(_clone_node):
		SFX.play(SFX.item_clone)
		var c := _clone_node
		var tw := create_tween()
		tw.tween_property(c, "modulate", Color(0.6, 1.0, 1.0, 0.0), 0.24)
		tw.parallel().tween_property(c, "scale", c.scale * 1.35, 0.24)
		tw.tween_callback(c.queue_free)
	_clone_node = null
	player_clone_active = false
	_restore_player_home()

func _dismiss_clone() -> void:
	if is_instance_valid(_clone_node):
		_clone_node.queue_free()
	_clone_node = null
	player_clone_active = false
	_restore_player_home()

func _restore_player_home() -> void:
	if is_instance_valid(player_ref) and _clone_player_home != Vector2.ZERO:
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(player_ref, "global_position", _clone_player_home, 0.15)
		_clone_player_home = Vector2.ZERO

# The enemy charges the clone at its actual position (front/above/below), lands
# the hit, then returns — so the clone visibly takes the blow, not the player.
func _enemy_lunge_at_clone() -> void:
	if not is_instance_valid(_clone_node):
		return
	var estart := global_position
	var ct := _clone_node.global_position
	var to := ct - estart
	var target := estart + (to.normalized() * maxf(to.length() - 22.0, 0.0) if to.length() > 0.001 else Vector2.ZERO)
	var espr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(espr): espr.flip_h = true
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target, 0.18)
	await tw.finished
	# quick impact shudder on the clone
	if is_instance_valid(_clone_node):
		var cp := _clone_node.global_position
		for _i in range(3):
			_clone_node.global_position = cp + Vector2(randf_range(-4, 4), randf_range(-3, 3))
			await get_tree().create_timer(0.04).timeout
		_clone_node.global_position = cp
	var tw2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw2.tween_property(self, "global_position", estart, 0.15)
	await tw2.finished

# =============================================================================
#  PLAYER ATTACK PHASE
# =============================================================================

func process_player_attack_phase() -> void:
	if player_items_locked: player_items_locked = false

	# ── Your side acts, one readable beat at a time ──────────────────────────
	# YOU swing first, then your Mirror Clone follows up. Each combatant travels
	# to its own target and its result lands before the next one moves, so all
	# four board states read clearly:
	#
	#   1. you            v enemy           — you hit the enemy.
	#   2. you + clone    v enemy           — you hit it, then your clone does.
	#   3. you            v enemy + double  — you cut down the double; the mob is
	#                                         untouched behind it.
	#   4. you + clone    v enemy + double  — you cut down the double, THEN your
	#                                         clone goes on to hit the mob.
	#
	# Previously the lunge was fired from CombatUI before any of this ran, so the
	# player always charged the mob itself and the double just evaporated where it
	# stood — and the clone struck at the same time with nothing separating them.
	if player_is_disarmed:
		player_is_disarmed = false
		if player_stun_extra_turns > 0:
			player_stun_extra_turns -= 1; player_is_disarmed = true
		player_damage_bonus = 0; player_sharpened = false; player_overcharged = false
		player_lifesteal_active = false; player_god_pierce = false
		await _player_lunge(null, true)
		await _fx_status("player", Color(1.0, 0.68, 0.10, 1.0), "❌")
		if combat_ui:
			combat_ui.display_round_history("💥 DISARMED — your attack was skipped!", true)
		_sync_ui()
	else:
		await _resolve_player_swing()
		if not is_in_combat: return
		if await _check_combat_end_conditions(): return

	# The clone is a SECOND combatant taking its own turn — never simultaneous
	# with yours. A disarm silences your swing, not the double you summoned.
	if player_clone_active:
		await get_tree().create_timer(ACTION_PAUSE).timeout
		if not is_in_combat: return
		await _clone_strike()
		if await _check_combat_end_conditions(): return

	_sync_ground_fx()
	_sync_ui()
	await get_tree().create_timer(ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return
	if combat_ui: combat_ui.start_enemy_turn_visuals()
	await get_tree().create_timer(1.0).timeout
	_execute_enemy_turn_ai()

# Runs the player to `target` and back. `target` null (or a disarmed swing) just
# shakes them in place. Targeting lives here rather than in CombatUI because only
# the combat state knows whether a double is standing in the way.
func _player_lunge(target: Node2D, disarmed: bool = false) -> void:
	if not is_instance_valid(player_ref) or not player_ref.has_method("do_attack_lunge"):
		return
	var pos: Vector2 = target.global_position if is_instance_valid(target) else player_ref.global_position
	await player_ref.do_attack_lunge(pos, target, disarmed)

# The player's own swing: picks its target, travels to it, and resolves.
func _resolve_player_swing() -> void:
	# The enemy's double throws itself in the way, exactly as your Mirror Clone
	# does — so it is what you RUN AT, and it eats the whole hit whatever its
	# size, even a pierce, then shatters. The mob behind it is untouched.
	if enemy_clone_active and is_instance_valid(_enemy_clone_node):
		await _player_lunge(_enemy_clone_node)
		# Spent on the double, buffs and all — the mirror of how your clone eats
		# the enemy's one-shots.
		player_damage_bonus = 0; player_sharpened = false; player_overcharged = false
		player_god_pierce = false; player_piercing = false
		player_cursed = false; player_lifesteal_active = false
		await _shatter_enemy_clone()
		if combat_ui: combat_ui.display_round_history(
			"👥 Its double threw itself in the way and shattered — the mob is untouched!", true)
		_sync_ui()
		return

	var dmg = 20 + player_damage_bonus
	player_damage_bonus = 0; player_sharpened = false; player_overcharged = false
	if player_weakened:
		dmg = maxi(0, dmg - 20)
		player_weakened = false
	# IRONHIDE: soaks a flat 10 off everything you swing.
	if threat_procs("ironhide"):
		dmg = maxi(0, dmg - 10)
	# EVASIVE: rolls its own dodge, then falls through to the normal dodge branch
	# below so the miss reads exactly like a smoke bomb.
	if not enemy_dodge_active and threat_procs("evasive"):
		enemy_dodge_active = true

	var actual_dmg_dealt := 0

	await _player_lunge(self)

	if player_god_pierce:
		# Overcharge: the hit is guaranteed to land no matter what the enemy has
		# active — it ignores this attack being cursed, and it pierces straight
		# through dodge, reflect, and shield. Shield itself is left standing
		# (pierced, not broken), matching how needle behaves; dodge/reflect are
		# consumed since they tried and failed to stop a guaranteed hit.
		player_god_pierce = false
		if player_piercing: player_piercing = false
		player_cursed = false
		enemy_dodge_active = false
		enemy_reflect_active = false
		enemy_health = clampi(enemy_health - dmg, 0, enemy_max_health)
		_note_enemy_damage(dmg)
		actual_dmg_dealt = dmg
		await _fx_status("enemy", Color(1.0, 0.45, 0.05, 1.0), "🔥")
		await _fx_damage("enemy")
		SFX.play(SFX.player_crit)
		if combat_ui: combat_ui.display_round_history("🔥 OVERCHARGED HIT — %d damage, every defense pierced!" % dmg, true)
	elif player_cursed:
		player_cursed = false
		player_lifesteal_active = false
		var cursed_heal := _enemy_heal(20)
		await _fx_status("player", Color(0.70, 0.20, 1.0, 1.0), "🗿")
		if cursed_heal > 0:
			await _fx_heal("enemy")
		if combat_ui: combat_ui.display_round_history(
			"🗿 CURSED — 0 dmg, healed enemy %d HP!" % cursed_heal if cursed_heal > 0
			else "🗿 CURSED — your attack was wasted!", true)
	elif enemy_dodge_active:
		enemy_dodge_active = false
		player_lifesteal_active = false
		SFX.play(SFX.player_dodge)
		await _fx_status("enemy", Color(0.30, 0.90, 1.0, 1.0), "💨")
		if combat_ui: combat_ui.display_round_history("💨 Enemy dodged — missed!", true)
	elif enemy_reflect_active:
		enemy_reflect_active = false
		player_lifesteal_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - dmg, 0, QuestManager.MAX_HEALTH)
		await _fx_status("enemy", Color(1.0, 0.90, 0.22, 1.0), "🪞")
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("🪞 REFLECTED — %d dmg bounced back at you!" % dmg, true)
	elif enemy_active_armor and not player_piercing:
		enemy_active_armor = false
		player_lifesteal_active = false
		SFX.play(SFX.player_block)
		await _fx_status("enemy", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Enemy shield blocked your hit!", true)
	else:
		if player_piercing: player_piercing = false
		enemy_health = clampi(enemy_health - dmg, 0, enemy_max_health)
		_note_enemy_damage(dmg)
		actual_dmg_dealt = dmg
		await _fx_damage("enemy")
		if combat_ui: combat_ui.display_round_history("⚔️ You attacked for %d damage!" % dmg, true)

	if player_lifesteal_active:
		player_lifesteal_active = false
		if actual_dmg_dealt > 0:
			var steal_heal = actual_dmg_dealt / 2
			# Must go through heal_player() — writing player_health directly skipped
			# the red-heart cap and let lifesteal top you up inside the gold zone.
			QuestManager.heal_player(steal_heal)
			await _fx_heal("player")
			if combat_ui: combat_ui.display_round_history("🩸 Lifesteal — healed %d HP!" % steal_heal, true)

	# THORNED: landing a hit costs you 10 — the price of touching it.
	if actual_dmg_dealt > 0 and threat_procs("thorned"):
		QuestManager.player_health = clampi(QuestManager.player_health - 10, 0, QuestManager.MAX_HEALTH)
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history(
			"📌 THORNED — its hide tears you for 10 as you strike!", true)

	_sync_ui()

# =============================================================================
#  ENEMY AI TURN
# =============================================================================

func _execute_enemy_turn_ai() -> void:
	if enemy_is_disarmed:
		enemy_is_disarmed = false
		if enemy_stun_extra_turns > 0:
			enemy_stun_extra_turns -= 1; enemy_is_disarmed = true
		enemy_damage_bonus = 0; enemy_sharpened = false
		enemy_overcharged  = false; enemy_lifesteal_active = false; enemy_god_pierce = false
		await _fx_status("enemy", Color(1.0, 0.68, 0.10, 1.0), "❌")
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, true)
		if combat_ui: combat_ui.display_round_history("💥 Enemy disarmed — turn skipped!", false)
		await _conclude_round_cycle_ticks()
		return

	# Threshold traits resolve first: a Splitter double appears and a Relicbound
	# beam falls before the enemy acts, never mid-swing.
	await _run_threshold_threats()
	if not is_in_combat: return
	if enemy_clone_active:
		await _enemy_clone_strike()
		if await _check_combat_end_conditions(): return
		# The double's hit is its own beat — let it land before the enemy's own
		# turn starts, or the two attacks read as a single event.
		await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
		if not is_in_combat: return

	# ── Start-of-round threat rolls ──────────────────────────────────────────
	# WARDED re-raises its mirror on a roll rather than being permanently up.
	if not enemy_reflect_active and threat_procs("warded"):
		enemy_reflect_active = true
		await _fx_status("enemy", Color(1.0, 0.90, 0.22, 1.0), "🪞")
		if combat_ui: combat_ui.display_round_history(
			"🪞 WARDED — a reflecting ward shimmers into place!", false)
		await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
		if not is_in_combat: return
	# JAMMER shorts out your kit. Same anti-lockout rule as Static Field: never
	# applied on a round you're already disarmed, so you keep one legal move.
	if not player_is_disarmed and player_stun_extra_turns <= 0 and not player_items_locked \
			and threat_procs("jammer"):
		player_items_locked = true
		await _fx_status("player", Color(0.70, 0.90, 1.0, 1.0), "⚡")
		if combat_ui: combat_ui.display_round_history(
			"⚡ JAMMER — your items are shorted out this round!", false)
		await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
		if not is_in_combat: return

	var tracking: Dictionary = {}
	var sg_eval := false

	if enemy_items_locked:
		enemy_items_locked = false
		await _fx_status("enemy", Color(0.70, 0.90, 1.0, 1.0), "⚡")
		if combat_ui: combat_ui.display_round_history("⚡ Enemy items LOCKED — basic attack only!", false)
		await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
	else:
		var going := true
		while going:
			var pick := ""
			# Gate heal items on the HEAL CAP, not on max health: a mob spawned above
			# the red-heart ceiling (e.g. 340/380) is "wounded" by max but can't be
			# healed at all, and picking a potion there burnt the item and the turn
			# for nothing while the log claimed a heal.
			if enemy_health <= enemy_heal_cap() - 20 and enemy_inventory.has("potion") and tracking.get("potion", 0) < 1:
				pick = "potion"
			elif enemy_health <= enemy_heal_cap() - 20 and enemy_inventory.has("bandage") and tracking.get("bandage", 0) < 1:
				pick = "bandage"
			# `not player_items_locked` here is the mirror of the Static Field gate
			# below: whichever lock lands first, the other is held back, so the
			# player is never left unable to both attack AND use an item.
			elif not player_is_disarmed and not player_items_locked and enemy_health <= enemy_max_health * 0.4 and enemy_inventory.has("time_warp") and tracking.get("time_warp", 0) < 1:
				pick = "time_warp"
			elif not player_is_disarmed and not player_items_locked and enemy_inventory.has("whip") and tracking.get("whip", 0) < 1:
				pick = "whip"
			elif not enemy_dodge_active and enemy_inventory.has("smoke_bomb") and tracking.get("smoke_bomb", 0) < 1 and randf() < 0.35:
				pick = "smoke_bomb"
			elif not enemy_reflect_active and not enemy_dodge_active and enemy_inventory.has("mirror_ward") and tracking.get("mirror_ward", 0) < 1 and randf() < 0.35:
				pick = "mirror_ward"
			elif player_active_armor and enemy_inventory.has("grindstone") and tracking.get("grindstone", 0) < 1 and not sg_eval:
				sg_eval = true
				if randf() < 0.5:
					pick = "grindstone"
				else:
					tracking["grindstone"] = 1
			elif player_active_armor and enemy_inventory.has("needle") and tracking.get("needle", 0) < 1 and not enemy_piercing:
				pick = "needle"
			elif not enemy_active_armor and enemy_inventory.has("shield") and tracking.get("shield", 0) < 1:
				pick = "shield"
			elif not enemy_sharpened and enemy_inventory.has("grindstone") and tracking.get("grindstone", 0) < 1:
				pick = "grindstone"
			elif not enemy_lifesteal_active and enemy_inventory.has("lifesteal_vial") and tracking.get("lifesteal_vial", 0) < 1:
				pick = "lifesteal_vial"
			elif enemy_poison_rounds <= 0 and enemy_inventory.has("poison_dart") and tracking.get("poison_dart", 0) < 1:
				pick = "poison_dart"
			elif not player_cursed and enemy_inventory.has("weaken_totem") and tracking.get("weaken_totem", 0) < 1 and randf() < 0.6:
				pick = "weaken_totem"
			# Static Field locks ITEMS; whip / time warp disarm the ATTACK. They are
			# separate locks, so stacking them leaves the player with no legal
			# action at all — a dead turn they just watch. Hold the field back
			# until the player can actually act (also skipped while a time-warp
			# stun is still queued for a following turn).
			elif not player_items_locked and not player_is_disarmed and player_stun_extra_turns <= 0 and enemy_inventory.has("static_field") and tracking.get("static_field", 0) < 1 and randf() < 0.45:
				pick = "static_field"
			elif player_inventory.size() >= 2 and enemy_inventory.has("chain_hook") and tracking.get("chain_hook", 0) < 1:
				pick = "chain_hook"
			elif player_inventory.size() > 0 and enemy_inventory.has("magnet") and tracking.get("magnet", 0) < 1:
				pick = "magnet"
			elif enemy_health <= enemy_max_health * 0.3 and enemy_inventory.has("overcharge") and tracking.get("overcharge", 0) < 1:
				pick = "overcharge"

			if pick != "":
				await _enemy_execute_item(pick, tracking)
				if not is_in_combat: return
				await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
			else:
				going = false

	if not is_in_combat: return

	# The enemy commits to its swing — per-LEVEL attack sound (falls back to
	# enemy_attack_default when that level's slot is empty).
	SFX.mob_attack_snd(enemy_level)

	var raw = 20 + enemy_damage_bonus
	# BRUTAL / CORNERED: flat +10s, kept multiples of ten so the heart display
	# stays exact (there is no half-heart art).
	if threat_procs("brutal"):
		raw += 10
	if enemy_health * 2 <= enemy_max_health and threat_procs("cornered"):
		raw += 10
	enemy_damage_bonus = 0; enemy_sharpened = false; enemy_overcharged = false
	if enemy_weakened:
		raw = maxi(0, raw - 20)
		enemy_weakened = false

	var actual_dmg_to_player := 0

	if player_clone_active:
		# The Mirror Clone soaks this hit ENTIRELY (any size, even piercing) and
		# shatters. The enemy charges the CLONE at wherever it stands, not the
		# player. The enemy's offensive one-shots are spent on it.
		enemy_god_pierce = false; enemy_piercing = false; enemy_cursed = false
		enemy_lifesteal_active = false
		await _enemy_lunge_at_clone()
		await _shatter_clone()
		if combat_ui: combat_ui.display_round_history("👥 Your clone threw itself in the way and shattered — no damage!", false)
	elif enemy_god_pierce:
		# Mirror of the player's Overcharge — guaranteed hit, ignores this attack
		# being cursed, and pierces straight through dodge/reflect/shield.
		enemy_god_pierce = false
		if enemy_piercing: enemy_piercing = false
		enemy_cursed = false
		player_dodge_active = false
		player_reflect_active = false
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		actual_dmg_to_player = raw
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("enemy", Color(1.0, 0.45, 0.05, 1.0), "🔥")
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("🔥 Enemy OVERCHARGED HIT — %d damage, every defense pierced!" % raw, false)
	elif enemy_cursed:
		enemy_cursed = false
		enemy_lifesteal_active = false
		QuestManager.heal_player(20)   # capped: the curse heal can't push you into gold
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_status("enemy", Color(0.70, 0.20, 1.0, 1.0))
		await _fx_heal("player")
		if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed — 0 dmg, you healed 20 HP!", false)
	elif player_dodge_active:
		player_dodge_active = false
		enemy_lifesteal_active = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		SFX.play(SFX.player_dodge)
		await _fx_status("player", Color(0.30, 0.90, 1.0, 1.0), "💨")
		if combat_ui: combat_ui.display_round_history("💨 DODGED — enemy attack missed!", false)
	elif player_reflect_active:
		player_reflect_active = false
		enemy_lifesteal_active = false
		enemy_health = clampi(enemy_health - raw, 0, enemy_max_health)
		_note_enemy_damage(raw)
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		SFX.play(SFX.player_reflect)
		await _fx_status("player", Color(1.0, 0.90, 0.22, 1.0), "🪞")
		await _fx_damage("enemy")
		if combat_ui: combat_ui.display_round_history(
			"🪞 REFLECTED — %d dmg bounced back at the enemy!" % raw, false)
	elif player_active_armor and not enemy_piercing:
		player_active_armor = false
		enemy_lifesteal_active = false
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		SFX.play(SFX.player_block)
		await _fx_status("player", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
		if combat_ui: combat_ui.display_round_history("🛡️ Your shield blocked the hit!", false)
	elif enemy_piercing:
		enemy_piercing = false
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		actual_dmg_to_player = raw
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("📌 Enemy needle pierced for %d dmg!" % raw, false)
	else:
		QuestManager.player_health = clampi(QuestManager.player_health - raw, 0, QuestManager.MAX_HEALTH)
		actual_dmg_to_player = raw
		if is_instance_valid(player_ref) and player_ref.has_method("do_enemy_lunge"):
			await player_ref.do_enemy_lunge(self, player_ref.global_position, false)
		await _fx_damage("player")
		if combat_ui: combat_ui.display_round_history("⚔️ Enemy dealt %d damage!" % raw, false)

	if enemy_lifesteal_active:
		enemy_lifesteal_active = false
		if actual_dmg_to_player > 0:
			var steal_heal = actual_dmg_to_player / 2
			# Silent when it drew nothing (enemy already past healing) — no log spam.
			var stolen := _enemy_heal(steal_heal)
			if stolen > 0:
				await _fx_heal("enemy")
				if combat_ui: combat_ui.display_round_history("🩸 Enemy lifesteal — healed %d HP!" % stolen, false)

	# ── Threat traits that fire off a landed hit ─────────────────────────────
	# Separate ifs, not a match: a mob can carry several of these at once.
	if actual_dmg_to_player > 0:
		if threat_procs("venomous"):
			# Refreshes rather than stacks, so it can't spiral out of control.
			player_poison_rounds = maxi(player_poison_rounds, 2)
			await _fx_status("player", Color(0.28, 0.82, 0.28, 1.0), "☠")
			if combat_ui: combat_ui.display_round_history(
				"☠️ VENOMOUS — its strike leaves you poisoned!", false)
		if threat_procs("leeching"):
			var drained := _enemy_heal(10)
			if drained > 0:
				await _fx_heal("enemy")
				if combat_ui: combat_ui.display_round_history(
					"🩸 LEECHING — it drank %d HP from the wound." % drained, false)
		if not player_weakened and threat_procs("hexer"):
			player_weakened = true
			await _fx_status("player", Color(0.70, 0.20, 1.0, 1.0), "🗿")
			if combat_ui: combat_ui.display_round_history(
				"🗿 HEXER — your next swing is weakened!", false)
		# Disarm obeys the same anti-lockout rule as whip/static field: never
		# applied on top of an item lock, so you always keep one legal move.
		if not player_is_disarmed and not player_items_locked and threat_procs("disarming"):
			player_is_disarmed = true
			await _fx_status("player", Color(1.0, 0.68, 0.10, 1.0), "❌")
			if combat_ui: combat_ui.display_round_history(
				"❌ DISARMING — it knocks your next swing aside!", false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	await get_tree().create_timer(ENEMY_ACTION_PAUSE).timeout
	if await _check_combat_end_conditions(): return

	# ── RELENTLESS: one extra full action ────────────────────────────────────
	# Re-enters this same turn once. The guard stops it chaining, and the nested
	# call is the one that runs the end-of-round ticks — otherwise poison and
	# regen would tick twice for a single round.
	if not _relentless_extra and threat_procs("relentless"):
		_relentless_extra = true
		if combat_ui: combat_ui.display_round_history("⏳ RELENTLESS — it moves again!", false)
		await _execute_enemy_turn_ai()
		_relentless_extra = false
		return

	await _conclude_round_cycle_ticks()

# =============================================================================
#  ENEMY ITEM EXECUTION
# =============================================================================

func _enemy_execute_item(item_type: String, tracking: Dictionary) -> void:
	if not enemy_inventory.has(item_type): return
	# HARD BLOCK: a healing item cannot be used at all while the enemy sits in
	# gold health (above the red-heart ceiling) — that overheal is unhealable, so
	# using one would burn the item and the turn for zero effect. Refused here as
	# well as in the AI's pick gate, so no future code path can sneak one through.
	if item_type in HEAL_ITEMS and enemy_health >= enemy_heal_cap():
		return
	enemy_inventory.erase(item_type)
	tracking[item_type] = tracking.get(item_type, 0) + 1

	match item_type:
		"potion":
			var healed := _enemy_heal(20)
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history("🧪 Enemy Potion (+%d HP)" % healed, false)
		"shield":
			enemy_active_armor = true
			await _fx_status("enemy", Color(0.50, 0.76, 1.0, 1.0), "🛡️")
			if combat_ui: combat_ui.display_round_history("🛡️ Enemy Shield raised", false)
		"grindstone":
			enemy_sharpened = true
			enemy_damage_bonus += 20
			await _fx_status("enemy", Color(1.0, 0.58, 0.10, 1.0), "🪨")
			if combat_ui: combat_ui.display_round_history(
				"🪨 Enemy Grindstone — +20 damage (total: +%d)" % enemy_damage_bonus, false)
		"whip":
			player_is_disarmed = true
			await _fx_status("player", Color(1.0, 0.68, 0.10, 1.0), "💥")
			if combat_ui: combat_ui.display_round_history("💥 Enemy Whip — YOUR turn skipped!", false)
		"needle":
			enemy_piercing = true
			await _fx_status("enemy", Color(0.80, 0.55, 1.0, 1.0), "📌")
			if combat_ui: combat_ui.display_round_history("📌 Enemy Needle — next hit pierces armor", false)
		"bandage":
			var healed := _enemy_heal(10)
			enemy_regen_rounds = 2
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history(
				"🩹 Enemy Bandage (+%d HP + regen ×2)" % healed, false)
		"poison_dart":
			player_poison_rounds = 3
			await _fx_status("player", Color(0.22, 0.72, 0.22, 1.0), "☠️")
			if combat_ui: combat_ui.display_round_history("☠️ Enemy poisoned you! (10/round ×3)", false)
		"lifesteal_vial":
			enemy_lifesteal_active = true
			await _fx_status("enemy", Color(0.90, 0.20, 0.40, 1.0), "🩸")
			if combat_ui: combat_ui.display_round_history(
				"🩸 Enemy Lifesteal Vial — their next attack heals them 50%!", false)
		"mirror_ward":
			enemy_reflect_active = true
			await _fx_status("enemy", Color(1.0, 0.90, 0.22, 1.0), "🪞")
			if combat_ui: combat_ui.display_round_history("🪞 Enemy Mirror Ward — your next hit reflected!", false)
		"smoke_bomb":
			enemy_dodge_active = true
			await _fx_status("enemy", Color(0.30, 0.90, 1.0, 1.0), "💨")
			if combat_ui: combat_ui.display_round_history("💨 Enemy Smoke Bomb — your next attack misses!", false)
		"weaken_totem":
			player_cursed = true
			await _fx_status("player", Color(0.70, 0.20, 1.0, 1.0), "🗿")
			if combat_ui: combat_ui.display_round_history("🗿 Enemy cursed your next attack!", false)
		"static_field":
			player_items_locked = true
			await _fx_status("player", Color(0.70, 0.90, 1.0, 1.0), "⚡")
			if combat_ui: combat_ui.display_round_history("⚡ Enemy locked your items next turn!", false)
		"time_warp":
			player_is_disarmed = true; player_stun_extra_turns += 1
			await _fx_status("player", Color(0.70, 1.0, 0.95, 1.0), "⏳")
			if combat_ui: combat_ui.display_round_history("⏳ Enemy Time Warp — you skip 2 turns!", false)
		"overcharge":
			enemy_overcharged = true
			enemy_damage_bonus += 20
			enemy_piercing = true
			enemy_god_pierce = true
			await _fx_status("enemy", Color(1.0, 0.45, 0.05, 1.0), "🔥")
			if combat_ui: combat_ui.display_round_history("🔥 Enemy Overcharge — +20 damage, GUARANTEED hit, pierces shield/dodge/reflect entirely!", false)
		"chain_hook":
			var valid = player_inventory.filter(func(i: String) -> bool:
				return i != "chain_hook" and i != "magnet" and i in enemy_item_pool
			)
			player_weakened = true
			if valid.size() > 0:
				var st = valid.pick_random()
				player_inventory.erase(st); enemy_inventory.append(st)
				await _fx_steal("player")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Enemy Chain Hook stole [%s] + your next attack -20!" % st, false)
			else:
				await _fx_status("player", Color(1.0, 0.65, 0.1, 1.0), "⛓️")
				if combat_ui: combat_ui.display_round_history(
					"⛓️ Enemy Chain Hook — nothing stealable, your next attack -20.", false)
		"magnet":
			var valid = player_inventory.filter(func(i: String) -> bool:
				return i != "magnet" and i != "chain_hook" and i in enemy_item_pool
			)
			if valid.size() > 0:
				var st := ""
				if valid.has("needle"):       st = "needle"
				elif valid.has("grindstone"): st = "grindstone"
				elif valid.has("shield"):     st = "shield"
				else:                         st = valid.pick_random()
				player_inventory.erase(st); enemy_inventory.append(st)
				await _fx_steal("player")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet stole [%s]!" % st, false)
			else:
				enemy_inventory.append("magnet")
				if combat_ui: combat_ui.display_round_history("🧲 Enemy Magnet fizzled.", false)

	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()

# =============================================================================
#  ROUND TICKS
# =============================================================================

func _conclude_round_cycle_ticks() -> void:
	await _process_dot_hot_ticks()
	# Feed the Relic: every point of damage that changed hands this round (dealt
	# to the enemy + taken by the player) builds charge, no matter the source.
	# The Relic only charges while it's actually in the bag — you can't bank
	# progress toward it before it drops (not a proactive system). If it isn't
	# held, its charge sits at zero.
	if player_inventory.has("relic"):
		var dealt := maxi(0, _relic_prev_enemy_hp  - enemy_health)
		var taken := maxi(0, _relic_prev_player_hp - QuestManager.player_health)
		if dealt + taken > 0:
			player_relic_charge += dealt + taken
	else:
		player_relic_charge = 0
		_relic_announced_charged = false
	_relic_prev_enemy_hp  = enemy_health
	_relic_prev_player_hp = QuestManager.player_health
	# One-shot callout the moment the Relic finishes charging.
	if not _relic_announced_charged and relic_is_charged():
		_relic_announced_charged = true
		if combat_ui:
			SFX.play(SFX.relic_ready)
			combat_ui.display_round_history("🏺✨ The Ancient Relic is FULLY CHARGED — unleash it!", true)
	_sync_ground_fx()
	if combat_ui: combat_ui._refresh_ui_states()
	if await _check_combat_end_conditions(): return
	cycles_until_drop -= 1
	if cycles_until_drop <= 0:
		_apply_supply_drop_rewards()
		SFX.play(SFX.crate_drop)
		if combat_ui: combat_ui.display_round_history("📦 The Quartermaster lobs in a matched crate — both fighters resupply!", true)
	if combat_ui:
		combat_ui.start_player_turn()
		combat_ui._refresh_ui_states()

func _process_dot_hot_ticks() -> void:
	if player_poison_rounds > 0:
		player_poison_rounds -= 1
		QuestManager.player_health = clampi(QuestManager.player_health - 10, 0, QuestManager.MAX_HEALTH)
		await _fx_poison_tick("player")
		if combat_ui: combat_ui.display_round_history(
			"☠️ Poison ticked — 10 dmg (%d left)" % player_poison_rounds, true)
	if enemy_poison_rounds > 0:
		enemy_poison_rounds -= 1
		enemy_health = clampi(enemy_health - 10, 0, enemy_max_health)
		_note_enemy_damage(10)
		await _fx_poison_tick("enemy")
		if combat_ui: combat_ui.display_round_history(
			"☠️ Enemy poison ticked — 10 dmg (%d left)" % enemy_poison_rounds, true)
	if player_regen_rounds > 0:
		player_regen_rounds -= 1
		QuestManager.heal_player(10)   # capped at red hearts
		await _fx_heal("player")
		if combat_ui: combat_ui.display_round_history(
			"🩹 Regen healed 10 HP (%d left)" % player_regen_rounds, true)
	if enemy_regen_rounds > 0:
		enemy_regen_rounds -= 1
		# Silent when it heals nothing (enemy in gold) — no log spam.
		var regened := _enemy_heal(10)
		if regened > 0:
			await _fx_heal("enemy")
			if combat_ui: combat_ui.display_round_history(
				"🩹 Enemy regen +%d HP (%d left)" % [regened, enemy_regen_rounds], true)
	# The Phoenix cooldown counts down on the same round cadence.
	if player_phoenix_cd > 0:
		player_phoenix_cd -= 1
	if (player_poison_rounds + enemy_poison_rounds + player_regen_rounds + enemy_regen_rounds) > 0:
		await get_tree().create_timer(0.30).timeout

# Puts the Phoenix on cooldown after an activation. The base window climbs by
# +1 with each use this fight so repeated revives get progressively riskier.
func _trigger_phoenix_cooldown() -> void:
	player_phoenix_uses += 1
	player_phoenix_cd = PHOENIX_BASE_COOLDOWN + (player_phoenix_uses - 1)

# Enemy healing obeys the same gold-heart rule as the player: it can only ever
# restore up to the red-heart cap (300), never its bonus gold HP.
# Heals the enemy and RETURNS THE HP ACTUALLY GAINED — which is 0 while it sits
# in gold health (above the red-heart ceiling), since that overheal is a
# per-fight bonus and can't be topped up. Callers must report this return value
# rather than the amount they asked for: the combat log used to print
# "Enemy Bandage (+10 HP)" during gold health when nothing had healed, which
# read exactly like the enemy cheating.
func _enemy_heal(amount: int) -> int:
	var cap := maxi(enemy_heal_cap(), enemy_health)
	var before := enemy_health
	enemy_health = clampi(enemy_health + amount, 0, cap)
	var gained := enemy_health - before
	if gained > 0:
		# Same heal cue the player gets (falls back to it when no enemy-specific
		# clip is assigned), so healing reads the same for both sides.
		SFX.play(SFX.enemy_heal if SFX.enemy_heal else SFX.player_heal)
	return gained

# The highest HP a heal can carry the enemy to: the red-heart ceiling, or its max
# if that's lower. Anything above this is unhealable gold.
func enemy_heal_cap() -> int:
	return mini(enemy_max_health, QuestManager.HP_PER_LAP)

# Phoenix death→rebirth flourish: the player goes limp for a beat (a faked death
# cycle, since there's no death animation), then flashes golden and rises.
# `target` is "player" for the Phoenix Feather or "enemy" for the Undying threat
# — the death beat and golden rebirth are identical, only the sprite differs.
func _play_phoenix_revive(target: String = "player") -> void:
	var spr := _get_sprite(target)
	if not is_instance_valid(spr):
		await get_tree().create_timer(0.8).timeout
		return
	var home_rot := spr.rotation
	var home_pos := spr.position
	# 1) Death beat — darken, keel over, sink; hold one cycle.
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(spr, "modulate", Color(0.22, 0.22, 0.28, 1.0), 0.35)
	t1.tween_property(spr, "rotation", home_rot + deg_to_rad(80), 0.35)
	t1.tween_property(spr, "position", home_pos + Vector2(0, 6), 0.35)
	await t1.finished
	await get_tree().create_timer(0.5).timeout
	# 2) Golden rebirth — pulse gold a few times while righting.
	for _i in range(3):
		spr.modulate = Color(2.3, 1.8, 0.6, 1.0)
		await get_tree().create_timer(0.12).timeout
		spr.modulate = Color(1.0, 0.85, 0.4, 1.0)
		await get_tree().create_timer(0.10).timeout
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(spr, "rotation", home_rot, 0.25)
	t2.tween_property(spr, "position", home_pos, 0.25)
	t2.tween_property(spr, "modulate", Color.WHITE, 0.3)
	await t2.finished

func _apply_supply_drop_rewards() -> void:
	drop_round_index += 1
	var items_this_drop = min(drop_round_index, 6)
	current_items_per_deal = items_this_drop
	const DROP_SCHEDULE = [1, 2, 4, 6, 8]
	cycles_until_drop = DROP_SCHEDULE[min(drop_round_index, DROP_SCHEDULE.size() - 1)]
	for _i in range(items_this_drop):
		if QuestManager.equipped_items.size() > 0:
			var pick: String = QuestManager.equipped_items.pick_random()
			# Some items cap at ONE copy in the bag (relic, phoenix). If the player
			# already holds it, that crate slot rolls a different equipped item
			# instead (so a loadout can't stockpile game-ending copies).
			if pick in MAX_ONE_ITEMS and player_inventory.has(pick):
				var alt := QuestManager.equipped_items.filter(func(i: String) -> bool:
					return not (i in MAX_ONE_ITEMS and player_inventory.has(i)))
				pick = alt.pick_random() if alt.size() > 0 else "potion"
			player_inventory.append(pick)
		if enemy_item_pool.size() > 0:
			enemy_inventory.append(enemy_item_pool.pick_random())

# Wipes every status effect on the PLAYER only (buffs and debuffs alike), leaving
# the enemy's state intact. Used by the Phoenix revive so you return to the fight
# with a clean slate — no lingering stun, poison, curse, regen or damage bonus.
func _clear_player_status() -> void:
	player_active_armor = false
	player_sharpened = false
	player_overcharged = false
	player_piercing = false
	player_is_disarmed = false
	player_weakened = false
	player_cursed = false
	player_reflect_active = false
	player_dodge_active = false
	player_items_locked = false
	player_lifesteal_active = false
	player_god_pierce = false
	player_damage_bonus = 0
	player_regen_rounds = 0
	player_poison_rounds = 0
	player_stun_extra_turns = 0
	_sync_ground_fx()
	if is_instance_valid(combat_ui):
		combat_ui._apply_status_tints()

# The enemy's mirror of the above, for an UNDYING revive. Same principle: a mob
# that just came back from the dead comes back CLEAN, so it isn't still carrying
# the stun/poison/curse from the blow that killed it. This does clear the
# debuffs the player spent items applying — which is exactly what the player's
# own Phoenix does to the enemy's, so both revives cost the other side the same.
func _clear_enemy_status() -> void:
	enemy_active_armor = false
	enemy_sharpened = false
	enemy_overcharged = false
	enemy_piercing = false
	enemy_is_disarmed = false
	enemy_weakened = false
	enemy_cursed = false
	enemy_reflect_active = false
	enemy_dodge_active = false
	enemy_items_locked = false
	enemy_lifesteal_active = false
	enemy_god_pierce = false
	enemy_damage_bonus = 0
	enemy_regen_rounds = 0
	enemy_poison_rounds = 0
	enemy_stun_extra_turns = 0
	_sync_ground_fx()
	if is_instance_valid(combat_ui):
		combat_ui._apply_status_tints()

func _reset_all_combat_modifiers() -> void:
	player_active_armor   = false;  enemy_active_armor   = false
	player_sharpened      = false;  enemy_sharpened      = false
	player_overcharged    = false;  enemy_overcharged    = false
	player_piercing       = false;  enemy_piercing       = false
	player_is_disarmed    = false;  enemy_is_disarmed    = false
	player_weakened       = false;  enemy_weakened       = false
	player_cursed         = false;  enemy_cursed         = false
	player_reflect_active = false;  enemy_reflect_active = false
	player_dodge_active   = false;  enemy_dodge_active   = false
	player_items_locked   = false;  enemy_items_locked   = false
	player_lifesteal_active = false; enemy_lifesteal_active = false
	player_god_pierce      = false; enemy_god_pierce      = false
	player_banner_rounds   = 0;     enemy_banner_rounds   = 0
	player_phoenix_cd      = 0;     player_phoenix_uses   = 0
	player_relic_charge    = 0;     _relic_announced_charged = false
	# The relic's charge requirement escalates within a fight only — every combat
	# starts it back at RELIC_CHARGE_BASE.
	QuestManager.relic_uses_fight = 0
	if is_instance_valid(_clone_node): _clone_node.queue_free()
	_clone_node = null; player_clone_active = false; _clone_player_home = Vector2.ZERO
	_dismiss_enemy_clone()
	_dmg_since_split = 0
	# The relic beam loops a sustained SFX — make sure a fight that ends mid-beam
	# (flee, death, relic kill) can never leave it droning.
	SFX.stop_loop("relic_beam")
	player_damage_bonus   = 0;      enemy_damage_bonus   = 0
	player_regen_rounds   = 0;      enemy_regen_rounds   = 0
	player_poison_rounds  = 0;      enemy_poison_rounds  = 0
	player_stun_extra_turns = 0;    enemy_stun_extra_turns = 0

func _switch_to_combat_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam):
		cam.enabled = true
		cam.make_current()

func _switch_to_overworld_camera() -> void:
	var cam = get_parent().get_node_or_null("CombatArenaCamera") as Camera2D
	if is_instance_valid(cam):
		cam.enabled = false
	if is_instance_valid(player_ref):
		var pcam = player_ref.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(pcam):
			pcam.enabled = true
			pcam.make_current()

func _check_combat_end_conditions() -> bool:
	if QuestManager.player_health <= 0:
		# ── Phoenix Feather auto-revive ────────────────────────────────────────
		# Holding a Phoenix that's off cooldown snatches you back from death at a
		# modest HP instead of losing the fight. It's consumed and the cooldown
		# climbs, so it can't chain-save you (and it can't help if it's dormant).
		if player_phoenix_cd == 0 and player_inventory.has("phoenix_feather"):
			player_inventory.erase("phoenix_feather")
			_trigger_phoenix_cooldown()
			if combat_ui:
				combat_ui.display_round_history(
					"🪶 PHOENIX FEATHER! You fall... then blaze back to %d HP (dormant %d turns)." % [PHOENIX_REVIVE_HP, player_phoenix_cd], true)
			await _play_phoenix_revive()   # die beat + golden rebirth flash
			# Reborn clean: every buff AND debuff on the player is wiped, so you
			# don't come back still stunned/poisoned/cursed from the hit that killed you.
			_clear_player_status()
			QuestManager.player_health = PHOENIX_REVIVE_HP
			if combat_ui: combat_ui._refresh_ui_states()
			return false
		# Set is_in_combat false FIRST so any in-flight fx coroutines bail out
		# on their next resume instead of re-applying a stale tint.
		if player_clone_active: _dismiss_clone()
		is_in_combat = false; QuestManager.is_in_combat = false
		_reset_sprite_modulates()
		_clear_ground_fx_visibility()
		if is_instance_valid(combat_ui): combat_ui.visible = false
		await ScreenFade.fade_out()
		self.global_position = enemy_overworld_position
		_switch_to_overworld_camera()
		SFX.play(SFX.defeat)
		SFX.stop_music()
		if is_instance_valid(lose_ui) and lose_ui.has_method("show_death_screen"):
			lose_ui.show_death_screen()
		await ScreenFade.fade_in()
		return true

	# ── UNDYING: one death save, mirroring the player's Phoenix Feather ───────
	# Checked BEFORE the death branch so the fight simply continues. has_threat,
	# NOT threat_procs — the save always fires; `_undying_spent` is what makes it
	# once per fight, and it is reset in _reset_all_combat_modifiers.
	if enemy_health <= 0 and not _undying_spent and has_threat("undying"):
		_undying_spent = true
		SFX.play(SFX.enemy_heal if SFX.enemy_heal else SFX.player_heal)
		if combat_ui: combat_ui.display_round_history(
			"🪶 UNDYING — it refuses to fall!", false)
		# The full Phoenix treatment: it keels over and sinks, then flashes gold
		# and rights itself. Snapping it back to 10 HP with a one-frame tint gave
		# no sense that anything had died, so a revive the player had no way to
		# prevent also read as if the hit simply had not registered.
		await _play_phoenix_revive("enemy")
		if not is_in_combat: return true
		# Reborn clean, exactly as the player's Phoenix revive is.
		_clear_enemy_status()
		enemy_health = PHOENIX_REVIVE_HP
		if combat_ui: combat_ui.display_round_history(
			"🪶 It rises again with %d HP!" % PHOENIX_REVIVE_HP, false)
		_sync_ui()
		return false

	if enemy_health <= 0:
		if player_clone_active: _dismiss_clone()
		is_in_combat = false; QuestManager.is_in_combat = false
		SFX.play(SFX.enemy_death)
		SFX.play(SFX.victory)
		_reset_sprite_modulates()
		_clear_ground_fx_visibility()
		if is_instance_valid(combat_ui): combat_ui.visible = false

		var xp := 25
		match enemy_level:
			1: xp = 25
			2: xp = 40
			3: xp = 60
			4: xp = 90
			_: xp = 90 + ((enemy_level - 4) * 30)

		xp = roundi(xp * 1.30)   # +30% global XP gain across all mob levels
		var _lvl_before = QuestManager.player_level
		# Fire the side-quest hook BEFORE gain_xp so an "underdog" check sees the
		# pre-level-up player level (beating a foe 3+ levels above you).
		QuestManager.notify_quest_event("enemy_defeated", {"enemy_level": enemy_level})
		QuestManager.gain_xp(xp)
		var _victory_toast = "⚔️  Victory!  +%d XP" % xp
		if QuestManager.player_level > _lvl_before:
			_victory_toast += "     ⭐  LV %d!" % QuestManager.player_level
		Toast.show_toast(_victory_toast)
		QuestManager.player_health = QuestManager.MAX_HEALTH

		var spr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if is_instance_valid(spr) and spr.sprite_frames and spr.sprite_frames.has_animation("die"):
			spr.stop(); spr.play("die")
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(spr): spr.stop()

		# Fade to black to cover the return camera-cut + player teleport.
		await ScreenFade.fade_out()
		if is_instance_valid(player_ref):
			if "velocity" in player_ref: player_ref.velocity = Vector2.ZERO
			player_ref.global_position = QuestManager.player_overworld_position
		_switch_to_overworld_camera()
		SFX.play_overworld_music()   # back from the fight → resume the overworld theme

		# Hard reset once more after the death-animation wait, defensive
		# against anything that may have queued during that 1s window.
		_reset_sprite_modulates()

		if is_tutorial_mob:
			# One-time guided-combat mob: gone for good, no respawn timer.
			QuestManager.tutorial_mob_defeated = true
			QuestManager.has_unsaved_progress = true
			_permanently_dead = true
			_hide_and_disable_at_graveyard()
		else:
			# ── Graveyard respawn instead of permanent removal ─────────────────
			QuestManager.defeated_enemies[enemy_id] = QuestManager.play_time_seconds
			_is_defeated_waiting_respawn = true
			_hide_and_disable_at_graveyard()

		await ScreenFade.fade_in()
		return true

	return false
