shader_type canvas_item;
// Electric pulses travelling along a Line2D (texture_mode = TILE, so UV.x grows with length).

uniform vec4 base_color : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform vec4 pulse_color : source_color = vec4(1.0, 1.0, 0.85, 1.0);
uniform float line_width = 3.0;     // Line2D width, converts UV.x back into pixels
uniform float spacing_px = 18.0;    // distance between pulses
uniform float speed = 3.0;          // pulses per second passing a point
uniform float pulse_len = 0.35;     // fraction of the spacing that is lit
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float d = UV.x * line_width / spacing_px;
	float p = fract(d - TIME * speed);
	float pulse = (1.0 - smoothstep(0.0, pulse_len, p)) * intensity;
	vec3 col = mix(base_color.rgb, pulse_color.rgb, pulse);
	float f = 1.0 - flicker * 0.65 * step(0.5, hash(floor(TIME * 24.0)));
	COLOR = vec4(col * f, base_color.a);
}
