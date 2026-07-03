extends RefCounted

# Builds/configures the player palette-swap ShaderMaterial
# (Hair / Shirt / Pants / Shoes / Skin — mask-driven, see player_recolor.gdshader).
# Shared by the character-creator preview and the in-game player so both look
# identical. Referenced via `const PlayerSkin = preload("res://PlayerSkin.gd")`.

const SHADER = preload("res://player_recolor.gdshader")
const GROUP_MASK = preload("res://Asset/sprites/characters/player_groups_mask.png")

# Base shades of the repainted sprite — the "no change" defaults for pickers.
const DEF_HAIR  := Color("573a23")
const DEF_SHIRT := Color("8f0303")
const DEF_PANTS := Color("2c65b5")
const DEF_SHOES := Color("573a23")
const DEF_SKIN  := Color("ac7b5d")

static func make_material(hair: Color, shirt: Color, pants: Color, shoes: Color, skin: Color) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("group_mask", GROUP_MASK)
	m.set_shader_parameter("recolor_on", 1.0)   # explicit: unset uniforms don't reliably take the shader default
	apply_colors(m, hair, shirt, pants, shoes, skin)
	return m

static func apply_colors(m: ShaderMaterial, hair: Color, shirt: Color, pants: Color, shoes: Color, skin: Color) -> void:
	if m == null:
		return
	m.set_shader_parameter("hair_color",  Vector3(hair.r,  hair.g,  hair.b))
	m.set_shader_parameter("shirt_color", Vector3(shirt.r, shirt.g, shirt.b))
	m.set_shader_parameter("pants_color", Vector3(pants.r, pants.g, pants.b))
	m.set_shader_parameter("shoe_color",  Vector3(shoes.r, shoes.g, shoes.b))
	m.set_shader_parameter("skin_color",  Vector3(skin.r,  skin.g,  skin.b))
