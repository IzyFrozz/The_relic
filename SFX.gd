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
# OFF by default: the game plays ONLY the sounds you've dragged into slots (empty
# slot = silent). Turn ON to auto-fill any empty slot with a rough stand-in from
# Asset/Main Sound so every event makes *some* noise while you're still building.
@export var use_placeholder_sounds: bool = false
@export var sfx_volume_db: float = 0.0      # global trim for one-shot SFX
@export var music_volume_db: float = -6.0   # music usually sits under SFX
@export var default_pitch_variation: float = 0.06   # ±6% random pitch so repeats don't machine-gun
@export var music_crossfade_sec: float = 0.8
@export var sfx_voices: int = 12            # how many SFX can overlap at once
# Footstep cadence. Sprinting reuses the SAME footstep samples, just quicker and a
# touch higher-pitched, so the run reads as the same boots moving faster.
@export var footstep_interval: float = 0.45      # seconds between steps when walking
@export var sprint_step_interval: float = 0.27   # …when sprinting
@export var sprint_step_pitch: float = 1.18      # pitch multiplier while sprinting

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
@export var ui_scroll: AudioStream        # scrolling a long list (wheel tick)
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
# ── Relic beam (PLACEHOLDER SLOTS — drop files in via the Inspector) ──────────
# Both fall back to relic_unleash while empty, so the beam is never silent.
@export var relic_beam_charge: AudioStream # rising hum as the beam winds up (~0.6s)
@export var relic_beam_fire: AudioStream   # the beam itself — ideally ~1.5s+, it is
										   # looped for as long as the beam is held

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
@export var item_lifesteal_vial: AudioStream      # "Lifesteal Vial"
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
@export var enemy_hit: AudioStream        # enemy takes damage with no attack behind it (poison tick)
@export var enemy_death: AudioStream      # enemy dies (generic)
@export var enemy_heal: AudioStream       # enemy heals (falls back to player_heal if empty)
# Per-LEVEL attack sound. Element 0 = Lv.1, element 1 = Lv.2, … up to Lv.20.
# Add 20 elements in the Inspector and drop a file into each level's slot; a level
# left empty falls back to `enemy_attack_default`.
@export var mob_attack: Array[AudioStream] = []
@export var enemy_attack_default: AudioStream   # used when a level's slot is empty

# ── Movement (overworld) ─────────────────────────────────────────────────────────
@export_group("Movement")
# Sprinting deliberately has NO slot of its own — it replays these same samples
# faster + pitched up (see sprint_step_interval / sprint_step_pitch above).
@export var footstep_a: AudioStream       # walking — alternates A/B for a natural gait
@export var footstep_b: AudioStream
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
var _current_music: AudioStream = null   # the SLOT currently playing (decks hold copies)
var _loops: Dictionary = {}              # key -> dedicated looping AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # UI/menus keep clicking while paused
	_ensure_buses()
	_sfx_bus = "SFX"
	_music_bus = "Music"
	_load_audio_settings()

	for i in range(max(1, sfx_voices)):
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)

	_music = _make_music_player()
	_music_fade = _make_music_player()

	# Only when explicitly enabled — otherwise unset slots stay silent so you hear
	# exactly what you've assigned.
	if use_placeholder_sounds:
		_apply_placeholders()

	# id -> item-use slot, so item("potion") finds item_potion, etc.
	_item_map = {
		"potion": item_potion, "shield": item_shield, "grindstone": item_grindstone,
		"whip": item_whip, "needle": item_needle, "magnet": item_magnet,
		"bandage": item_bandage, "poison_dart": item_poison_dart, "lifesteal_vial": item_lifesteal_vial,
		"mirror_ward": item_mirror_ward, "smoke_bomb": item_smoke_bomb, "weaken_totem": item_weaken_totem,
		"chain_hook": item_chain_hook, "static_field": item_static_field, "time_warp": item_time_warp,
		"overcharge": item_overcharge, "phoenix_feather": item_phoenix_feather,
		"clone": item_clone, "relic": item_relic,
	}

	# Auto-play a click on EVERY button press and a blip on hover, game-wide, by
	# watching for buttons as they're added — no per-button wiring needed.
	get_tree().node_added.connect(_on_node_added)

# ── Global button feedback ───────────────────────────────────────────────────────
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		# Checkboxes/switches get the distinct "toggle" sound; everything else clicks.
		if n is CheckButton or n is CheckBox:
			if not n.pressed.is_connected(_btn_toggle):
				n.pressed.connect(_btn_toggle)
		elif not n.pressed.is_connected(_btn_click):
			n.pressed.connect(_btn_click)
		if not n.mouse_entered.is_connected(_btn_hover):
			n.mouse_entered.connect(_btn_hover)
	elif n is Slider:
		if not n.drag_ended.is_connected(_slider_done):
			n.drag_ended.connect(_slider_done)
	elif n is ScrollContainer:
		# Same idea as the button hook: every scrollable list in the game gets a
		# wheel tick with no per-list wiring.
		if not n.gui_input.is_connected(_scroll_gui_input):
			n.gui_input.connect(_scroll_gui_input.bind(n))

# ── Scroll ticks ─────────────────────────────────────────────────────────────────
# Driven off gui_input rather than the scrollbar's value_changed, deliberately: a
# menu rebuilding its contents re-clamps the scroll value and would fire
# value_changed, ticking when the player never touched the wheel. This only
# reacts to a real wheel event, and stays silent when there's nothing to scroll
# or we're already pinned at that end of the list.
const SCROLL_MIN_GAP := 0.05   # seconds — a fast wheel spin shouldn't machine-gun
var _last_scroll_t: float = -99.0

func _scroll_gui_input(event: InputEvent, sc: ScrollContainer) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	var b := (event as InputEventMouseButton).button_index
	if b != MOUSE_BUTTON_WHEEL_UP and b != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var vb := sc.get_v_scroll_bar()
	if not is_instance_valid(vb) or vb.max_value <= vb.page:
		return   # content fits — nothing to scroll
	if b == MOUSE_BUTTON_WHEEL_UP and vb.value <= vb.min_value:
		return   # already at the top
	if b == MOUSE_BUTTON_WHEEL_DOWN and vb.value >= vb.max_value - vb.page:
		return   # already at the bottom
	var t := float(Time.get_ticks_msec()) / 1000.0
	if t - _last_scroll_t < SCROLL_MIN_GAP:
		return
	_last_scroll_t = t
	play(ui_scroll if ui_scroll else ui_tab, -9.0, 0.08)

func _btn_click() -> void:
	play(ui_click)

func _btn_toggle() -> void:
	play(ui_toggle if ui_toggle else ui_click)

func _slider_done(_changed: bool) -> void:
	play(ui_slider, -4.0)

func _btn_hover() -> void:
	play(ui_hover, -6.0)

# ═══════════════════════════════════════════════════════════════════════════════
#  AUDIO BUSES & VOLUME  (Master → Music + SFX)  — settings sliders drive these
# ═══════════════════════════════════════════════════════════════════════════════
const AUDIO_CFG := "user://audio.cfg"
# Order shown in the settings Audio section. "Master" already exists at index 0.
const MIX_BUSES := ["Master", "Music", "SFX"]

# Creates the Music + SFX buses (routed into Master) if the project doesn't already
# define them, so each can be mixed independently by its own slider.
func _ensure_buses() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")

# Volume as a 0..1 slider value (linear). 0 = silent.
func get_bus_linear(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return 1.0
	# Deliberately ignores mute: mute is a separate toggle. Folding it in here made
	# saving-while-muted write 0.0 and wipe the real level for good.
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(i)), 0.0, 1.0)

func _apply_bus_linear(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	v = clampf(v, 0.0, 1.0)
	if v <= 0.001:
		AudioServer.set_bus_volume_db(i, -80.0)
	else:
		AudioServer.set_bus_volume_db(i, linear_to_db(v))

# Set + persist (call from a slider's value_changed).
func set_bus_linear(bus: String, v: float) -> void:
	_apply_bus_linear(bus, v)
	_save_audio_settings()

func set_master_mute(muted: bool) -> void:
	AudioServer.set_bus_mute(0, muted)
	_save_audio_settings()

func is_master_muted() -> bool:
	return AudioServer.is_bus_mute(0)

func _save_audio_settings() -> void:
	var cfg := ConfigFile.new()
	for b in MIX_BUSES:
		cfg.set_value("audio", b, get_bus_linear(b))
	cfg.set_value("audio", "mute", AudioServer.is_bus_mute(0))
	cfg.save(AUDIO_CFG)

func _load_audio_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUDIO_CFG) != OK:
		return
	for b in MIX_BUSES:
		_apply_bus_linear(b, float(cfg.get_value("audio", b, 1.0)))
	AudioServer.set_bus_mute(0, bool(cfg.get_value("audio", "mute", false)))

# Returns a LOOPING copy of `stream`. It duplicates first on purpose: the loop flag
# lives on the imported resource, so flipping it in place would also make the same
# file loop forever anywhere else it's used (e.g. the same mp3 in an SFX slot).
func _looping_copy(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var s: AudioStream = stream.duplicate()
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif "loop" in s:
		s.loop = true
	return s

# ── Music by context (with sensible fallbacks so nothing is dead silent) ─────────
func play_menu_music() -> void:      play_music(music_menu)
func play_overworld_music() -> void: play_music(music_overworld if music_overworld else music_town)
func play_victory_music() -> void:   play_music(music_victory)
func play_interior_music() -> void:  play_music(music_interior if music_interior else music_overworld)
# Combat only switches if a combat track exists; otherwise the overworld music
# keeps playing (so a fight is never abruptly silent).
func play_combat_music() -> void:
	if music_combat:
		play_music(music_combat)

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
	if ui_scroll == null:   ui_scroll   = _ph(FX + "select.wav")
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
func play(stream: AudioStream, volume_db: float = 0.0, pitch_rand: float = -1.0,
		base_pitch: float = 1.0) -> void:
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = sfx_volume_db + volume_db
	var pr := default_pitch_variation if pitch_rand < 0.0 else pitch_rand
	p.pitch_scale = base_pitch * (1.0 + randf_range(-pr, pr)) if pr > 0.0 else base_pitch
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

# One footstep. Alternates the A/B samples with a little pitch wobble. Sprinting
# uses the SAME samples, just pitched up (the caller also steps more often).
func footstep(sprinting: bool = false) -> void:
	_foot_toggle = not _foot_toggle
	var s: AudioStream = footstep_b if _foot_toggle else footstep_a
	if s == null:   # only one sample filled → use whichever exists
		s = footstep_a if footstep_a != null else footstep_b
	play(s, -3.0, 0.10, sprint_step_pitch if sprinting else 1.0)

# Seconds between steps for the current gait — drives the walk loop in mainplayer.
func step_interval(sprinting: bool) -> float:
	return sprint_step_interval if sprinting else footstep_interval

# ── Music ─────────────────────────────────────────────────────────────────────────
# Crossfades to `stream` (looping). Same track already playing → no-op.
func play_music(stream: AudioStream) -> void:
	if stream == null:
		stop_music()
		return
	# Compare against the ORIGINAL slot (the deck holds a looping duplicate).
	if _music.playing and _current_music == stream:
		return
	_current_music = stream
	# Swap decks so the old track fades out while the new one fades in.
	var tmp := _music
	_music = _music_fade
	_music_fade = tmp
	_music.stream = _looping_copy(stream)   # music always loops
	_music.volume_db = -40.0
	_music.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music, "volume_db", music_volume_db, music_crossfade_sec)
	if _music_fade.playing:
		tw.tween_property(_music_fade, "volume_db", -40.0, music_crossfade_sec)
		tw.chain().tween_callback(_music_fade.stop)

func stop_music() -> void:
	_current_music = null
	if _music.playing:
		var deck := _music
		create_tween().tween_property(deck, "volume_db", -40.0, music_crossfade_sec) \
			.finished.connect(deck.stop)

# ── Continuous / looping SFX ─────────────────────────────────────────────────────
# For sounds that run WHILE something is happening (reeling a fish, an engine, an
# ambience bed). Each `key` gets its own player, so several can loop at once.
#   SFX.start_loop("reel", SFX.fish_reel)   …later…   SFX.stop_loop("reel")
# Calling start_loop again with the same key while it's already playing is a no-op,
# so it's safe to call every frame.
func start_loop(key: String, stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var p: AudioStreamPlayer = _loops.get(key)
	if not is_instance_valid(p):
		p = AudioStreamPlayer.new()
		p.bus = _sfx_bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_loops[key] = p
	p.volume_db = sfx_volume_db + volume_db
	p.pitch_scale = pitch
	if p.playing:
		return                      # already looping this key
	p.stream = _looping_copy(stream)
	p.play()

func stop_loop(key: String) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if is_instance_valid(p) and p.playing:
		p.stop()

# ── Dialogue typewriter blip ─────────────────────────────────────────────────────
# IMPORTANT: `dialogue_blip` is not one blip — the file is an 8.8-second track of
# ~81 evenly spaced blips (one per ~109ms), i.e. a ready-made typewriter LOOP.
# Treat it as such: start it once when a line begins revealing and stop it when
# the reveal ends. It gets its own voice so we have that stop handle.
#
# Do NOT retrigger this per character. Firing it as a pooled one-shot plays all
# 8.8s over the top of everything; restarting it every few characters only ever
# replays the file's 47ms of leading silence, which is inaudible.
var _blip: AudioStreamPlayer = null

# The blip file is MUCH quieter than the rest of the library — measured peaks:
#   blip -18.3 dB · click ui -4.0 dB · game coin -1.7 dB
# so it needs a BOOST, not the usual trim. Without this it lands ~22 dB under a
# button click and is simply inaudible under music. +8 puts its peak near -14 dB:
# clearly present, still sitting below the one-shot SFX (it's a continuous sound,
# so it shouldn't match them). Retune here if the sample is ever replaced.
const BLIP_GAIN_DB := 8.0

func start_blip(volume_db: float = BLIP_GAIN_DB) -> void:
	if dialogue_blip == null:
		return
	if not is_instance_valid(_blip):
		_blip = AudioStreamPlayer.new()
		_blip.bus = _sfx_bus
		_blip.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_blip)
	_blip.volume_db = sfx_volume_db + volume_db
	if _blip.playing:
		return                                    # already ticking for this line
	_blip.stream = _looping_copy(dialogue_blip)   # loops if a line outruns the file
	_blip.play()

func stop_blip() -> void:
	if is_instance_valid(_blip) and _blip.playing:
		_blip.stop()

func stop_all_loops() -> void:
	for k in _loops.keys():
		stop_loop(k)

func stop_all_sfx() -> void:
	for p in _pool:
		p.stop()
