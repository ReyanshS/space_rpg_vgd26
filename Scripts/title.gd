# ---------------------------------------------------------------------------
# title.gd: the title screen. The name of the game, the story in one line,
# the controls, and the buttons to start.
#
# The background is the same Starfield the spacewalk uses (on a CanvasLayer
# behind everything). With no camera in this scene, the stars drift on their own.
# START fades to black and asks Game (the autoload) to load Level 1.
# If there's a save file (you finished a level before), the first button says
# CONTINUE instead and goes to the next level, with your skills. NEW GAME
# appears next to it and starts over (it deletes the save).
# Click a button, or pick one with the arrow keys and press E, Space or Enter.
# Edit the texts in title.tscn: select a Label or Button and change its Text.
# ---------------------------------------------------------------------------
extends Node2D

@onready var play_button: Button = $UI/Buttons/Play
@onready var new_game_button: Button = $UI/Buttons/NewGame
@onready var fade: ColorRect = $UI/Fade
@onready var astronaut: AnimatedSprite2D = $Astronaut

var _t := 0.0
var _starting := false
var _music: AudioStreamPlayer
var _grab: AudioStreamPlayer


func _ready() -> void:
	var saved := Game.load_game() and Game.has_save()   # results and skills come back
	if saved:
		play_button.text = "CONTINUE: LEVEL %d" % Game.continue_level()
	else:
		Game.new_game()              # a fresh run: forget old results
	new_game_button.visible = saved
	play_button.pressed.connect(func() -> void: _start(Game.continue_level() if Game.has_save() else 1))
	new_game_button.pressed.connect(func() -> void:
		Game.new_game()
		_start(1))
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	_music = AudioStreamPlayer.new()             # the title theme (see Game.MUSIC)
	_music.stream = Game.load_music("title")
	_music.volume_db = Game.MUSIC["title"]
	add_child(_music)
	_music.play()
	_grab = _make_player("res://Assets/audio/grab.wav", -4.0)
	# select the first button after a moment, so a key still held from the last
	# screen doesn't press it straight away
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree() and not _starting:
		play_button.grab_focus()


func _make_player(path: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = volume
	add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	# the astronaut floats gently, as if in zero-G
	astronaut.position = Vector2(104, 150) + Vector2(sin(_t * 0.7) * 6.0, sin(_t * 1.1) * 8.0)
	astronaut.rotation = sin(_t * 0.5) * 0.25


func _start(level: int) -> void:
	if _starting:
		return                       # (a second click while it fades)
	_starting = true
	play_button.disabled = true
	new_game_button.disabled = true
	_grab.play()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.parallel().tween_property(_music, "volume_db", -60.0, 0.7)
	await tw.finished
	Game.go_to_level(level)
