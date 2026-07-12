extends Control

# Thin drawing surface for WorldMap. WorldMap owns all the logic and does the
# actual painting in _paint(); this node just forwards its _draw() call so the
# map can use draw_rect / draw_circle / draw_line etc. `full` distinguishes the
# corner mini-map (false) from the full-screen map (true).

var map: Node = null
var full: bool = false

func _draw() -> void:
	if is_instance_valid(map) and map.has_method("_paint"):
		map._paint(self, full)
