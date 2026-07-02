extends RefCounted

# Shared look for the floating "[E] …" interaction chip. No drop shadow (soft
# shadows blur badly when the canvas is scaled to 4K); the gold border carries
# the pop instead. Referenced via
#   const PromptStyle = preload("res://PromptStyle.gd")
# (avoids depending on the global class-name cache in headless runs).

const COL_BG     := Color(0.06, 0.07, 0.11, 0.94)
const COL_BORDER := Color(1.00, 0.85, 0.30, 0.95)
const COL_TEXT   := Color(1.00, 0.96, 0.86, 1.00)

static func apply(label: Label) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_color_override("font_color", COL_TEXT)
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var s = StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = COL_BORDER
	s.content_margin_left = 11; s.content_margin_right = 11
	s.content_margin_top = 5;   s.content_margin_bottom = 5
	label.add_theme_stylebox_override("normal", s)
