extends CanvasLayer

# ── Global interact prompt ──────────────────────────────────────────────────
# One crisp screen-space "[E] …" chip that floats just above the player's head,
# always horizontally centred on them and auto-sized to its text (so it never
# drifts off-centre when the wording changes). Rendered in screen space so it
# stays sharp at any resolution / camera zoom instead of getting pixelated.
#
# Interactables register/unregister as the player enters/leaves:
#     PromptHUD.request(self, "[E]  Talk")
#     PromptHUD.release(self)
# The most recently requested prompt wins when several overlap.

const PromptStyle = preload("res://PromptStyle.gd")
const Y_OFFSET := 96.0   # screen px above the player's origin

var _requests: Dictionary = {}   # instance_id -> text
var _order: Array = []           # request order, last = shown
var _label: Label = null
var _player: Node2D = null

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	PromptStyle.apply(_label)
	_label.visible = false
	add_child(_label)

func request(source: Object, text: String) -> void:
	if not is_instance_valid(source):
		return
	var key = source.get_instance_id()
	_requests[key] = text
	_order.erase(key)
	_order.append(key)
	_apply_text()

func release(source: Object) -> void:
	if not is_instance_valid(source):
		return
	var key = source.get_instance_id()
	_requests.erase(key)
	_order.erase(key)
	_apply_text()

func _apply_text() -> void:
	if _order.is_empty():
		_label.visible = false
		return
	_label.text = _requests[_order[-1]]
	_label.reset_size()

func _process(_delta: float) -> void:
	if _order.is_empty():
		_label.visible = false
		return
	if QuestManager.is_in_combat or DialogueManager.is_active:
		_label.visible = false
		return
	var p = _get_player()
	if not is_instance_valid(p):
		_label.visible = false
		return
	var screen = get_viewport().get_canvas_transform() * p.global_position
	_label.reset_size()
	_label.position = screen + Vector2(-_label.size.x * 0.5, -Y_OFFSET)
	_label.visible = true

func _get_player() -> Node2D:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().root.find_child("mainplayer", true, false) as Node2D
	return _player
