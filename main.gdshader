shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 n = NORMAL;
	if (!FRONT_FACING) n = -n;
	ALBEDO = n * 0.5 + 0.5;
}