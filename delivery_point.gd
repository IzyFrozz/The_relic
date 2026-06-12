extends Area2D

@onready var prompt_label: Label = $PromptLabel
@onready var quest_ui: CanvasLayer = $QuestUI
@onready var status_label: Label = $QuestUI/MenuPanel/StatusLabel

var player_nearby: bool = false

func _ready() -> void:
 prompt_label.visible = false
 quest_ui.visible = false 
 body_entered.connect(_on_body_entered)
 body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
 if player_nearby and Input.is_action_just_pressed("interact"):
  if QuestManager.chest_unlocked:
   return

  if QuestManager.has_enough_coins():
   QuestManager.chest_unlocked = true
   QuestManager.has_relic = true
   prompt_label.text = "Chest Unlocked!"
   
   # Separate CanvasLayer popup for gaining the relic (Left exactly as you wrote it!)
   show_canvas_popup("✨ ANCIENT RELIC GAINED!!! ✨")
  else:
   # DYNAMIC UPDATE: Automatically updates the text target numbers from 3 to 10
   var current = str(QuestManager.coins_collected)
   var total = str(QuestManager.COINS_NEEDED)
   show_canvas_popup("It's locked! Need " + total + " coins.\n(Coins: " + current + "/" + total + ")")

# Handles showing the CanvasLayer popup text for 3 seconds
func show_canvas_popup(text_to_display: String) -> void:
 status_label.text = text_to_display
 quest_ui.visible = true
 await get_tree().create_timer(3.0).timeout
 quest_ui.visible = false

func _on_body_entered(body: Node2D) -> void:
 if body.name == "mainplayer":
  player_nearby = true
  if QuestManager.chest_unlocked:
   prompt_label.text = "Chest Unlocked!"
  else:
   prompt_label.text = "[E] Inspect Chest"
  prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
 if body.name == "mainplayer":
  player_nearby = false
  prompt_label.visible = false
  quest_ui.visible = false # Hide the popup early if they walk away
