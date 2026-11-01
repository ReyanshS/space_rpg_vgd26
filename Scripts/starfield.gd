# ---------------------------------------------------------------------------
# starfield.gd  -  the view of space behind everything: stars, a nebula, a planet.
#
# It lives on a CanvasLayer with a NEGATIVE layer number, so it's drawn behind the
# level - and it's NOT darkened by the level's CanvasModulate (that only tints its
# own layer). Anywhere the level draws nothing (open space), you see this.
#
# PARALLAX: far-away things move slower than near things when the camera moves.
# Every star has a "depth" between 0.02 and 0.25: it moves that fraction of the
# camera's movement. The planet (0.05) and nebula (0.02) barely move at all.
# That's what makes it feel deep.
# ---------------------------------------------------------------------------
class_name Starfield
extends Node2D

const PLANET_TEX := "res://Assets/images/space/planet.png"
const NEBULA_TEX := "res://Assets/images/space/nebula.png"
const FIELD := Vector2(1024, 640)     # the stars repeat every this many pixels

## A point in the level that the planet "hangs behind" (set by the level).
@export var focus := Vector2.ZERO
## With no camera (the title screen) the stars drift by themselves at this speed.
@export var auto_scroll := Vector2(-8, 0)
## Where the planet sits on screen, as a fraction of the screen size.
@export var planet_spot := Vector2(0.62, 0.06)

var _stars: Array = []     # each: [position, depth, brightness, twinkle phase, size]
var _planet: Texture2D
var _nebula: Texture2D
var _scroll := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2027            # same sky every time
	for i in 280:
		var size := 2 if rng.randf() < 0.07 else 1
		_stars.append([Vector2(rng.randf() * FIELD.x, rng.randf() * FIELD.y),
			rng.randf_range(0.02, 0.25), rng.randf_range(0.3, 1.0), rng.randf() * TAU, size])
	_planet = load(PLANET_TEX)
	_nebula = load(NEBULA_TEX)


func _process(delta: float) -> void:
	_t += delta
	_scroll += auto_scroll * delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var c := cam.get_screen_center_position() if cam else -_scroll
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.015, 0.02, 0.055))
	if _nebula:
		var np := (view - _nebula.get_size()) * 0.5 + Vector2(-70, 20) - (c - focus) * 0.02
		draw_texture(_nebula, np.round())
	for s in _stars:
		var p: Vector2 = s[0] - c * float(s[1])
		p = Vector2(fposmod(p.x, FIELD.x), fposmod(p.y, FIELD.y))
		if p.x > view.x or p.y > view.y:
			continue
		var twinkle := 0.7 + 0.3 * sin(_t * (1.0 + float(s[1]) * 8.0) + float(s[3]))
		var b := float(s[2]) * twinkle
		draw_rect(Rect2(p.floor(), Vector2(s[4], s[4])), Color(b * 0.85, b * 0.9, b))
	if _planet:
		var pp := view * planet_spot - (c - focus) * 0.05
		draw_texture(_planet, pp.round())
