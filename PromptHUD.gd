extends CanvasLayer

# ── Global interact prompt ──────────────────────────────────────────────────
# One crisp screen-space "[E] …" chip that floats just above the OBJECT it
# belongs to (the NPC / chest / coin / door), staying put on that object and
# auto-sized to its text. Rendered in screen space so it stays sharp at any
# resolution / camera zoom, and it always draws above the player model. It
# hides itself whenever a menu/popup is open so it never sits on top of panels.
#
# Interactables register/unregister as the player enters/leaves:
#     PromptHUD.request(self, "[E]  Talk")
#     PromptHUD.release(self)
# The most recently requested prompt wins when several overlap.

const PromptStyle = preload("res://PromptStyle.gd")
const Y_OFFSET := 74.0   # screen px above the object's origin

var _requests: Dictionary = {}   # instance_id -> { "node": Node2D, "text": String }
var _order: Array = []           # request order, last = shown
var _label: Label = null

# Cached modal-UI references (found lazily) so we can hide behind them.
var _pause: Node = null
var _save: Node = null
var _equip: Node = null
var _roadmap: Node = null

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	PromptStyle.apply(_label)
	_label.visible = false
	add_child(_label)

func request(source: Object, text: String) -> void:
	if not (source is Node2D):
		return
	var key = source.get_instance_id()
	_requests[key] = { "node": source, "text": text }
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
	_label.text = _requests[_order[-1]].text
	_label.reset_size()

func _process(_delta: float) -> void:
	if _order.is_empty() or _blocking():
		_label.visible = false
		return
	var entry = _requests[_order[-1]]
	var node = entry.node
	if not is_instance_valid(node):
		release(node)
		return
	# Some objects (e.g. doorways) have their origin at a trigger zone far from
	# where the prompt should sit — they can override the anchor node.
	var anchor: Node2D = node
	if node.has_method("get_prompt_target"):
		var t = node.get_prompt_target()
		if is_instance_valid(t):
			anchor = t
	var screen = get_viewport().get_canvas_transform() * anchor.global_position
	_label.reset_size()
	_label.position = screen + Vector2(-_label.size.x * 0.5, -Y_OFFSET)
	_label.visible = true

# True while combat, dialogue, or any menu/popup is up — so the chip never
# sits on top of those panels.
func _blocking() -> bool:
	if QuestManager.is_in_combat or DialogueManager.is_active:
		return true
	if not is_instance_valid(_pause): _pause = get_tree().root.find_child("PauseMenu", true, false)
	if is_instance_valid(_pause) and _pause.has_method("is_open") and _pause.is_open():
		return true
	if not is_instance_valid(_save): _save = get_tree().root.find_child("SavePopup", true, false)
	if is_instance_valid(_save) and _save.visible:
		return true
	if not is_instance_valid(_equip): _equip = get_tree().root.find_child("EquipmentMenu", true, false)
	if is_instance_valid(_equip) and _equip.visible:
		return true
	if not is_instance_valid(_roadmap): _roadmap = get_tree().root.find_child("RoadmapPopup", true, false)
	if is_instance_valid(_roadmap) and _roadmap.visible:
		return true
	return false
