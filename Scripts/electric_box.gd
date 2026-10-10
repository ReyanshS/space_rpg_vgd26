extends Area2D

var player_in_range: bool = false
var is_powered: bool = false

@onready var color_box = $ColorRect
@onready var power_symbol = $PowerSymbol

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	power_symbol.modulate = Color(1.0, 0.0, 0.0, 1.0) # Red default

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		player_in_range = false

func _process(delta: float) -> void:
	if player_in_range and not is_powered and Input.is_action_just_pressed("ui_accept"):
		trigger_box_interaction()

func trigger_box_interaction() -> void:
	is_powered = true
	
	# Orange-Yellow Palette Swap
	color_box.color = Color(1.0, 0.65, 0.0, 1.0)
	power_symbol.modulate = Color(1.0, 0.65, 0.0, 1.0)
	
	# DIRECT FIX: Tell the main script EXACTLY who clicked first!
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("log_box_activation"):
		main_scene.log_box_activation(name)
