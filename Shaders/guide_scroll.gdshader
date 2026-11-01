shader_type canvas_item;
// Makes the floor-guide chevrons slide along the Line2D, like a moving walkway.
// UV.x grows by 1 for every repeat of the texture along the line (TILE mode),
// so subtracting TIME shifts the picture forward over time.

uniform float speed = 1.5;   // chevrons per second

void fragment() {
	vec2 uv = vec2(fract(UV.x - TIME * speed), UV.y);
	COLOR = texture(TEXTURE, uv) * COLOR;
}
