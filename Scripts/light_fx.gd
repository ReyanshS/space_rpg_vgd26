# ---------------------------------------------------------------------------
# light_fx.gd  -  one helper that makes soft round 2D lights.
#
# HOW 2D LIGHTING WORKS IN GODOT (the short version)
#   - A CanvasModulate node tints EVERYTHING on its canvas. A dark blue
#     CanvasModulate = the ship with the power off.
#   - A PointLight2D adds light back in a shape given by its texture. Ours is
#     a white circle that fades to transparent at the edge, so the light is
#     bright in the middle and soft at the edges.
#   - Final colour of a pixel = its own colour x (darkness tint + all lights on it).
#
# LIGHT CHANNELS - how wires and pads "shine" in the dark
#   Every CanvasItem (sprite, line, particles...) has a `light_mask`: which
#   light CHANNELS it listens to. Every light has a `range_item_cull_mask`:
#   which channels it shines on. Normal things and normal lights use channel 1.
#   Things that should glow by themselves (wires, pad halos, floor guides) call
#   LightFX.glow(item): they switch to channel 2 ONLY. The level adds ONE big,
#   flat "glow light" that shines on channel 2 only - so glowing things show
#   their full colour, while the darkness and the room lights ignore them.
#   They stay in the normal world, so the astronaut still walks on top of them.
#
# Usage: var lamp := LightFX.make(Color.WHITE, 80.0, 0.9)  -> add_child(lamp)
#        LightFX.glow(my_line)   -> my_line now shines in the dark
# ---------------------------------------------------------------------------
class_name LightFX
extends RefCounted

const GLOW_CHANNEL := 2      # light_mask bit 2 (the value 2 = binary 10)

static var _tex: GradientTexture2D
static var _flat_tex: ImageTexture


## The shared circular "light shape" texture (made once, used by every light).
static func texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)     # centre of the circle
		_tex.fill_to = Vector2(1.0, 0.5)       # edge of the circle
		_tex.width = 128
		_tex.height = 128
	return _tex


## A soft light. `radius` is in pixels (a tile is 32), `energy` is brightness (about 0-1).
static func make(color: Color, radius: float, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = texture()
	l.texture_scale = radius / 64.0        # the texture's circle is 64 px in radius
	l.color = color
	l.energy = energy
	return l


## Make `item` glow: it listens ONLY to the glow channel, so the darkness can't dim it.
## (light_mask is NOT passed on to children - each drawn node needs its own call.)
static func glow(item: CanvasItem) -> void:
	item.light_mask = GLOW_CHANNEL


## The one flat light (no fade - a plain white square) that covers `area`
## and shines ONLY on glowing things. The level makes one of these.
## darkness (~0.2) + energy (0.8) = about 1 = the thing's normal, full colour.
static func make_glow_light(area: Rect2, energy := 0.8) -> PointLight2D:
	if _flat_tex == null:
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_flat_tex = ImageTexture.create_from_image(img)
	var l := PointLight2D.new()
	l.texture = _flat_tex
	l.texture_scale = maxf(area.size.x, area.size.y) / 4.0 + 1.0   # stretch the 4 px square over the area
	l.position = area.get_center()
	l.energy = energy
	l.range_item_cull_mask = GLOW_CHANNEL      # only things on channel 2 feel it
	return l
