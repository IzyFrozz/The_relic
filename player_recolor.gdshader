shader_type canvas_item;

// ── Player palette-swap (mask-driven) ───────────────────────────────────────
// Recolors five groups on the single baked player sprite: HAIR, SHIRT, PANTS,
// SHOES and SKIN. Hair and shoes share the same browns on the repainted
// sprite, so instead of matching colours at runtime the groups come from a
// pre-generated region mask (player_groups_mask.png, built by
// tools/gen_player_mask.py) whose RED channel holds a group id per pixel:
//   40 hair · 80 shirt · 120 pants · 160 shoes · 200 skin · 0 untouched
// The mask is the same size as player.png, so the sprite UV samples it 1:1.
// Outline, eyes and the weapon metal are id 0 and stay untouched.
//
// Each assigned pixel is painted the EXACT chosen colour (flat fill, no shading
// or multiply) so the result matches the colour picker's hex precisely.
//
// IMPORTANT: on a canvas_item, the built-in COLOR arrives pre-set to
// texture×modulate. We must OVERWRITE it with the flat fill (COLOR = vec4(rgb…))
// — NOT multiply into it, or white × brown-texture = brown and the recolour
// silently vanishes. When recolor is off we leave COLOR at its default so the
// normal texture×modulate rendering (incl. combat FX tint) passes through.
//
// recolor_on is driven from code: it's forced to 0 whenever the sprite is
// tinted by a combat FX (modulate ≠ white) so the FX plays on the base
// colours, then back to 1 so the customization returns instantly. Because of
// that pairing, when recolor_on is 1 the modulate is always white, so simply
// writing the flat colour (no modulate term) is correct.

uniform sampler2D group_mask : filter_nearest, repeat_disable;

// Chosen replacement colours (defaults = the sprite's base shades, so an
// untouched picker means no visible change).
uniform vec3 hair_color  = vec3(0.341, 0.227, 0.137);   // #573a23
uniform vec3 shirt_color = vec3(0.561, 0.012, 0.012);   // #8f0303
uniform vec3 pants_color = vec3(0.173, 0.396, 0.710);   // #2c65b5
uniform vec3 shoe_color  = vec3(0.341, 0.227, 0.137);   // #573a23
uniform vec3 skin_color  = vec3(0.675, 0.482, 0.365);   // #ac7b5d

uniform float recolor_on = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (recolor_on > 0.5 && tex.a > 0.05) {
		vec3 rgb = tex.rgb;
		float id = texture(group_mask, UV).r * 255.0;
		// Flat fill: paint the exact chosen colour, no luminance/shading applied.
		if (id > 30.0 && id < 50.0) {
			rgb = hair_color;
		} else if (id > 70.0 && id < 90.0) {
			rgb = shirt_color;
		} else if (id > 110.0 && id < 130.0) {
			rgb = pants_color;
		} else if (id > 150.0 && id < 170.0) {
			rgb = shoe_color;
		} else if (id > 190.0) {
			rgb = skin_color;
		}
		// Overwrite (don't multiply) — modulate is white whenever recolor is on.
		COLOR = vec4(rgb, tex.a);
	}
	// recolor off: leave COLOR at its default (texture × modulate) so normal
	// rendering and combat-FX tints pass through untouched.
}
