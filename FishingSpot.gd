extends Area2D

# ── Fishing Spot (the water / puddle) ────────────────────────────────────────
# The place you actually FISH, split out from the Fisherman NPC (who now only
# talks and teaches). Interact (E) here to cast. Gated behind level 5 via
# LevelGate("fishing") AND behind meeting the fisherman (his tutorial), so the
# player is pointed at him first. A 3-second "get ready" countdown runs before
# the minigame so the cast never catches the player off-guard.
#
# Add this as an Area2D near the water in main.tscn (do NOT edit map.tscn /
# foreground.tscn). It needs a child CollisionShape2D for the trigger zone.

const LevelGate = preload("res://LevelGate.gd")
const FishingMinigame = preload("res://FishingMinigame.gd")

# ── Mirror Clone drop rates ──────────────────────────────────────────────────
# Baseline chance on ANY catch, plus a guaranteed drop from these top tiers (keys
# must match FishingMinigame.SIZES). It's a one-time unlock either way.
const CLONE_CHANCE := 0.05
const CLONE_FISH := ["exotic", "rare", "legendary"]

# ── XP nerf ──────────────────────────────────────────────────────────────────
# Fishing was out-earning every other XP source, so the whole payout is scaled
# down here (one knob, so the per-tier xp_mult curve stays untouched).
# Two stacked 25% cuts: 0.75 × 0.75 — fishing now pays ~56% of its original XP.
const XP_SCALE := 0.5625

# ── XP bands per tier ────────────────────────────────────────────────────────
# The payout used to be one shared randi_range(18, 30) scaled by the tier's
# multiplier. That ±25% spread is wider than the gap between neighbouring tiers,
# so the bands overlapped badly — a lucky `medium` could out-earn an unlucky
# `large`, and a `massive` could beat an `exotic` two tiers above it.
#
# Each tier now gets its own band, ±XP_JITTER around its midpoint. ±7% is the
# widest spread the ladder tolerates: the tightest neighbouring ratio is
# rare→exotic at 1.158, and (1-j)/(1+j) >= 1/1.158 solves to j <= 0.073.
# _build_xp_bands() then walks the ladder and nudges any floor that integer
# rounding left touching the previous ceiling, so the order can NEVER invert.
const XP_JITTER   := 0.07
const XP_MID_ROLL := 24.0   # midpoint of the old 18-30 roll

var _xp_bands: Dictionary = {}   # tier name -> Vector2i(min_xp, max_xp)
var _bands_difficulty: int = -1  # which difficulty the cached bands were built for

func _build_xp_bands() -> void:
	_xp_bands.clear()
	_bands_difficulty = QuestManager.difficulty
	# RELIC difficulty trims the whole ladder by the same factor, so the bands stay
	# ordered (a uniform scale can't reorder them) and the non-overlap pass below
	# still guarantees a bigger fish always pays more.
	var diff_mult: float = QuestManager.DIFF_FISHING_XP_MULT if QuestManager.is_relic_difficulty() else 1.0
	var tiers: Array = FishingMinigame.SIZES.keys()
	tiers.sort_custom(func(a, b):
		return float(FishingMinigame.SIZES[a]["xp"]) < float(FishingMinigame.SIZES[b]["xp"]))
	var prev_max := 0
	for t in tiers:
		var mid: float = XP_MID_ROLL * float(FishingMinigame.SIZES[t]["xp"]) * XP_SCALE * diff_mult
		var lo: int = maxi(1, int(round(mid * (1.0 - XP_JITTER))))
		var hi: int = maxi(lo, int(round(mid * (1.0 + XP_JITTER))))
		if lo <= prev_max:          # rounding closed the gap — force it open
			lo = prev_max + 1
			hi = maxi(hi, lo)
		prev_max = hi
		_xp_bands[t] = Vector2i(lo, hi)

# XP for landing `size_name`, always inside that tier's own band.
func xp_for_catch(size_name: String) -> int:
	# Rebuild if difficulty changed mid-run (Settings can flip it any time).
	if _xp_bands.is_empty() or _bands_difficulty != QuestManager.difficulty:
		_build_xp_bands()
	var band: Vector2i = _xp_bands.get(size_name, Vector2i(10, 17))
	return randi_range(band.x, band.y)

var player_nearby: bool = false
var _busy: bool = false

@onready var _rod_icon: Sprite2D = get_node_or_null("RodIcon")

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	# The rod marker starts hidden and only shows while the player is in range.
	if is_instance_valid(_rod_icon):
		var tex = IconDB.tex("fishing_rod")
		if tex: _rod_icon.texture = tex
		_rod_icon.visible = false

# The rod icon is the whole affordance now — no "[E] …" text prompt.
func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		IconDB.set_marker_visible(_rod_icon, true)

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		IconDB.set_marker_visible(_rod_icon, false)

func _process(_delta: float) -> void:
	if _busy or QuestManager.is_fishing:
		return
	if not (player_nearby and Input.is_action_just_pressed("interact")):
		return
	if QuestManager.ui_arrow_nav_open or DialogueManager.is_active:
		return
	var pause_menu = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(pause_menu) and pause_menu.has_method("is_open") and pause_menu.is_open():
		return
	_try_cast()

func _try_cast() -> void:
	if not LevelGate.is_unlocked("fishing"):
		DialogueManager.say("", "The water looks promising, but you don't have the knack yet.  " + LevelGate.hint("fishing"))
		return
	# Must have met the Old Fisherman and learned the ropes first.
	if not QuestManager.fishing_tutorial_done:
		DialogueManager.say("", "Rod in hand, but no idea how to use it. Best find the [b]Old Fisherman[/b] nearby — he'll teach you.")
		return
	_cast()

func _cast() -> void:
	_busy = true
	IconDB.set_marker_visible(_rod_icon, false)
	await _run_countdown()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var mg = FishingMinigame.new()
	# Nudges harder as the player levels past 5, but CAPPED — this multiplies the
	# per-tier speed, so uncapped it made the top tiers uncatchable late on.
	mg.difficulty = minf(1.30, 1.0 + float(max(0, QuestManager.player_level - 5)) * 0.03)
	mg.finished.connect(_on_fish_result)
	get_tree().current_scene.add_child(mg)

# A quick 3 · 2 · 1 · Cast! overlay so the player can settle before the fish bite.
func _run_countdown() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	get_tree().current_scene.add_child(layer)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 90)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(lbl)
	for n in ["3", "2", "1", "Cast!"]:
		SFX.play(SFX.fish_cast if n == "Cast!" else SFX.fish_countdown)
		lbl.text = n
		# reset_size() first: otherwise pivot_offset uses the PREVIOUS text's size and
		# the pop-in scales around the wrong point (it reads as a ghosted double).
		lbl.reset_size()
		lbl.pivot_offset = lbl.size * 0.5
		lbl.scale = Vector2(1.4, 1.4)
		create_tween().tween_property(lbl, "scale", Vector2(1, 1), 0.25)
		await get_tree().create_timer(0.7).timeout
	# Hide before queue_free: the free is deferred, so without this the "Cast!" text
	# lingers a frame on top of the minigame that spawns right after.
	layer.visible = false
	layer.queue_free()

func _on_fish_result(success: bool, size_name: String, xp_mult: float) -> void:
	_busy = false
	if player_nearby:
		IconDB.set_marker_visible(_rod_icon, true)
	if not success:
		SFX.play(SFX.fish_fail)
		Toast.show_toast("🎣  The fish slipped the line — cast again!")
		return
	SFX.play(SFX.fish_catch)
	QuestManager.record_fish_caught()   # progresses the "Gone Fishing" quest
	# Bigger (harder) fish are worth strictly more XP — bands never overlap.
	var xp := xp_for_catch(size_name)
	QuestManager.gain_xp(xp)
	var msg := "%s   +%d XP" % [_lead_for(size_name), xp]
	# ── Mirror Clone drop ──────────────────────────────────────────────────────
	# A flat CLONE_CHANCE from any catch, and a guaranteed drop from the three top
	# tiers — so landing a hard fish is always worth it, and everyone else still
	# gets there eventually. Announced only on the first unlock (catching more fish
	# shouldn't keep re-popping the same line).
	if not QuestManager.unlocked_items.has("clone"):
		if size_name in CLONE_FISH or randf() < CLONE_CHANCE:
			QuestManager.unlocked_items.append("clone")
			QuestManager.has_unsaved_progress = true
			var cmeta = QuestManager.ITEM_META.get("clone", {})
			msg += "    ✨ %s %s! (equip it in your Loadout)" % [cmeta.get("emoji", "👥"), cmeta.get("label", "Mirror Clone")]
	# Fishing NEVER gives coins — the only coins are the 10 win-gating pickups.
	Toast.show_toast(msg)

func _lead_for(size_name: String) -> String:
	match size_name:
		"tiny":      return _fish_lead("fish_tiny",      "🐟", "A little one!")
		"minnow":    return _fish_lead("fish_minnow",    "🐟", "Barely a mouthful.")
		"small":     return _fish_lead("fish_small",     "🐟", "Nice catch!")
		"modest":    return _fish_lead("fish_modest",    "🐟", "A decent little fish.")
		"medium":    return _fish_lead("fish_medium",    "🐟", "Solid catch!")
		"good":      return _fish_lead("fish_good",      "🐟", "Now that's a good one!")
		"large":     return _fish_lead("fish_large",     "🐠", "What a whopper!")
		"big":       return _fish_lead("fish_big",       "🐠", "A proper big'un!")
		"huge":      return _fish_lead("fish_huge",      "🐡", "A monster of the deep!")
		"giant":     return _fish_lead("fish_giant",     "🐡", "A GIANT — look at the size of it!")
		"massive":   return _fish_lead("fish_massive",   "🐡", "MASSIVE! It nearly snapped the rod!")
		"trophy":    return _fish_lead("fish_trophy",    "🎏", "A TROPHY fish — one for the wall!")
		"exotic":    return _fish_lead("fish_exotic",    "🎏", "An EXOTIC beauty — never seen its like.")
		"rare":      return _fish_lead("fish_rare",      "🎏", "A RARE catch! Almost unheard of.")
		"legendary": return _fish_lead("fish_legendary", "🎏", "LEGENDARY CATCH!!!")
	return _fish_lead("fish_small", "🐟", "Nice catch!")

# Builds "<fish-icon>  <text>" — the toast is a RichTextLabel, so an inline [img]
# renders the chosen fish; falls back to the emoji if the icon is missing.
func _fish_lead(id: String, emoji: String, text: String) -> String:
	# Random sprite from this tier's pool, so landing the same tier twice still
	# shows a different fish (IconDB.FISH_VARIANTS).
	var bb := IconDB.fish_bbcode(id, 28)
	return "%s  %s" % [bb if bb != "" else emoji, text]
