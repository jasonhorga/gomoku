shader_type canvas_item;

uniform vec3 color_light : source_color = vec3(0.76, 0.60, 0.42);
uniform vec3 color_dark : source_color = vec3(0.55, 0.38, 0.22);
uniform float grain_scale : hint_range(1.0, 50.0) = 20.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV * grain_scale;
	float n = noise(uv * 0.5) * noise_strength;
	float grain = sin(uv.y * 6.0 + n * 10.0) * 0.5 + 0.5;
	grain = smoothstep(0.3, 0.7, grain);
	vec3 col = mix(color_light, color_dark, grain * 0.4);
	col += (noise(uv * 2.0) - 0.5) * 0.05;
	COLOR = vec4(col, 1.0);
}
