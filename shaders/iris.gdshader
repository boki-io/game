shader_type canvas_item;
// A circular wipe (spec v0.9 section 4): everything farther than `radius` pixels from `center` is covered by `tint`, with a hard
// edge (no feathering) to suit the pixel art. The rect that carries it fills the layer, so UV * view_size is in screen pixels.

uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(320.0, 180.0);
uniform float radius = 2000.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 p = UV * view_size;
	COLOR = distance(p, center) > radius ? tint : vec4(0.0);
}
