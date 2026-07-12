extends CanvasLayer

# ── Global screen-fade transition ────────────────────────────────────────────
# Autoloaded. A single full-screen black rect above everything else, used to
# hide the hard camera-cut + teleport when entering/leaving combat so it reads
# as a smooth transition instead of a sudden clip.
#
#     await ScreenFade.fade_out()   # screen → black
#     ...move cameras / reposition fighters...
#     await ScreenFade.fade_in()    # black → clear
#
# Runs on PROCESS_MODE_ALWAYS so it still animates if the tree is paused.

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	layer = 200                       # above HUD (90), dialogue (120), end screens
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0.0)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

func fade_out(dur: float = 0.22) -> void:
	await _fade_to(1.0, dur)

func fade_in(dur: float = 0.22) -> void:
	await _fade_to(0.0, dur)

func _fade_to(target_a: float, dur: float) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target_a, dur)
	await _tween.finished
