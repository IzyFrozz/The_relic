extends Node

# ── Icon database ────────────────────────────────────────────────────────────
# Autoloaded. Maps a game concept id -> a texture in Asset/Selected Icon/. UI code
# calls IconDB.tex("potion"): it returns the Texture2D if the file exists, else
# null — so callers fall back to their emoji automatically and a half-finished
# icon set still renders cleanly (icons where we have them, emoji elsewhere).
#
# Filenames are the artist-chosen names in the folder (spaces/case preserved).

const DIR := "res://Asset/Selected Icon/"

# concept id -> filename (without the folder)
const MAP := {
	# ── Combat items (match QuestManager.ITEM_META ids) ──
	"potion":          "fb266.png",              # a healing potion from the fb265-272 set
	"shield":          "fb853.png",              # shield set fb853-860
	"grindstone":      "grindstone.png",
	"whip":            "whip.png",
	"needle":          "needle.png",
	"magnet":          "magnet.png",
	"bandage":         "bandage.png",
	"poison_dart":     "poison dart.png",
	"lifesteal_vial":     "lifesteal_vial.png",     # "Lifesteal Vial"
	"mirror_ward":     "mirror ward.png",
	"smoke_bomb":      "smoke bomb.png",
	"weaken_totem":    "weaken totem.png",
	"chain_hook":      "chain hook.png",
	"static_field":    "static field.png",
	"time_warp":       "time warp.png",
	"overcharge":      "overcharge.png",
	"phoenix_feather": "phoenix feather.png",
	"clone":           "clone.png",
	"relic":           "Relic.png",

	# ── Currency / world objects ──
	"coin":            "gold coin.png",
	"supply_crate":    "supply crate.png",
	"chest":           "chest icon.png",
	"reward":          "reward.png",

	# ── HUD / progression ──
	"level_up":        "level_up.png",
	"heart_full":      "red heart.png",
	"heart_half":      "redhearthalf.png",
	"heart_empty":     "blackheart.png",
	"heart_gold_full": "goldheartfull.png",
	"heart_gold_half": "goldhearthalf.png",
	"map":             "map.png",
	"trophy":          "trophy.png",
	"skull":           "skull label.png",
	"attack":          "attack.png",
	"ready":           "ready.png",
	"compass":         "compass.png",
	"marker_player":   "markerplayer.png",
	"marker_objective":"markerobjective.png",
	"wolf":            "underdog.png",

	# ── Menu / misc ──
	"key":             "key.png",
	"save":            "save.png",
	"load":            "load.png",
	"settings":        "settings.png",
	"help":            "help.png",
	"loadout_station": "loadout_station.png",
	"loadout_bag":     "pouch.png",          # the 🎒 in the Roadmap loadout-slot lines
	"quest_scroll":    "feather pen.png",     # ROADMAP (quill)
	"quest_log":       "quest book.png",      # QUEST LOG (book) — distinct from roadmap
	"talk":            "chat.png",           # talk-to-NPC quests
	"audio":           "music node icon.png",
	"home":            "house icon.png",
	"exit":            "door.png",
	"flee":            "sprinting icon.png",
	"wizard":          "wizard.png",
	"yes":             "thumb up (yes).png",
	"no":              "thumb down (no).png",
	"crate":           "supply crate.png",   # alias of supply_crate for toasts
	"gift":            "reward.png",          # 🎁 rare-find

	# ── Combat status FX / buff-debuff (floating icons + buff labels) ──
	"fx_heal":         "heal HP.png",           # ✚ instant heal / 🩹 regen
	"buff_damage":     "buff damage.png",       # +Ndmg damage bonus / 💥 heavy hit
	"buff_dodge":      "speed buff.png",         # 💨 dodge active
	"debuff_weaken":   "debuff damage.png",     # 🗿 weakened (reduced damage)
	"debuff_disarm":   "X button.png",          # ❌ disarmed

	# ── Fishing ──
	"fishing_rod":     "fishing_rod_basic.png",
	# Catch tiers (tiny → legendary), shown in the catch toast. 15 rungs, each with
	# its own fish, so the reward reads differently every step up.
	# These are the CENTRE of each tier's size window — see FISH_VARIANTS below;
	# they're picked by measured on-screen bulk, not by filename number.
	"fish_tiny":       "fishes (33).png",
	"fish_minnow":     "fishes (42).png",
	"fish_small":      "fishes (37).png",
	"fish_modest":     "fishes (2).png",
	"fish_medium":     "fishes (14).png",
	"fish_good":       "fishes (30).png",
	"fish_large":      "fishes (27).png",
	"fish_big":        "fishes (10).png",
	"fish_huge":       "fishes (23).png",
	"fish_giant":      "fishes (26).png",
	"fish_massive":    "fishes (5).png",
	"fish_trophy":     "fishes (39).png",
	"fish_exotic":     "fishes (20).png",
	"fish_rare":       "fishes (11).png",
	"fish_legendary":  "fishes (19).png",
	# The fish shown swimming in the minigame tank. Deliberately its OWN icon and
	# not any tier's, so the art can never hint at what you've hooked.
	"fish_hooked":     "fishes (43).png",

	# ── Stamina bar states ──
	"stamina_full":    "green stamina icon.png",
	"stamina_low":     "yellow stamina icon.png",
	"stamina_empty":   "red stamina icon.png",
}

# ── Fish variety ─────────────────────────────────────────────────────────────
# The folder holds 44 fish sprites but only 16 were ever wired (one per tier plus
# the one in the tank), so a session showed the same handful of fish over and
# over — and the common tiers dominate the weights, so in practice you saw ~7-8.
# Each tier now owns a POOL and the catch toast picks from it at random: landing
# the same tier twice still shows a different fish. Each tier's original
# hand-picked sprite stays first in its pool.
#
# Sprites are ranked by their MEASURED on-screen bulk (opaque bounding-box area —
# a 1.51x spread across the set) and dealt to the tiers in that order, NOT by
# filename number. Filename order is what let a visually chunky fish come back
# labelled "medium". Each tier draws from a tight ±2 window around its own rung,
# so a pool holds 3-5 fish of genuinely similar size while all 43 stay reachable
# over a run. Widen the window for more variety, narrow it for a tighter size
# match — that's the single trade-off knob here.
#
# All 44 sprites are used: 43 across the tiers, plus "fishes (43)" which stays
# the tank's fixed art — the tank must never hint at the tier, the reveal is
# the payoff.
# Each list runs SMALLEST -> LARGEST by measured bulk, and the tiers run in the
# same order, so reading the table top-to-bottom walks the fish from tiddler to
# monster. The centre entry of each row is the tier's canonical icon in MAP.
const FISH_VARIANTS := {
	#                   ── smallest ─────────────────────────────────── largest ──
	"fish_tiny":       ["fishes (33).png", "fishes (34).png", "fishes (35).png"],
	"fish_minnow":     ["fishes (34).png", "fishes (35).png", "fishes (42).png", "fishes (44).png", "fishes (36).png"],
	"fish_small":      ["fishes (44).png", "fishes (36).png", "fishes (37).png", "fishes (38).png", "fishes (1).png"],
	"fish_modest":     ["fishes (38).png", "fishes (1).png",  "fishes (2).png",  "fishes (3).png",  "fishes (4).png"],
	"fish_medium":     ["fishes (3).png",  "fishes (4).png",  "fishes (14).png", "fishes (15).png", "fishes (16).png"],
	"fish_good":       ["fishes (15).png", "fishes (16).png", "fishes (30).png", "fishes (31).png", "fishes (32).png"],
	"fish_large":      ["fishes (31).png", "fishes (32).png", "fishes (27).png", "fishes (28).png", "fishes (29).png"],
	"fish_big":        ["fishes (28).png", "fishes (29).png", "fishes (10).png", "fishes (8).png",  "fishes (9).png"],
	"fish_huge":       ["fishes (8).png",  "fishes (9).png",  "fishes (23).png", "fishes (24).png", "fishes (25).png"],
	"fish_giant":      ["fishes (24).png", "fishes (25).png", "fishes (26).png", "fishes (17).png", "fishes (18).png"],
	"fish_massive":    ["fishes (17).png", "fishes (18).png", "fishes (5).png",  "fishes (6).png",  "fishes (7).png"],
	"fish_trophy":     ["fishes (6).png",  "fishes (7).png",  "fishes (39).png", "fishes (40).png", "fishes (41).png"],
	"fish_exotic":     ["fishes (40).png", "fishes (41).png", "fishes (20).png", "fishes (21).png", "fishes (22).png"],
	"fish_rare":       ["fishes (21).png", "fishes (22).png", "fishes (11).png", "fishes (12).png", "fishes (13).png"],
	"fish_legendary":  ["fishes (12).png", "fishes (13).png", "fishes (19).png"],
}



# A random sprite path from `tier_id`'s pool, or "" if the tier has no pool.
func fish_variant_path(tier_id: String) -> String:
	var pool: Array = FISH_VARIANTS.get(tier_id, [])
	if pool.is_empty():
		return ""
	var p: String = DIR + str(pool[randi() % pool.size()])
	return p if ResourceLoader.exists(p) else ""

# [img] bbcode for a random sprite from the tier's pool (RichTextLabel), falling
# back to the tier's canonical icon.
func fish_bbcode(tier_id: String, size: int = 28) -> String:
	var p: String = fish_variant_path(tier_id)
	if p != "":
		return "[img=%d]%s[/img]" % [size, p]
	return bbcode_for_id(tier_id, size)

var _cache: Dictionary = {}

# Returns the Texture2D for `id`, or null if there's no mapped/imported file.
func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var result: Texture2D = null
	if MAP.has(id):
		var path: String = DIR + MAP[id]
		if ResourceLoader.exists(path):
			result = load(path) as Texture2D
	_cache[id] = result
	return result

func has(id: String) -> bool:
	return tex(id) != null

# ── Floating interact markers ────────────────────────────────────────────────
# Every interactable in the world announces itself the same way: a small icon
# that floats above it while the player is in range. This replaced the old
# "[E] …" text prompts — the icon says both "you can act here" AND what the
# action is (chat bubble, save disk, chest, door, …).
#
#     _marker = IconDB.add_marker(self, "save")     # in _ready()
#     IconDB.set_marker_visible(_marker, true)      # on body_entered
#
# `host` must be a Node2D — pass the node the icon should sit on (for objects
# whose origin is off the sprite, e.g. a doorway trigger, pass the child that
# IS on the door). Returns the Sprite2D, or null if the icon is missing.
func add_marker(host: Node2D, icon_id: String, offset: Vector2 = Vector2(0, -32), scale_f: float = 0.42) -> Sprite2D:
	if not is_instance_valid(host):
		return null
	var existing := host.get_node_or_null("InteractMarker")
	if is_instance_valid(existing):
		return existing as Sprite2D
	var t := tex(icon_id)
	if t == null:
		return null
	# Hide any legacy in-scene affordance this marker supersedes.
	for legacy_name in ["Emoji", "PromptLabel", "InteractPrompt"]:
		var legacy := host.get_node_or_null(legacy_name)
		if is_instance_valid(legacy) and legacy is CanvasItem:
			(legacy as CanvasItem).visible = false
	var s := Sprite2D.new()
	s.name = "InteractMarker"
	s.texture = t
	s.position = offset
	s.scale = Vector2(scale_f, scale_f)
	s.z_index = 60
	s.visible = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	host.add_child(s)
	return s

# Shows/hides a marker, chirping the interact-prompt sound on the hidden→shown
# edge only (PromptHUD used to own that chirp).
func set_marker_visible(marker: Sprite2D, on: bool) -> void:
	if not is_instance_valid(marker):
		return
	if on and not marker.visible:
		SFX.play(SFX.interact_prompt, -4.0)
	marker.visible = on

# Swaps a live marker's icon (e.g. the chest flipping from locked to opened).
func set_marker_icon(marker: Sprite2D, icon_id: String) -> void:
	if not is_instance_valid(marker):
		return
	var t := tex(icon_id)
	if t != null:
		marker.texture = t

# Back-compat shorthand for talkable NPCs — the chat bubble.
func add_talk_marker(npc: Node2D, offset: Vector2 = Vector2(0, -32), scale_f: float = 0.42) -> Sprite2D:
	return add_marker(npc, "talk", offset, scale_f)

# Gives a Button a centred icon+label GROUP (icon immediately left of the text,
# the pair centred together) — matching how the emoji-in-text buttons look, which
# Godot's native Button.icon (pinned to the far edge) can't reproduce. Builds an
# overlay CenterContainer→HBox(TextureRect + Label); the label copies the button's
# own font size/colour so it blends in. Falls back to emoji-in-text when no icon.
# NOTE: set the button's font override BEFORE calling this so the copy picks it up.
func decorate_button(btn: Button, glyph: String, label: String, size: int = 28) -> void:
	if not is_instance_valid(btn):
		return
	var old := btn.get_node_or_null("IconContent")
	if is_instance_valid(old):
		old.free()
	var t: Texture2D = tex(id_for_emoji(glyph))
	if t == null:
		btn.text = ("%s  %s" % [glyph, label]) if label != "" else glyph
		return
	btn.text = ""
	var cc := CenterContainer.new()
	cc.name = "IconContent"
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	cc.add_child(hb)
	var ir := TextureRect.new()
	ir.texture = t
	ir.custom_minimum_size = Vector2(size, size)
	ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ir.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ir)
	if label != "":
		var lb := Label.new()
		lb.text = label
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var fs := btn.get_theme_font_size("font_size")
		if fs > 0:
			lb.add_theme_font_size_override("font_size", fs)
		lb.add_theme_color_override("font_color", btn.get_theme_color("font_color"))
		hb.add_child(lb)
	btn.add_child(cc)

# Returns the res:// path for `id` if the file exists, else "" — for callers that
# need the path itself (e.g. RichTextLabel [img] bbcode).
func path(id: String) -> String:
	if MAP.has(id):
		var p: String = DIR + MAP[id]
		if ResourceLoader.exists(p):
			return p
	return ""

# Returns an [img] bbcode tag for a concept id (for RichTextLabel), or "" if the
# icon is missing so callers can substitute their own fallback glyph.
func bbcode_for_id(id: String, size: int = 22) -> String:
	var p: String = path(id)
	return "[img=%d]%s[/img]" % [size, p] if p != "" else ""

# ── Emoji → concept-id lookup ────────────────────────────────────────────────
# The combat FX layer and buff labels historically use emoji glyphs. This maps
# each glyph to an IconDB concept id so a single lookup upgrades every call site
# to a real icon (falling back to the emoji when no icon is mapped/imported).
const EMOJI_TO_ID := {
	"✚": "fx_heal",
	"🩹": "fx_heal",
	"☠": "poison_dart", "☠️": "poison_dart",
	"🧲": "magnet",
	"⛓️": "chain_hook", "⛓": "chain_hook",
	"🏺": "relic",
	"🩸": "lifesteal_vial",
	"🧪": "potion",
	"🛡️": "shield", "🛡": "shield",
	"🪨": "grindstone",
	"💥": "whip",
	"🔥": "overcharge",
	"📌": "needle",
	"🪞": "mirror_ward",
	"💨": "buff_dodge",
	"🗿": "debuff_weaken",
	"⚡": "static_field",
	"⏳": "time_warp",
	"❌": "debuff_disarm",
	"💀": "skull",
	# ── HP hearts ──
	"❤️": "heart_full", "❤": "heart_full",
	"💔": "heart_half",
	"🖤": "heart_empty",
	"💛": "heart_gold_full",
	"🧡": "heart_gold_half",
	# ── HP headers / misc combat ──
	"⚔️": "attack", "⚔": "attack",
	"✨": "ready",
	"👥": "clone",
	"📦": "supply_crate",
	"🎁": "gift",
	"⭐": "level_up",
	# ── Currency ──
	"🪙": "coin",
	# ── Quest / world ──
	"🔑": "key",
	"🏆": "trophy",
	"🗺️": "map", "🗺": "map",
	"🧭": "compass",
	"🔵": "marker_player",
	"🟡": "marker_objective",
	"🐺": "wolf",
	"🪶": "phoenix_feather",
	"🧙": "wizard",
	"🎣": "fishing_rod",
	"🎒": "loadout_bag",
	"📜": "quest_scroll",                                    # roadmap (quill)
	"🗒️": "quest_log", "🗒": "quest_log", "📋": "quest_log",  # quest log (book)
	"🗣️": "talk", "🗣": "talk",
	# ── Menu glyphs ──
	"💾": "save",
	"📂": "load",
	"🔊": "audio",
	"⚙️": "settings", "⚙": "settings",
	"🏠": "home",
	"🚪": "exit",
	"🏃": "flee",
	"❓": "help", "❔": "help",
	"✅": "yes", "✔": "yes", "✔️": "yes",
	"✖": "no", "✕": "no",
}

# Given an emoji glyph, returns the mapped concept id ("" if none).
func id_for_emoji(glyph: String) -> String:
	return EMOJI_TO_ID.get(glyph, "")

# Replaces every known emoji glyph inside `text` with an [img] bbcode tag (when an
# icon exists), leaving unmapped glyphs untouched. Longer glyphs (variation-selector
# forms like "☠️") are replaced first so they win over their bare counterparts.
func iconify(text: String, size: int = 22) -> String:
	var glyphs: Array = EMOJI_TO_ID.keys()
	glyphs.sort_custom(func(a, b): return a.length() > b.length())
	for g in glyphs:
		if text.find(g) == -1:
			continue
		var p: String = path(EMOJI_TO_ID[g])
		if p != "":
			text = text.replace(g, "[img=%d]%s[/img]" % [size, p])
	return text

# Returns bbcode for an emoji: an [img] tag when an icon exists, else the raw
# emoji. `size` is the inline image height in px.
func bbcode_for_emoji(glyph: String, size: int = 22) -> String:
	var id: String = EMOJI_TO_ID.get(glyph, "")
	if id != "":
		var p: String = path(id)
		if p != "":
			return "[img=%d]%s[/img]" % [size, p]
	return glyph
