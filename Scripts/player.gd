extends CharacterBody2D

const SPEED = 300.0

@onready var sprite = $AnimatedSprite2D

func _physics_process(delta: float) -> void:
	# 1. Standard top-down spaceship movement tracking
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	
	input_vector = input_vector.normalized()

	# 2. Apply movement velocity
	if input_vector != Vector2.ZERO:
		velocity = input_vector * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

	# 3. Flip left or right depending on movement direction
	if input_vector.x > 0:
		sprite.flip_h = false # Face right
	elif input_vector.x < 0:
		sprite.flip_h = true  # Face left (mirrors your idle frames)

	# 4. No conditions here—always play your default idle animation loop
	sprite.play("idle_right")

	# Move the character around the spaceship grid
	move_and_slide()
