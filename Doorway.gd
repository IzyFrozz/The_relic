extends Area2D

var prompt_label: Label = null

# Drag and drop your destination Marker2D into this slot in the Inspector!
@export var target_marker: Marker2D 
@export var prompt_text: String = "[E] Interact"

var player_ref: Node2D = null

func _ready() -> void:
	# 1. DEEP SCAN: Look through ALL sub-folders and child nodes to find the label
	_find_label_deep_scan(self)
	
	if prompt_label == null:
		print("⚠️ DOORWAY WARNING: Hand-to-god, I scanned everywhere and couldn't find a Label node inside '", name, "'!")

	# 2. Connect collision signals safely via code — guarded so a scene-wired
	#    connection doesn't double-bind (removes the "already connected" errors).
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

# Recursive function that searches deep into the node tree to find and kill the label visibility
func _find_label_deep_scan(current_node: Node) -> void:
	for child in current_node.get_children():
		if child is Label:
			prompt_label = child
			prompt_label.visible = false # FORCE IT HIDDEN ON LAUNCH!
			return
		_find_label_deep_scan(child) # Look deeper if it's tucked away inside another node

func _process(_delta: float) -> void:
	# Teleport loop when hitting E inside the zone
	if player_ref and Input.is_action_just_pressed("interact") and not QuestManager.ui_arrow_nav_open:
		if target_marker:
			player_ref.global_position = target_marker.global_position
		else:
			print("⚠️ DOORWAY WARNING: Target Marker is empty in the Inspector!")

var _prompt_anchor: Node2D = null

# Anchor the "[E]" chip on the door itself (the interaction CollisionShape2D,
# which is placed on the door) so it stays put on the door instead of trailing
# the player. Falls back to this node's origin if no collision child is found.
func get_prompt_target() -> Node2D:
	if not is_instance_valid(_prompt_anchor):
		for c in get_children():
			if c is CollisionShape2D:
				_prompt_anchor = c
				break
	return _prompt_anchor if is_instance_valid(_prompt_anchor) else self

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_ref = body
		PromptHUD.request(self, prompt_text)

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_ref = null
		PromptHUD.release(self)
