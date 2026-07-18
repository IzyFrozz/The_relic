extends Node

# ═══════════════════════════════════════════════════════════════════════════════
#  SFX / MUSIC MANAGER  (autoload — lives on sfx.tscn)
# ═══════════════════════════════════════════════════════════════════════════════
# Every sound in the game has a NAMED SLOT below. They're all `@export`, so you fill
# them by opening `sfx.tscn` in the editor and DRAGGING an audio file onto each slot
# in the Inspector — no code needed. Empty slots simply stay silent, so the game
# never breaks while the set is half-finished (that's the "placeholder ready" part).
#
# ── How to REPLACE a placeholder ────────────────────────────────────────────────
#   1. Drop your new .wav/.mp3/.ogg into Asset/Main Sound/fx (or /music).
#   2. Open sfx.tscn, click the SFX root, find the slot in the Inspector.
#   3. Drag the file onto the slot. Done — it plays next time that event fires.
#
# ── How to PLAY a sound from code (when wiring events later) ─────────────────────
#   SFX.play(SFX.ui_click)                 # any slot, one-shot
#   SFX.item("potion")                     # the item-use sound for an item id
#   SFX.mob_attack_snd(enemy_level)        # the attack sound for that mob level
#   SFX.footstep()                         # alternates + randomises pitch for walking
#   SFX.play_music(SFX.music_overworld)    # looping track w/ crossfade
#
# NOTE: nothing is wired to game events yet — this is the ready-to-fill library and
# the play API. Hooking each event up (button press, hit, coin, …) comes later.

# ── Audio buses ────────────────────────────────────────────────────────────────
# Routes through "SFX" / "Music" buses if the project defines them, else "Master"
# (so the existing mute/volume controls still work either way).
var _sfx_bus := "Master"
var _music_bus := "Master"

# ── Playback tuning ──────────────────────────────────────────────────────────────
@export_group("Playback")
@export var sfx_volume_db: float = 0.0      # global trim for one-shot SFX
@export var music_volume_db: float = -6.0   # music usually sits under SFX
@export var default_pitch_variation: float = 0.06   # ±6% random pitch so repeats don't machine-gun
@export var music_crossfade_sec: float = 0.8
@export var sfx_voices: int = 12            # how many SFX can overlap at once

# ═══════════════════════════════════════════════════════════════════════════════
#  SOUND SLOTS  — drag files onto these in the Inspector
# ═══════════════════════════════════════════════════════════════════════════════

# ── Menu / UI ───────────────────────────────────────────────────────────────────
@export_group("UI / Menu")
@export var ui_open: AudioStream          # a menu/panel opens
@export var ui_close: AudioStream         # a menu/panel closes
@export var ui_click: AudioStream         # generic button press
@export var ui_hover: AudioStream         # cursor moves onto a button
@export var ui_confirm: AudioStream       # accept / OK / equip
@export var ui_cancel: AudioStream        # back / decline
@export var ui_error: AudioStream         # blocked / invalid action
@export var ui_tab: AudioStream           # switch page / quest tab
@export var ui_toggle: AudioStream        # checkbox / mute flip
@export var ui_slider: AudioStream        # volume slider tick
@export var ui_save: AudioStream          # save to a slot
@export var ui_load: AudioStream          # load a slot
@export var ui_pause: AudioStream         # game paused
@export var ui_unpause: AudioStream       # game resumed
@export var ui_rebind: AudioStream        # a key was rebound

# ── Player in combat ─────────────────────────────────────────────────────────────
@export_group("Player Combat")
@export var player_attack: AudioStream    # your basic attack swing/lunge
@export var player_hit: AudioStream       # you take damage
@export var player_block: AudioStream     # shield/armor soaks a hit
@export var player_dodge: AudioStream     # smoke-bomb / dodge whiff
@export var player_reflect: AudioStream   # mirror ward bounces a hit
@export var player_heal: AudioStream      # you get healed
@export var player_crit: AudioStream      # a big/overcharged hit lands

# ── Combat flow ──────────────────────────────────────────────────────────────────
@export_group("Combat Flow")
@export var combat_start: AudioStream     # a fight begins
@export var combat_flee: AudioStream      # you flee a fight
@export var victory: AudioStream          # enemy defeated
@export var defeat: AudioStream           # you died / game over
@export var level_up: AudioStream         # you gain a level
@export var crate_drop: AudioStream       # Quartermaster's supply crate lands
@export var relic_ready: AudioStream      # the relic finishes charging (glows)
@export var relic_unleash: AudioStream    # the relic is unleashed

# ── Item use (one per item id — see QuestManager.ITEM_META) ─────────────────────
@export_group("Item Use SFX")
@export var item_potion: AudioStream
@export var item_shield: AudioStream
@export var item_grindstone: AudioStream
@export var item_whip: AudioStream
@export var item_needle: AudioStream
@export var item_magnet: AudioStream
@export var item_bandage: AudioStream
@export var item_poison_dart: AudioStream
@export var item_battle_horn: AudioStream      # "Lifesteal Vial"
@export var item_mirror_ward: AudioStream
@export var item_smoke_bomb: AudioStream
@export var item_weaken_totem: AudioStream
@export var item_chain_hook: AudioStream
@export var item_static_field: AudioStream
@export var item_time_warp: AudioStream
@export var item_overcharge: AudioStream
@export var item_phoenix_feather: AudioStream  # auto-revive trigger
@export var item_clone: AudioStream            # "Mirror Clone"
@export var item_relic: AudioStream

# ── Enemy ─────────────────────────────────────────────────────────────────────────
@export_group("Enemy")
@export var enemy_hit: AudioStream        # enemy takes damage (generic)
@export var enemy_death: AudioStream      # enemy dies (generic)
# Per-LEVEL attack sound. Element 0 = Lv.1, element 1 = Lv.2, … up to Lv.20.
# Add 20 elements in the Inspector and drop a file into each level's slot; a level
# left empty falls back to `enemy_attack_default`.
@export var mob_attack: Array[AudioStream] = []
@export var enemy_attack_default: AudioStream   # used when a level's slot is empty

# ── Movement (overworld) ─────────────────────────────────────────────────────────
@export_group("Movement")
@export var footstep_a: AudioStream       # walking — alternates A/B for a natural gait
@export var footstep_b: AudioStream
@export var sprint: AudioStream           # sprint start / loop
@export var bump: AudioStream             # walking into a wall / solid NPC

# ── World & pickups ───────────────────────────────────────────────────────────────
@export_group("World & Pickups")
@export var coin: AudioStream             # coin pickup
@export var item_pickup: AudioStream      # generic item/potion pickup
@export var chest_open: AudioStream       # the ancient chest opens
@export var key_get: AudioStream          # receive the chest key
@export var relic_get: AudioStream        # obtain the Ancient Relic
@export var quest_accept: AudioStream     # a quest is accepted
@export var quest_complete: AudioStream   # a quest/objective completes
@export var dialogue_blip: AudioStream    # per-character typewriter blip (optional)
@export var interact_prompt: AudioStream  # walking into an interactable's range

# ── Fishing ───────────────────────────────────────────────────────────────────────
@export_group("Fishing")
@export var fish_cast: AudioStream        # rod cast / "Cast!"
@export var fish_countdown: AudioStream   # 3-2-1 tick
@export var fish_reel: AudioStream        # holding to reel (loop)
@export var fish_catch: AudioStream       # landed it
@export var fish_fail: AudioStream        # it got away

# ── Music (looping) ────────────────────────────────────────────────────────────────
@export_group("Music")
@export var music_menu: AudioStream       # main menu
@export var music_overworld: AudioStream  # exploring the island
@export var music_combat: AudioStream     # a fight
@export var music_town: AudioStream       # village / hub
@export var music_interior: AudioStream   # house interiors
@export var music_victory: AudioStream    # win screen

# ═══════════════════════════════════════════════════════════════════════════════
#  RUNTIME
# ═══════════════════════════════════════════════════════════════════════════════
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_fade: AudioStreamPlayer   # second deck for crossfading
var _foot_toggle := false
var _item_map: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # UI/menus keep clicking while paused
	if AudioServer.get_bus_index("SFX") != -1:
		_sfx_bus = "SFX"
	if AudioServer.get_bus_index("Music") != -1:
		_music_bus = "Music"

	for i in range(max(1, sfx_voices)):
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)

	_music = _make_music_player()
	_music_fade = _make_music_player()

	# Fill any slot left EMPTY with a temporary sound so the game has audio now.
	# Anything you drag onto a slot in the Inspector wins over these (exports are
	# applied before _ready, so a filled slot is already non-null here).
	_apply_placeholders()

	# id -> item-use slot, so item("potion") finds item_potion, etc.
	_item_map = {
		"potion": item_potion, "shield": item_shield, "grindstone": item_grindstone,
		"whip": item_whip, "needle": item_needle, "magnet": item_magnet,
		"bandage": item_bandage, "poison_dart": item_poison_dart, "battle_horn": item_battle_horn,
		"mirror_ward": item_mirror_ward, "smoke_bomb": item_smoke_bomb, "weaken_totem": item_weaken_totem,
		"chain_hook": item_chain_hook, "static_field": item_static_field, "time_warp": item_time_warp,
		"overcharge": item_overcharge, "phoenix_feather": item_phoenix_feather,
		"clone": item_clone, "relic": item_relic,
	}

# Loads an audio file if it exists, else null (so a deleted placeholder is safe).
func _ph(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null

# TEMPORARY stand-in sounds, drawn from the existing Asset/Main Sound files. These
# are deliberately rough placeholders — swap each via the Inspector. Only slots you
# HAVEN'T filled yourself get one (`if x == null`).
func _apply_placeholders() -> void:
	const FX := "res://Asset/Main Sound/fx/"
	const MU := "res://Asset/Main Sound/music/"
	# ── UI ──
	if ui_click == null:    ui_click    = _ph(FX + "click.mp3")
	if ui_hover == null:    ui_hover    = _ph(FX + "select.wav")
	if ui_confirm == null:  ui_confirm  = _ph(FX + "enter.wav")
	if ui_cancel == null:   ui_cancel   = _ph(FX + "break.wav")
	if ui_error == null:    ui_error    = _ph(FX + "universfield-error-08-206492.mp3")
	if ui_tab == null:      ui_tab      = _ph(FX + "select.wav")
	if ui_open == null:     ui_open     = _ph(FX + "enter.wav")
	if ui_save == null:     ui_save     = _ph(FX + "complete.ogg")
	# ── Combat ──
	if player_attack == null: player_attack = _ph(FX + "shooter.wav")
	if player_hit == null:    player_hit    = _ph(FX + "thorn.wav")
	if enemy_hit == null:     enemy_hit     = _ph(FX + "thorn.wav")
	if victory == null:       victory       = _ph(FX + "complete.ogg")
	if level_up == null:      level_up      = _ph(FX + "upgrade.mp3")
	if crate_drop == null:    crate_drop    = _ph(FX + "OvenDing.mp3")
	# ── World / fishing ──
	if coin == null:           coin           = _ph(FX + "game coin.mp3")
	if quest_complete == null: quest_complete = _ph(FX + "complete.ogg")
	if quest_accept == null:   quest_accept   = _ph(FX + "enter.wav")
	if fish_catch == null:     fish_catch     = _ph(FX + "complete.ogg")
	if fish_fail == null:      fish_fail      = _ph(FX + "break.wav")
	if chest_open == null:     chest_open     = _ph(FX + "OvenDing.mp3")
	# ── Music (nothing auto-plays yet — these just fill the slots) ──
	if music_menu == null:      music_menu      = _ph(MU + "determination.ogg")
	if music_overworld == null: music_overworld = _ph(MU + "Sun Tribe.ogg")
	if music_combat == null:    music_combat    = _ph(MU + "ghost-town.ogg")
	if music_town == null:      music_town      = _ph(MU + "hot_spring_town.mp3")
	if music_interior == null:  music_interior  = _ph(MU + "Sun Tribe interior.ogg")
	if music_victory == null:   music_victory   = _ph(MU + "Heros determination silent.ogg")

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _music_bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

# ── One-shot SFX ─────────────────────────────────────────────────────────────────
# Plays `stream` on a free pooled voice. Null (an unfilled slot) is a silent no-op,
# so callers never have to null-check. `pitch_rand` adds ± that fraction of random
# pitch; pass 0 for an exact repeat.
func play(stream: AudioStream, volume_db: float = 0.0, pitch_rand: float = -1.0) -> void:
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = sfx_volume_db + volume_db
	var pr := default_pitch_variation if pitch_rand < 0.0 else pitch_rand
	p.pitch_scale = 1.0 + randf_range(-pr, pr) if pr > 0.0 else 1.0
	p.play()

# The item-use sound for a QuestManager item id ("potion", "relic", …).
func item(item_id: String) -> void:
	play(_item_map.get(item_id, null))

# The attack sound for a mob of `level` (1-based). Falls back to the default when
# that level's slot is empty or out of range.
func mob_attack_snd(level: int) -> void:
	var idx := level - 1
	var s: AudioStream = mob_attack[idx] if idx >= 0 and idx < mob_attack.size() else null
	if s == null:
		s = enemy_attack_default
	play(s)

# Walking: alternates the two footstep samples with a little pitch wobble.
func footstep() -> void:
	_foot_toggle = not _foot_toggle
	play(footstep_b if _foot_toggle else footstep_a, -3.0, 0.10)

# ── Music ─────────────────────────────────────────────────────────────────────────
# Crossfades to `stream` (looping). Same track already playing → no-op.
func play_music(stream: AudioStream) -> void:
	if stream == null:
		stop_music()
		return
	if _music.playing and _music.stream == stream:
		return
	# Swap decks so the old track fades out while the new one fades in.
	var tmp := _music
	_music = _music_fade
	_music_fade = tmp
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music, "volume_db", music_volume_db, music_crossfade_sec)
	if _music_fade.playing:
		tw.tween_property(_music_fade, "volume_db", -40.0, music_crossfade_sec)
		tw.chain().tween_callback(_music_fade.stop)

func stop_music() -> void:
	if _music.playing:
		var deck := _music
		create_tween().tween_property(deck, "volume_db", -40.0, music_crossfade_sec) \
			.finished.connect(deck.stop)

func stop_all_sfx() -> void:
	for p in _pool:
		p.stop()
