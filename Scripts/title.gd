# ---------------------------------------------------------------------------
# title.gd: the title screen. The name of the game, the story in one line,
# the controls, and "press E to start".
#
# The background is the same Starfield the spacewalk uses (on a CanvasLayer
# behind everything). With no camera in this scene, the stars drift on their own.
# Pressing E fades to black and asks Game (the autoload) to load Level 1.
# Edit the texts in title.tscn: select a Label and change its Text.
# ---------------------------------------------------------------------------
extends Node2D

@onready var start_label: Label = $UI/Start
@onready var fade: ColorRect = $UI/Fade
@onready var astronaut: AnimatedSprite2D = $Astronaut

var _t := 0.0
var _starting := false
var _music: AudioStreamPlayer
var _grab: AudioStreamPlayer


func _ready() -> void:
	Game.new_game()                  # a fresh run: forget old results
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	_music = AudioStreamPlayer.new()             # the title theme (see Game.MUSIC)
	_music.stream = Game.load_music("title")
	_music.volume_db = Game.MUSIC["title"]
	add_child(_music)
	_music.play()
	_grab = _make_player("res://Assets/audio/grab.wav", -4.0)


func _make_player(path: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = volume
	add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	start_label.visible = _starting or int(_t * 2.0) % 2 == 0      # blink
	# the astronaut floats gently, as if in zero-G
	astronaut.position = Vector2(104, 150) + Vector2(sin(_t * 0.7) * 6.0, sin(_t * 1.1) * 8.0)
	astronaut.rotation = sin(_t * 0.5) * 0.25
	if not _starting and _t > 0.5 and Input.is_action_just_pressed("interact"):
		_start()


func _start() -> void:
	_starting = true
	_grab.play()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.parallel().tween_property(_music, "volume_db", -60.0, 0.7)
	await tw.finished
	Game.go_to_level(1)
