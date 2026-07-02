extends Node

# ── Custom keybinds ─────────────────────────────────────────────────────────
# Rebindable actions persist to user://keybinds.cfg and are re-applied on the
# next launch (autoloaded, so this runs before any scene). The PauseMenu's
# Keybinds view calls rebind() / reset_defaults().

const SAVE_PATH := "user://keybinds.cfg"

# Action id -> friendly label, in display order.
const ACTIONS := [
	["move_up",    "Move Up"],
	["move_down",  "Move Down"],
	["move_left",  "Move Left"],
	["move_right", "Move Right"],
	["interact",   "Interact"],
	["sprint",     "Sprint"],
]

# Captured at boot before any override is applied, so "Reset to Defaults" works.
var _defaults: Dictionary = {}

func _ready() -> void:
	for entry in ACTIONS:
		_defaults[entry[0]] = _current_keycode(entry[0])
	load_binds()

func action_ids() -> Array:
	var ids: Array = []
	for entry in ACTIONS:
		ids.append(entry[0])
	return ids

func label_for(action: String) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[1]
	return action.capitalize()

func key_display(action: String) -> String:
	var kc = _current_keycode(action)
	if kc == 0:
		return "—"
	return OS.get_keycode_string(kc)

# Rebind an action to a single physical key and persist immediately.
func rebind(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev = InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)
	save_binds()

func reset_defaults() -> void:
	for action in _defaults.keys():
		var kc = int(_defaults[action])
		if kc != 0:
			InputMap.action_erase_events(action)
			var ev = InputEventKey.new()
			ev.physical_keycode = kc
			InputMap.action_add_event(action, ev)
	save_binds()

func save_binds() -> void:
	var cfg = ConfigFile.new()
	for entry in ACTIONS:
		cfg.set_value("keys", entry[0], _current_keycode(entry[0]))
	cfg.save(SAVE_PATH)

func load_binds() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for entry in ACTIONS:
		var action = entry[0]
		if not InputMap.has_action(action):
			continue
		var kc = int(cfg.get_value("keys", action, 0))
		if kc == 0:
			continue
		InputMap.action_erase_events(action)
		var ev = InputEventKey.new()
		ev.physical_keycode = kc
		InputMap.action_add_event(action, ev)

func _current_keycode(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	return 0
