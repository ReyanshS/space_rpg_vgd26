# ---------------------------------------------------------------------------
# rogue_pip.gd: PIP's body in Level 3, and the boss fight against him.
#
# The story: the ship is finally at full power, and the surge scrambles PIP's
# safety programs. He decides all that power is "unsafe" and starts switching
# the ship off again. He hides in his core chamber, docked on a CORE socket.
# Wrapping the live wire all the way round his core reboots him a little.
# Three sockets = three reboots = PIP is himself again.
#
# How it fits in (the same idea as story.gd: the level doesn't know we exist)
#   - The rules stay in level.gd: a core room gets power when the wire goes
#     all the way round its core. This script never changes a rule.
#   - It listens: level.room_solved tells it when the malfunction room got
#     power, and when you closed a loop round the core PIP is docked on.
#   - It asks the level for a few things: cut_wire() (his shutdown pulse),
#     set_alert() (red lights + boss music), shake(), and hold() / let_go()
#     ("wait for my cutscene before you open the doors").
#   - It draws PIP itself in _draw(): a little floating monitor with a face.
#
# The shutdown meter: while you carry the wire in the room PIP is docked in, a
# bar of 12 red lights over his head fills up. When it's full he sends out a
# pulse that cuts your wire (the room resets). shutdown_seconds = how long it
# takes, one number per phase. So the loop has to be fast, not just possible.
#
# Moods: a small state machine for how he looks (like the player's State).
#   ASLEEP  docked and dozing, before the surge (green, eyes shut)
#   ROGUE   red face, angry eyes, the meter is running
#   HIT     a loop just closed round him: white flash, X eyes
#   OFF     the last loop shut him down: black screen
#   BOOT    restarting: a loading bar
#   AWAKE   himself again (green, smiling)
#
# Where he goes: you don't place PIP himself. Paint CORE tiles (@) in the map:
# the core in room `malfunction_room` is the sync pylon that turns him, and the
# cores in the rooms after it are his sockets, in walking order. This script is
# a @tool, so the editor shows a preview: a PIP on each socket with its number
# and shutdown time, and a dotted line for the way he flies.
# ---------------------------------------------------------------------------
@tool
class_name RoguePip
extends Node2D

enum Mood { ASLEEP, ROGUE, HIT, OFF, BOOT, AWAKE }

const GREEN := Color(0.66, 0.94, 0.63)
const RED := Color(1.0, 0.33, 0.27)
const CASE := Color(0.29, 0.32, 0.38)
const CASE_LIGHT := Color(0.54, 0.58, 0.65)
const OUTLINE := Color(0.03, 0.04, 0.09)
const SIZE := 2.0           # he's drawn at twice the size of his console face: he's the boss
const HOVER := 44.0          # he floats this many pixels above his socket (a cable plugs him in)
const LEDS := 12             # lights in the shutdown meter

## Powering this room (its number in walking order: 0 = the first room) is what
## overloads PIP. From then on he defends the cores of the rooms after it.
@export var malfunction_room := 0
## Seconds PIP needs to fill his shutdown meter, one number per socket (phase).
## Check the solver's "s in all" for each stage: a good player needs about that
## long, so give them some extra on top.
@export var shutdown_seconds: PackedFloat32Array = [18.0, 15.0, 19.0]

@export_group("Lines")
## Normal PIP, as the surge hits him (the player presses E through these).
@export var surge_lines: PackedStringArray = [
	"Sync loop's holding. Core power at 100 percent. 140. 300?",
	"That's too much. That's way too much p... p... p...",
]
## Straight after the malfunction, said by "P!P".
@export var rogue_lines: PackedStringArray = [
	"POWER LEVELS UNSAFE. SHUTDOWN PROTOCOL ON.",
	"I AM SWITCHING THE SHIP OFF. ALL OF IT. FOR YOUR SAFETY.",
	"STAY OUT OF MY CORE ROOM. WIRES ARE NOT ALLOWED NEAR ME.",
]
## One per loop he survives (said by "P!P" as he flies to his next socket).
## His blue arrow points at the socket he's flying to.
@export var escape_lines: PackedStringArray = [
	"REBOOT 1 OF 3? NO. NO THANK YOU. TRY CATCHING ME BEHIND THE CARGO.",
	"REBOOT 2 OF 3. my head feels cl... NO IT DOESN'T. THE FLOOR HERE IS LIVE.",
]
## After the last loop, when he's himself again (press E through these).
@export var reboot_lines: PackedStringArray = [
	"Ow. Why is there a wire tied round me?",
	"Oh no. I tried to switch the whole ship off, didn't I?",
	"All that power at once gave me the hiccups. Sorry about the yelling.",
	"Thanks for getting me back. I've got the controls now. Let's go home.",
]
## One of these, picked at random, when his pulse cuts your wire.
@export var cut_lines: PackedStringArray = [
	"SNIP. NO POWER, NO PROBLEMS.",
	"SHUTDOWN 1, ASTRONAUT 0.",
	"TOO SLOW. SAFETY WINS AGAIN.",
	"I SAID NO WIRES.",
]

var mood: Mood = Mood.ASLEEP
var _level: WireLevel
var _spots: Array = []        # [room index, pixel position] of each socket he defends
var _phase := -1              # which socket he's on (-1 = not fighting)
var _home := Vector2.ZERO     # where he hovers (a tween moves it when he flies)
var _charge := 0.0            # shutdown meter, in seconds
var _beep := 0.0
var _wave := -1.0             # the pulse ring: 0..1 while it spreads, -1 = none
var _boot := 0.0              # loading bar, 0..1
var _flight: Array = []       # [start, top, end] of the curve he's flying along
var _t := 0.0
var _light: PointLight2D
var _sfx := {}
var _preview: Array = []      # editor only: [room index, pixel position] of every core
var _preview_wait := 0.0


func _ready() -> void:
	z_index = 5                    # he floats above the floor and the player's feet
	if Engine.is_editor_hint():
		return                     # in the editor we only draw a preview (see _process)
	LightFX.glow(self)             # his screen shines in the dark
	visible = false
	_start.call_deferred()         # the level isn't ready yet (children go first)


func _start() -> void:
	_level = get_tree().get_first_node_in_group("level") as WireLevel
	if _level == null:
		return
	for spot in _level.core_spots():
		if spot[0] > malfunction_room:
			_spots.append(spot)
	if _spots.is_empty():
		push_warning("RoguePip: no CORE tiles after room %d to dock on." % malfunction_room)
		return
	# Playtesting from a TestStart marker (F6) further in? Then the rooms before
	# it are done: count the sockets he already lost, and start on the next one.
	var testing := _level.test_room > malfunction_room
	var start_phase := 0
	if testing:
		for spot in _spots:
			if spot[0] < _level.test_room:
				start_phase += 1
	_home = _dock(mini(start_phase, _spots.size() - 1))
	position = _home
	visible = true
	_light = LightFX.make(GREEN, 70.0, 0.5)
	add_child(_light)
	for n in ["glitch", "warn", "boot", "shock"]:
		var p := AudioStreamPlayer.new()
		var path := "res://Assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_sfx[n] = p
	_sfx["warn"].volume_db = -8.0
	_level.room_solved.connect(_on_room_solved)
	if testing:
		if start_phase < _spots.size():
			_phase = start_phase            # already rogue, defending this socket
			mood = Mood.ROGUE
			_level.set_alert(true)
			_level.hud.set_rogue(true)
		else:
			mood = Mood.AWAKE               # every socket is behind you: he's rebooted


## Where he hovers over socket number i.
func _dock(i: int) -> Vector2:
	return _spots[i][1] + Vector2(0, -HOVER)


func _play(n: String) -> void:
	var p: AudioStreamPlayer = _sfx.get(n)
	if p and p.stream:
		p.play()


# ------------------------------------------------------------------ every frame

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _level == null or _spots.is_empty():
		return
	_t += delta
	position = (_home + Vector2(0, roundf(sin(_t * 2.2) * 2.0))).round()   # bob up and down
	if _wave >= 0.0:
		_wave += delta * 2.0
		if _wave > 1.0:
			_wave = -1.0
	_update_meter(delta)
	if _light:
		var col := GREEN
		match mood:
			Mood.ROGUE: col = RED
			Mood.HIT: col = Color.WHITE
			Mood.OFF: col = Color.BLACK
		_light.color = col
		_light.energy = 0.0 if mood == Mood.OFF else 0.55 + 0.25 * _meter()
	queue_redraw()


## The shutdown meter fills while you carry the wire in his room, and drains
## fast when you don't. Full = he pulses and cuts your wire.
func _update_meter(delta: float) -> void:
	if mood != Mood.ROGUE or _phase < 0:
		_charge = 0.0
		return
	if _level.wire_room_index() != _spots[_phase][0]:
		_charge = move_toward(_charge, 0.0, delta * 10.0)
		return
	_charge += delta
	var limit := _limit()
	# beeps: slow at first, faster as the meter fills
	_beep -= delta
	if _beep <= 0.0 and _meter() > 0.5:
		_play("warn")
		_beep = lerpf(0.6, 0.12, (_meter() - 0.5) * 2.0)
	if _charge >= limit:
		_pulse()


func _limit() -> float:
	if _phase >= 0 and _phase < shutdown_seconds.size():
		return shutdown_seconds[_phase]
	return 16.0


## How full the meter is: 0 = empty, 1 = full.
func _meter() -> float:
	return clampf(_charge / _limit(), 0.0, 1.0)


## Shutdown pulse: a red ring spreads out from him and the wire is cut.
func _pulse() -> void:
	_charge = 0.0
	_wave = 0.0
	_play("glitch")
	_level.cut_wire()
	if not cut_lines.is_empty():
		_level.hud.say(PackedStringArray([cut_lines[randi() % cut_lines.size()]]), GameHUD.ROGUE_SPEAKER)


# ------------------------------------------------------------------ story moments

func _on_room_solved(index: int) -> void:
	if index == malfunction_room and mood == Mood.ASLEEP:
		_malfunction()
	elif _phase >= 0 and _phase < _spots.size() and index == _spots[_phase][0]:
		_caught()


## Waits until PIP has finished talking (the player presses E through blocking lines).
func _until_quiet() -> void:
	await get_tree().process_frame
	while _level.hud.is_talking() and is_inside_tree():
		await get_tree().process_frame


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


## The power surge hits him. The level waits (hold) until we let go, so the
## door to his core room only opens after he's turned.
func _malfunction() -> void:
	_level.hold()
	await _wait(0.6)
	mood = Mood.AWAKE
	_level.hud.say(surge_lines, "PIP", true)
	await _until_quiet()
	# the glitch: flicker between his normal face and the red one
	for i in 6:
		mood = Mood.ROGUE if i % 2 == 0 else Mood.AWAKE
		_play("glitch")
		_level.hud.set_rogue(i % 2 == 0)
		await _wait(0.12)
	mood = Mood.ROGUE
	_level.hud.set_rogue(true)
	_level.hud.flash(RED, 0.7)
	_level.shake(0.7, 3.0)
	_level.set_alert(true)          # red lights, flashing alarms, boss music
	_phase = 0
	await _wait(0.8)
	_level.hud.say(rogue_lines, GameHUD.ROGUE_SPEAKER, true)
	await _until_quiet()
	_level.let_go()


## You closed a loop round the core he's docked on.
func _caught() -> void:
	_level.hold()
	_charge = 0.0
	mood = Mood.HIT
	_play("shock")
	_play("glitch")
	_level.shake(0.4, 2.5)
	_sparks(18)
	await _wait(1.2)
	if _phase + 1 < _spots.size():
		# not finished yet: he shakes it off and flies to his next socket
		mood = Mood.ROGUE
		var line := escape_lines[_phase] if _phase < escape_lines.size() else ""
		_phase += 1
		_level.let_go()             # the barrier sinks while he flies
		await _fly_to(_dock(_phase))
		if line != "":
			# the blue arrow points at him (just above his shutdown meter)
			_level.hud.say(PackedStringArray([line]), GameHUD.ROGUE_SPEAKER, false, _dock(_phase) + Vector2(0, -40))
		return
	# the last loop: he shuts down, reboots, and he's PIP again
	_phase = -1
	mood = Mood.OFF
	_light.energy = 0.0
	_level.set_music_override("none")   # the music fades out while he's switched off
	_level.set_alert(false)
	await _wait(1.2)
	mood = Mood.BOOT
	_play("boot")
	_boot = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_boot", 1.0, 1.4)
	await tw.finished
	mood = Mood.AWAKE
	_level.hud.set_rogue(false)
	_level.set_music_override("ending")   # he's back: the ending theme, to the last results
	_sparks(12)
	await _wait(0.4)
	_level.hud.say(reboot_lines, "PIP", true)
	await _until_quiet()
	_level.let_go()                 # now the lights-on cutscene can play


## Flies to `target` in a curve (up and over), like a drone, not a straight slide.
func _fly_to(target: Vector2) -> void:
	_flight = [_home, (_home + target) * 0.5 + Vector2(0, -60), target]
	var tw := create_tween()
	tw.tween_method(_fly_step, 0.0, 1.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## k = 0 at the start of the flight, 1 at the end. A "quadratic Bezier curve":
## slide along start->top and along top->end at the same time, and blend the
## two (more of the second as k grows). The result is a smooth arc.
func _fly_step(k: float) -> void:
	var a: Vector2 = _flight[0].lerp(_flight[1], k)
	var b: Vector2 = _flight[1].lerp(_flight[2], k)
	_home = a.lerp(b, k)


func _sparks(amount: int) -> void:
	var s := Wire.make_sparks(Color(0.8, 1.0, 1.0), amount, 0.5)
	s.one_shot = true
	s.explosiveness = 1.0
	s.position = position
	s.z_index = 6
	get_parent().add_child(s)
	s.emitting = true
	get_tree().create_timer(1.0).timeout.connect(s.queue_free)


# ------------------------------------------------------------------ drawing

## Editor only: twice a second, ask the level where the cores are (the map may
## have just been painted) and redraw the preview.
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_preview_wait -= delta
	if _preview_wait > 0.0:
		return
	_preview_wait = 0.5
	var level := get_parent() as WireLevel
	_preview = level.editor_core_spots() if level else []
	queue_redraw()


## Editor only: the sync pylon, then PIP on each socket he'll defend, numbered,
## with how long his shutdown meter takes there, joined by his flight path.
func _draw_preview() -> void:
	var level := get_parent() as WireLevel
	if level == null:
		return
	var font := ThemeDB.fallback_font
	var prev := Vector2.INF
	var n := 0
	var keep := mood
	mood = Mood.ROGUE
	for spot in _preview:
		var at := to_local(level.to_global(spot[1]))
		if spot[0] == malfunction_room:
			draw_string(font, at + Vector2(-30, -22), "SYNC PYLON", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GREEN)
			draw_string(font, at + Vector2(-44, 30), "powering it turns PIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GREEN)
			continue
		if spot[0] < malfunction_room:
			continue
		var hover := at + Vector2(0, -HOVER)
		if prev.is_finite():
			var d := prev.distance_to(hover)
			var t := 0.0
			while t < d:
				draw_rect(Rect2(prev.lerp(hover, t / d) - Vector2.ONE, Vector2(2, 2)), Color(RED, 0.7))
				t += 8.0
		prev = hover
		draw_line(hover + Vector2(0, 20), at - Vector2(0, 6), OUTLINE, 3.0)
		draw_set_transform(hover, 0.0, Vector2(SIZE, SIZE))
		_draw_body()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var secs := shutdown_seconds[n] if n < shutdown_seconds.size() else 16.0
		draw_string(font, hover + Vector2(-34, -40), "PIP %d   %d s" % [n + 1, int(secs)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RED)
		n += 1
	mood = keep


func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_preview()
		return
	var bob := position - _home
	var socket := Vector2(0, HOVER) - bob          # the socket's centre, from where he is now
	# his shadow on the socket, and the cable that plugs him into it
	_ellipse(socket + Vector2(0, 2), Vector2(14, 4), Color(0, 0, 0, 0.35))
	var cable := RED.darkened(0.3) if mood == Mood.ROGUE else Color(0.3, 0.6, 0.4)
	draw_line(Vector2(0, 20), socket - Vector2(0, 6), OUTLINE, 4.0)
	draw_line(Vector2(0, 20), socket - Vector2(0, 6), cable, 2.0)
	if _wave >= 0.0:
		draw_arc(Vector2.ZERO, 8.0 + _wave * 230.0, 0.0, TAU, 48, Color(RED, 1.0 - _wave), 3.0)
	if mood == Mood.ROGUE:
		_draw_meter()
	# from here on everything is drawn twice as big (each pixel becomes 2 x 2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(SIZE, SIZE))
	_draw_body()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## PIP himself, at normal size: a little monitor with a face (_draw scales it up).
func _draw_body() -> void:
	# thruster flame under him
	if mood != Mood.OFF:
		var flame := 2.0 + float(int(_t * 20.0) % 3)
		draw_rect(Rect2(-2, 9, 4, flame), Color(1.0, 0.6, 0.2) if mood == Mood.ROGUE else Color(0.5, 0.9, 1.0))
	# antenna with a blinking tip
	draw_rect(Rect2(-1, -14, 1, 5), CASE_LIGHT)
	var tip := RED if mood == Mood.ROGUE else Color(1.0, 0.76, 0.3)
	if fmod(_t, 1.0) < 0.5 and mood != Mood.OFF:
		draw_rect(Rect2(-2, -16, 3, 2), tip)
	# the monitor case and its screen
	draw_rect(Rect2(-12, -10, 24, 20), OUTLINE)
	draw_rect(Rect2(-11, -9, 22, 18), CASE)
	draw_rect(Rect2(-11, -9, 22, 1), CASE_LIGHT)
	draw_rect(Rect2(-9, -7, 18, 13), _screen_color())
	_draw_face()
	for y in range(-6, 6, 2):
		draw_rect(Rect2(-9, y, 18, 1), Color(0, 0, 0, 0.25))          # scanlines


func _screen_color() -> Color:
	match mood:
		Mood.ROGUE: return Color(0.18, 0.03, 0.03)
		Mood.HIT: return Color(0.9, 0.95, 1.0) if int(_t * 16.0) % 2 == 0 else Color(0.2, 0.3, 0.4)
		Mood.OFF: return Color(0.02, 0.02, 0.03)
	return Color(0.03, 0.12, 0.06)


func _draw_face() -> void:
	match mood:
		Mood.OFF:
			return
		Mood.BOOT:
			draw_rect(Rect2(-6, 0, 12, 2), Color(0.1, 0.3, 0.15))
			draw_rect(Rect2(-6, 0, roundf(12.0 * _boot), 2), GREEN)
			if int(_t * 4.0) % 2 == 0:
				draw_rect(Rect2(-6, -4, 2, 2), GREEN)                    # blinking cursor
			return
		Mood.HIT:
			for x in [-5.0, 2.0]:                                          # X X eyes
				for k in 3:
					draw_rect(Rect2(x + k, -5 + k, 1, 1), OUTLINE)
					draw_rect(Rect2(x + 2 - k, -5 + k, 1, 1), OUTLINE)
			return
	var ink := RED if mood == Mood.ROGUE else GREEN
	# a glitch now and then (rogue only): the whole face jumps a pixel sideways
	var o := Vector2(signf(sin(_t * 37.0)), 0) if mood == Mood.ROGUE and fmod(_t * 3.0, 4.0) < 0.4 else Vector2.ZERO
	if mood == Mood.ASLEEP:
		for x in [-6.0, 2.0]:
			draw_rect(Rect2(o + Vector2(x, -2), Vector2(4, 1)), ink.darkened(0.3))   # eyes shut
		draw_rect(Rect2(o + Vector2(-2, 2), Vector2(4, 1)), ink.darkened(0.3))
		_draw_z()
		return
	# the eyes look at the astronaut
	var look := Vector2.ZERO
	if _level and _level.player:
		var d := _level.player.global_position - global_position
		look = Vector2(clampf(d.x / 60.0, -1.0, 1.0), clampf(d.y / 60.0, -1.0, 1.0)).round()
	for x in [-6.0, 2.0]:
		if mood == Mood.ROGUE:
			# angry: the top of each eye slopes down towards the middle
			var inner := 3.0 if x < 0.0 else 0.0
			for k in 4:
				var drop := roundf(absf(k - inner) * 0.5)
				draw_rect(Rect2(o + Vector2(x + k, -5 + drop), Vector2(1, 4 - drop)), ink)
		else:
			draw_rect(Rect2(o + Vector2(x, -5), Vector2(4, 4)), ink)
		draw_rect(Rect2(o + Vector2(x + 1.5, -4) + look, Vector2(1, 2)), _screen_color())   # pupil
	if mood == Mood.ROGUE:
		draw_rect(Rect2(o + Vector2(-3, 2), Vector2(6, 1)), ink)             # flat, cross mouth
	else:
		draw_rect(Rect2(o + Vector2(-4, 1), Vector2(1, 1)), ink)             # a smile
		draw_rect(Rect2(o + Vector2(-3, 2), Vector2(6, 1)), ink)
		draw_rect(Rect2(o + Vector2(3, 1), Vector2(1, 1)), ink)


## Little "z"s floating up while he dozes.
func _draw_z() -> void:
	var k := fmod(_t * 0.6, 1.0)
	var p := Vector2(10 + k * 6.0, -14 - k * 10.0).round()
	var c := Color(GREEN, 1.0 - k)
	draw_rect(Rect2(p, Vector2(3, 1)), c)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), c)
	draw_rect(Rect2(p + Vector2(0, 2), Vector2(3, 1)), c)


## The shutdown meter: 12 red lights in a dark case over his head, lit one by
## one, left to right. They blink once it's nearly full.
func _draw_meter() -> void:
	var lit := ceili(_meter() * LEDS - 0.001)
	var hot := _meter() > 0.75 and int(_t * 8.0) % 2 == 0
	var w := LEDS * 5 + 3
	var top := Vector2(-w / 2.0, -48).round()
	draw_rect(Rect2(top, Vector2(w, 9)), Color(0.04, 0.03, 0.05, 0.9))
	draw_rect(Rect2(top, Vector2(w, 9)), Color(0.45, 0.2, 0.2), false, 1.0)
	for i in LEDS:
		var r := Rect2(top + Vector2(2 + i * 5, 2), Vector2(4, 5))
		if i < lit:
			var col := Color(1.0, 0.85, 0.8) if hot else RED
			draw_rect(r, col)
			draw_rect(Rect2(r.position, Vector2(4, 1)), col.lightened(0.5))
		else:
			draw_rect(r, Color(0.22, 0.06, 0.06))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
