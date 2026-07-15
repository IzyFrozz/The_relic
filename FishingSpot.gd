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
		if is_instance_valid(_rod_icon): _rod_icon.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if is_instance_valid(_rod_icon): _rod_icon.visible = false

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
	if is_instance_valid(_rod_icon): _rod_icon.visible = false
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
	if player_nearby and is_instance_valid(_rod_icon):
		_rod_icon.visible = true
	if not success:
		Toast.show_toast("🎣  The fish slipped the line — cast again!")
		return
	QuestManager.record_fish_caught()   # progresses the "Gone Fishing" quest
	# Bigger (harder) fish are worth proportionally more XP.
	var xp := int(round(randi_range(18, 30) * xp_mult))
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
	var bb := IconDB.bbcode_for_id(id, 28)
	return "%s  %s" % [bb if bb != "" else emoji, text]
