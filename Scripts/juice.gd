# ---------------------------------------------------------------------------
# juice.gd: "game feel" helpers. It's an autoload named "Juice".
#
# Juice is the small extra feedback that makes an action feel strong: the game
# freezing for a split second when you get zapped, the camera shaking, the
# astronaut squashing when his boots hit the hull, a battery popping when you
# charge it. None of it changes the rules. These functions only change how
# things LOOK (and sound) for a moment, so the game plays exactly the same
# without them.
#
# Any script can call them by name:
#   Juice.hitstop(0.1)                               freeze the game for 0.1 s
#   Juice.shake(0.6, 0.4)                            shake the camera: strength 0..1, seconds
#   Juice.punch_scale(node, Vector2(1.3, 0.7), 0.2)  squash a node, it springs back
#   Juice.flash(sprite)                              flash a sprite white for a moment
#   Juice.pitch()                                    a pitch near 1, a bit different each time
#
# Who calls it: level.gd when something happens (the zap, a room powering up,
# a crate rolling, landing a drift...), power_cell.gd and pickup.gd when you
# pick them up. player.gd keeps the astronaut's feet on the floor while he
# squashes (squash()).
# ---------------------------------------------------------------------------
extends Node

## Camera shake at full strength (1.0) moves the view this many pixels.
const MAX_SHAKE := 6.0
## How fast the shake wobbles: higher = more jittery.
const SHAKE_SPEED := 40.0

# The shake uses "trauma": a number from 0 (still) to 1 (shaken hard) that
# drops back to 0 over time. The camera moves by trauma squared, so a strong
# shake feels strong but fades out smoothly instead of stopping dead.
var _trauma := 0.0
var _trauma_fall := 1.0       # how much trauma goes away per second
var _shake_t := 0.0
var _noise := FastNoiseLite.new()   # smooth randomness, so the shake wobbles instead of jumping
var _camera: Camera2D
var _stop_id := 0             # hitstop: which freeze is the newest one
var _stop_ends := 0           # ...and when it ends (Time.get_ticks_msec)


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.4


## Hitstop: the whole game stops for `duration` real seconds, then carries on.
## A tiny freeze right at the moment of a hit makes it feel heavy. Fighting
## games do it on every punch; here it's the zap and a room powering up.
## Engine.time_scale = 0 stops everything that uses time: walking, the wire's
## timer, tweens, animations. Sounds keep playing, so you hear the hit.
func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	var ends := Time.get_ticks_msec() + int(duration * 1000.0)
	if ends <= _stop_ends:
		return                    # a longer freeze is already running
	_stop_ends = ends
	_stop_id += 1
	var id := _stop_id
	Engine.time_scale = 0.0
	# This timer ignores time_scale (the last "true"), or it would wait forever.
	await get_tree().create_timer(duration, true, false, true).timeout
	if id == _stop_id:            # the newest freeze ends the slow-down
		Engine.time_scale = 1.0


## Shakes the camera. `intensity` 0..1 (1 = MAX_SHAKE pixels), dying away over
## `duration` seconds. A weaker shake during a stronger one is ignored.
func shake(intensity: float, duration: float) -> void:
	intensity = clampf(intensity, 0.0, 1.0)
	if intensity <= _trauma:
		return
	_trauma = intensity
	_trauma_fall = intensity / maxf(duration, 0.01)


## A quick squash and stretch: the node jumps to `scale_mult` times its size,
## then springs back with a little overshoot. Vector2(1.3, 1.3) = a pop,
## Vector2(1.3, 0.75) = squashed flat, Vector2(0.8, 1.25) = stretched tall.
func punch_scale(node: Node2D, scale_mult: Vector2, duration := 0.2) -> void:
	if not is_instance_valid(node):
		return
	# Remember its normal size the first time, so two punches in a row don't
	# start from a half squashed size and leave it the wrong size.
	var base: Vector2 = node.get_meta("juice_scale", node.scale)
	node.set_meta("juice_scale", base)
	if node.has_meta("juice_tween"):      # (get_meta with a null default would complain)
		var old: Tween = node.get_meta("juice_tween")
		if old and old.is_valid():
			old.kill()                    # a punch still running: start again from the top
	node.scale = base * scale_mult
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.set_meta("juice_tween", tw)


## Flashes a sprite white for `duration` seconds (0.08 = about 5 frames).
## A modulate above 1 brightens every colour towards white.
func flash(node: CanvasItem, duration := 0.08) -> void:
	if not is_instance_valid(node):
		return
	var base: Color = node.get_meta("juice_modulate", node.modulate)
	node.set_meta("juice_modulate", base)
	node.modulate = Color(4.0, 4.0, 4.0, base.a)
	node.create_tween().tween_property(node, "modulate", base, duration)


## A pitch close to 1, different every time (0.92 to 1.08 by default). The same
## sound played over and over at exactly the same pitch sounds robotic; tiny
## changes make it sound natural.
func pitch(spread := 0.08) -> float:
	return randf_range(1.0 - spread, 1.0 + spread)


# The shake moves the camera's `offset`, not its position: the level moves the
# position every frame to follow you, and the offset is added on top.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != _camera:
		_camera = cam                 # a new scene: a new camera
	if cam == null:
		return
	if _trauma <= 0.0:
		if cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
		return
	_trauma = maxf(_trauma - _trauma_fall * delta, 0.0)
	_shake_t += delta * SHAKE_SPEED
	var amount := _trauma * _trauma
	var wobble := Vector2(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t + 50.0))
	# whole pixels only: half a pixel of movement makes pixel art shimmer
	cam.offset = (wobble * 1.6 * MAX_SHAKE * amount).round()
