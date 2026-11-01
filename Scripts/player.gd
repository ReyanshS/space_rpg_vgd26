# ---------------------------------------------------------------------------
# player.gd  -  the astronaut you control.
#
# The player is always in exactly ONE "state". Each state decides what the
# arrow keys do:
#   FREE      walking around, not holding the wire
#   WIRED     walking around while carrying the wire. The wire is pulled tight
#             in a straight line from the last pad you touched, so you can't
#             walk anywhere that would make it pass through a crate, wall or
#             red tile (level.gd answers that question for us).
#   CHOOSING  stopped on a purple BEND, waiting for you to press one of its
#             two arrows
#   FLUNG     the BEND is throwing you in a straight line - no steering
#   LOCKED    a short "cut-scene" (shocked, room solved...) - no control
#
# This script only handles moving + animation. The RULES live in level.gd.
# The player tells the level "I moved" by calling level.player_moved(), and
# the level answers by calling functions back on the player (choose_fling,
# lock, release...).
# ---------------------------------------------------------------------------
class_name Astronaut          # lets other scripts use "Astronaut" as a type
extends CharacterBody2D       # the node type this script is attached to

enum State { FREE, WIRED, CHOOSING, FLUNG, LOCKED }

const LAMP_ENERGY := 0.85     # helmet lamp brightness when it's on

# Half the size of the box around his feet that bumps into walls (12 x 8 px).
# `position` is the point between his feet.
const FEET_HALF := Vector2(6, 4)

# @export shows these in the Inspector so you can tweak them without code.
## Walking speed in pixels per second (100 = about 3 tiles a second).
@export var walk_speed := 100.0
## How fast a BEND pad throws you.
@export var fling_speed := 260.0

var level: WireLevel = null   # set by the level when the game starts
var state: State = State.FREE
var facing := Vector2i(0, 1)  # which way he looks: (0,1) = down, towards the camera
var _last_x := 1              # last left/right he faced (for sprites with no "walk_up")

var _fling_dir := Vector2.ZERO
var _choice_at := Vector2.ZERO
var _choices: Array[Vector2] = []
var _moving := false
var _carrying := false
var _anim_override := ""      # forces an animation ("shock", "burnt")
var _lamp: PointLight2D       # helmet lamp - only on in rooms with no power
var _lamp_tween: Tween
var _hand_light: PointLight2D # yellow glow from the live wire in his hands

# @onready = fill this in once the scene is loaded. $AnimatedSprite2D is
# shorthand for get_node("AnimatedSprite2D").
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")    # the tutorial finds the player with get_first_node_in_group("player")
	sprite.play(_first_existing(["idle_down", "idle"]))
	_lamp = LightFX.make(Color(0.8, 0.9, 1.0), 100.0, LAMP_ENERGY)
	_lamp.position = Vector2(0, -18)          # at the helmet
	add_child(_lamp)
	_hand_light = LightFX.make(Color(1.0, 0.8, 0.35), 44.0, 0.7)
	_hand_light.visible = false
	add_child(_hand_light)


# Godot calls _physics_process 60 times a second. `delta` is the time since the
# last call (~0.016 s). Multiplying speeds by delta keeps movement the same
# speed on fast and slow computers.
func _physics_process(delta: float) -> void:
	match state:
		State.FREE, State.WIRED:
			_walk(delta)
			if level:
				level.player_moved()
		State.CHOOSING:
			_moving = false
			_choose()
		State.FLUNG:
			_fling_step(delta)
		State.LOCKED:
			_moving = false
	_update_anim()
	_hand_light.visible = _carrying
	_hand_light.position = hand_position() - position


# ------------------------------------------------------------------ called by the level

func is_wired() -> bool:
	return state in [State.WIRED, State.CHOOSING, State.FLUNG] or (state == State.LOCKED and _carrying)


func grab_wire() -> void:
	state = State.WIRED
	_carrying = true


## Stopped on a BEND: stand on its centre and wait for one of the two directions.
func choose_fling(at: Vector2, options: Array[Vector2]) -> void:
	position = at
	_choice_at = at
	_choices = options
	state = State.CHOOSING


## Fly off in a straight line from `from`.
func fling(from: Vector2, dir: Vector2) -> void:
	position = from
	_fling_dir = dir.normalized()
	_face(_fling_dir)
	state = State.FLUNG


## The fling ended on a node (or hit something) - you can walk again.
func land() -> void:
	if state == State.FLUNG:
		state = State.WIRED


func lock(keep_carrying := false) -> void:
	state = State.LOCKED
	_carrying = keep_carrying
	_moving = false


func release() -> void:
	state = State.FREE
	_carrying = false
	_anim_override = ""


## Fade the helmet lamp on or off. The level calls this: off once a room has
## power (the ceiling lights take over), on again when you walk into a dark room.
func set_lamp(on: bool) -> void:
	if _lamp_tween:
		_lamp_tween.kill()        # stop a fade that's still running, so two don't fight
	_lamp_tween = create_tween()
	_lamp_tween.tween_property(_lamp, "energy", LAMP_ENERGY if on else 0.0, 0.8)


func play_shock() -> void:
	_anim_override = "shock"


func play_burnt() -> void:
	_anim_override = "burnt"


## Where the wire attaches: his hands, a bit above his feet.
func hand_position() -> Vector2:
	var x := 0.0
	if facing.x > 0:
		x = 3.0
	elif facing.x < 0:
		x = -3.0
	return position + Vector2(x, -9.0)


# ------------------------------------------------------------------ walking

func _walk(delta: float) -> void:
	# get_vector turns the 4 arrow/WASD actions into one direction (length 0..1)
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_moving = input.length() > 0.1
	if _moving:
		_face(input)
	if level == null:
		# The old prototype scene (main.tscn) has no level: use normal physics.
		velocity = input * walk_speed
		move_and_slide()
		return
	var step := input * walk_speed * delta
	# Move X and Y separately so you slide along walls instead of sticking.
	_slide(Vector2(step.x, 0.0), absf(input.y) < 0.2)
	_slide(Vector2(0.0, step.y), absf(input.x) < 0.2)


## Can the astronaut stand at `pos`? Not inside a wall, and (if wired) the
## wire must still reach him in a straight line.
func _can_stand(pos: Vector2) -> bool:
	if level.box_blocked(pos, FEET_HALF):
		return false
	if state == State.WIRED and not level.wire_reaches(pos):
		return false
	return true


func _slide(mv: Vector2, may_nudge: bool) -> void:
	if mv == Vector2.ZERO:
		return
	if _can_stand(position + mv):
		position += mv
		return
	# Something's in the way: creep forward in tiny steps to get right up to it.
	var dir := mv.normalized()
	var remaining := mv.length()
	while remaining > 0.0:
		var s := minf(0.25, remaining)
		if not _can_stand(position + dir * s):
			break
		position += dir * s
		remaining -= s
	if remaining <= 0.0:
		return
	if state == State.WIRED and not level.box_blocked(position + dir * remaining, FEET_HALF):
		level.wire_strained(position + dir * remaining)   # it was the wire, not a wall
	elif may_nudge:
		_nudge_around_corner(dir)


## Slides you sideways around a corner so doorways are easy to walk into.
func _nudge_around_corner(dir: Vector2) -> void:
	var perp := Vector2(absf(dir.y), absf(dir.x))
	for k in range(1, 11):
		for s in [-1.0, 1.0]:
			if _can_stand(position + perp * (k * s) + dir):
				var step: Vector2 = perp * s
				if _can_stand(position + step):
					position += step
				return


func _face(v: Vector2) -> void:
	var f := Vector2i(int(signf(v.x)) if absf(v.x) > 0.3 else 0, int(signf(v.y)) if absf(v.y) > 0.3 else 0)
	if f != Vector2i.ZERO:
		facing = f
	if f.x != 0:
		_last_x = f.x


## "down", "up", "right" or "left" - picks which animation set to use.
## Walking diagonally uses the side view.
func _dir_name() -> String:
	if facing.x > 0:
		return "right"
	if facing.x < 0:
		return "left"
	return "up" if facing.y < 0 else "down"


# ------------------------------------------------------------------ bends

## On a bend: wait until the keys point (roughly) at one of the two options.
func _choose() -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input.length() < 0.5:
		return
	for option in _choices:
		# dot = how much two directions agree: 1 same way, 0 sideways, -1 opposite
		if input.normalized().dot(option) > 0.65:
			level.bend_chosen()
			fling(_choice_at, option)
			return


func _fling_step(delta: float) -> void:
	_moving = true
	var remaining := fling_speed * delta
	# Move 2 px at a time so we can't skip past a wall, a red tile or a pad.
	while remaining > 0.0 and state == State.FLUNG:
		var s := minf(2.0, remaining)
		var next := position + _fling_dir * s
		if level.box_blocked(next, FEET_HALF):
			land()                 # hit something solid: you can walk again
			level.fling_stopped()
			return
		position = next
		remaining -= s
		level.player_moved()       # may touch a pad / get shocked (changes state)


# ------------------------------------------------------------------ animation

## Which animation to play. The sprite's animations live in a SpriteFrames file
## (Assets/images/astronaut/*_frames.tres). Different sprites have different
## animations: the original astronaut has "idle", "walk_down", "walk_left",
## "walk_right"; the v2 one also has "walk_up" and an idle for every direction.
## So for each situation we list what we'd LIKE, best first, and play the first
## one this sprite actually has. Swap the sprite and this code still works.
func _update_anim() -> void:
	var dir := _dir_name()
	var side := "right" if _last_x > 0 else "left"
	var anim: String
	if _anim_override != "":
		anim = _anim_override                                   # "shock" / "burnt"
	elif _moving:
		anim = _first_existing(["walk_" + dir, "walk_" + side])  # no walk_up? walk sideways
	elif _carrying and dir == "down":
		anim = "carry"                                          # facing the camera, plug in hands
	elif _carrying:
		anim = _first_existing(["idle_" + dir, "carry"])
	else:
		anim = _first_existing(["idle_" + dir, "idle"])
	sprite.speed_scale = 2.0 if state == State.FLUNG else 1.0
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


## The first animation in `names` that the sprite has (or the last one if none do).
func _first_existing(names: Array) -> String:
	for n in names:
		if sprite.sprite_frames.has_animation(n):
			return n
	return names[-1]
