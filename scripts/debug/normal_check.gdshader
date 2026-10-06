shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	vec3 n = NORMAL;
	if (!FRONT_FACING) {
		n = -n;
	}
	ALBEDO = n.z > 0.0 ? vec3(0.0, 0.9, 0.2) : vec3(1.0, 0.1, 0.1);
}