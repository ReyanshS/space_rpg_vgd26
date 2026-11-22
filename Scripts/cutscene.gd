# ---------------------------------------------------------------------------
# cutscene.gd: a slideshow cutscene. It shows pictures one after another, with
# a fade in between. E, Space, Enter or a mouse click goes to the next picture,
# Esc skips the rest. When it's over it loads a level.
#
# Scenes/intro.tscn uses it between the title screen and Level 1 (the team's
# three pictures: the cryostasis warning, the station by Uranus, and "wake up").
#
# To change the pictures or their order: open intro.tscn, select the Intro node
# and edit Slides in the Inspector (drag PNGs in from Assets/images/cutscenes).
# Make each picture 480 x 270 pixels, the size of the game's screen, so it's
# shown pixel for pixel. (The team's pictures were bigger; they were shrunk
# with Python, see the AI-use notes in CLAUDE.md.)
# For another cutscene, duplicate intro.tscn and change Slides and Next Level.
# ---------------------------------------------------------------------------
extends Control

## The pictures, in the order they're shown.
@export var slides: Array[Texture2D] = []
## The level to load when the last picture is done (1 = Level 1).
@export var next_level := 1
## Seconds a picture stays before a key works (so one press can't skip two).
@export var min_show := 0.6
## Seconds for each fade to black and back.
@export var fade_time := 0.35
## Music to play under it (a name from Game.MUSIC, e.g. "title"). Empty = none.
@export var music := "title"

@onready var picture: TextureRect = $Picture
@onready var fade: ColorRect = $Fade

var _index := -1
var _shown_for := 0.0
var _changing := false        # a fade is running: ignore keys
var _leaving := false
var _music: AudioStreamPlayer
var _blip: AudioStreamPlayer


func _ready() -> void:
	fade.color.a = 1.0
	if music != "":
		_music = AudioStreamPlayer.new()
		_music.stream = Game.load_music(music)
		_music.volume_db = Game.MUSIC.get(music, -18.0)
		add_child(_music)
		_music.play()
	_blip = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://Assets/audio/blip.wav"):
		_blip.stream = load("res://Assets/audio/blip.wav")
	_blip.volume_db = -6.0
	add_child(_blip)
	if slides.is_empty():
		_finish()
		return
	_go_to(0)


func _process(delta: float) -> void:
	_shown_for += delta
	if _changing or _leaving:
		return
	if Input.is_action_just_pressed("pause"):
		_finish()                                   # Esc: skip the whole cutscene
	elif _shown_for >= min_show and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")):
		_advance()


# A left click also goes on (the pictures say "click E", some people click).
func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if not _changing and not _leaving and _shown_for >= min_show:
			_advance()


func _advance() -> void:
	_blip.play()
	if _index + 1 >= slides.size():
		_finish()
	else:
		_go_to(_index + 1)


## Fade to black (if a picture is showing), swap the picture, fade back in.
## This uses `await`: the function waits at each fade while the game keeps running.
func _go_to(i: int) -> void:
	_changing = true
	if _index >= 0:
		await _fade_to(1.0)
		if not is_inside_tree(): return
	_index = i
	picture.texture = slides[i]
	await _fade_to(0.0)
	if not is_inside_tree(): return
	_shown_for = 0.0
	_changing = false


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, fade_time)
	await tw.finished


## The end (or Esc): fade out picture and music, then load the level.
func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.6)
	if _music:
		tw.parallel().tween_property(_music, "volume_db", -60.0, 0.6)
	await tw.finished
	if not is_inside_tree(): return
	Game.go_to_level(next_level)
