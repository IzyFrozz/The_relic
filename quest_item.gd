extends Area2D

# Collectible coin. Press [E] near it to grab it (feeds QuestManager coins,
# which the player later trades to the QuestNPC for the chest key).

var _scene_label: Label = null
var player_nearby: bool = false
var _marker: Sprite2D = null

func _ready() -> void:
	# A coin already picked up must NOT come back. quest.tscn is re-instantiated
	# by every reload_current_scene() (fleeing a fight, restarting after death,
	# loading a slot), so without this the whole set respawned and could be
	# farmed. Our node name ("QuestItem", "QuestItem2", …) is authored in the
	# scene and therefore stable across reloads, which makes it a usable id.
	if QuestManager.coin_is_collected(name):
		queue_free()
		return
	# A save written before per-coin tracking knows only the count — let coins
	# claim themselves back until it's accounted for, which heals that save.
	if QuestManager.claim_legacy_coin(name):
		queue_free()
		return

	# Guard so scene-wired connections don't double-bind.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	# Old per-coin world label is superseded by the floating icon marker.
	for child in get_children():
		if child is Label:
			_scene_label = child
			_scene_label.visible = false
			break
	# Floating coin icon instead of the old "[E] Grab Coin" text chip. Coins are
	# small, so it sits closer in and a touch smaller than the NPC markers.
	_marker = IconDB.add_marker(self, "coin", Vector2(0, -22), 0.34)

func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact") and not QuestManager.ui_arrow_nav_open:
		QuestManager.collect_coin(name)
		_spawn_pickup_feedback()
		queue_free()

# A little "+1 <coin> n/10" that floats up and fades. Parented to our parent so
# it outlives this coin being freed.
#
# RichTextLabel (not Label) so the coin renders as the real IconDB pixel icon
# inline instead of a system emoji, and deliberately small: the old 22px/0.4
# Label came out ~53 screen px at the 6× camera zoom, dwarfing every other bit
# of world text.
const POP_WIDTH := 140.0
const POP_SCALE := 0.25

func _spawn_pickup_feedback() -> void:
	var parent = get_parent()
	if not is_instance_valid(parent):
		return
	var lbl = RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size = Vector2(POP_WIDTH, 0)
	lbl.add_theme_font_size_override("normal_font_size", 16)
	lbl.add_theme_color_override("default_color", Color(1.0, 0.85, 0.3))
	lbl.text = "[center]+1  %s  %d/%d[/center]" % [
		IconDB.bbcode_for_emoji("🪙", 18),
		QuestManager.coins_collected, QuestManager.COINS_NEEDED,
	]
	lbl.scale = Vector2(POP_SCALE, POP_SCALE)
	lbl.z_index = 100
	parent.add_child(lbl)
	lbl.global_position = global_position + Vector2(-POP_WIDTH * POP_SCALE * 0.5, -16)
	var tw = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 26, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.15)
	get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func _on_body_entered(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = true
		IconDB.set_marker_visible(_marker, true)

func _on_body_exited(body: Node2D) -> void:
	if body.name == "mainplayer":
		player_nearby = false
		IconDB.set_marker_visible(_marker, false)
