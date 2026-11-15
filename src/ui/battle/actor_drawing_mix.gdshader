shader_type canvas_item;
render_mode unshaded;

// Registered part canvases share the same bone weights. Premultiplied RGB
// keeps transparent gutters from introducing colored fringes while blending.
uniform sampler2D drawing_a : source_color, filter_linear_mipmap;
uniform sampler2D drawing_b : source_color, filter_linear_mipmap;
uniform sampler2D drawing_c : source_color, filter_linear_mipmap;
uniform vec4 drawing_weights = vec4(1.0, 0.0, 0.0, 0.0);
varying vec4 part_modulate;

void vertex() {
	part_modulate = COLOR;
}

vec4 premultiplied(vec4 c) {
	return vec4(c.rgb * c.a, c.a);
}

void fragment() {
	vec4 mixed = premultiplied(texture(TEXTURE, UV)) * drawing_weights.x
		+ premultiplied(texture(drawing_a, UV)) * drawing_weights.y
		+ premultiplied(texture(drawing_b, UV)) * drawing_weights.z
		+ premultiplied(texture(drawing_c, UV)) * drawing_weights.w;
	COLOR = vec4(mixed.rgb / max(mixed.a, 0.00001), mixed.a) * part_modulate;
}
