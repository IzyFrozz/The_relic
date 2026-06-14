extends Node2D

var player_nearby: bool = false
var prompt_label: Label = null
var equipment_menu: CanvasLayer = null

func _ready() -> void:
	# Grabs the direct child Label (your setup uses a plain "Label" node)
	prompt_label = get_node_or_null("Label") as Label
	if is_instance_valid(prompt_label):
		prompt_label.visible = false

	# Find EquipmentMenu anywhere in the scene tree
	equipment_menu = get_tree().root.find_child("EquipmentMenu", true, false) as CanvasLayer

	# Connect InteractArea (your Area2D child) signals
	var area = get_node_or_null("InteractArea") as Area2D
	if is_instance_valid(area):
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		_open_equipment_menu()

func _open_equipment_menu() -> void:
	if not is_instance_valid(equipment_menu):
		equipment_menu = get_tree().root.find_child("EquipmentMenu", true, false) as CanvasLayer
	if is_instance_valid(equipment_menu):
		equipment_menu.visible = true
		equipment_menu.refresh_display()

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		if is_instance_valid(prompt_label):
			prompt_label.text = "[E] Configure Loadout"
			prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		if is_instance_valid(prompt_label):
			prompt_label.visible = false
