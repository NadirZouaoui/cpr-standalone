shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Reproduces Blender's Texture Coordinate > Generated -> Separate XYZ -> Map
// Range -> Alpha chain, which is procedural and therefore cannot cross glTF.
//
// Generated coordinates are the vertex position normalised over the mesh
// bounding box, so fade_t below is the same 0..1 value Blender feeds into
// Map Range. The axis, extent and range are supplied by
// scripts/import/alpha_fade_materials.gd, which reads them off the object's
// godot_alpha_fade custom property and the imported mesh AABB.

uniform vec4 albedo : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Local-space axis the gradient runs along, plus where the bounding box
// starts and how far it extends along it.
uniform vec3 grad_axis = vec3(0.0, 1.0, 0.0);
uniform float grad_min = 0.0;
uniform float grad_extent = 1.0;

// Map Range's From Min / From Max. To Min / To Max are 0 and 1.
uniform float from_min = 0.0;
uniform float from_max = 1.0;

varying float fade_t;

void vertex() {
	fade_t = (dot(VERTEX, grad_axis) - grad_min) / max(grad_extent, 0.000001);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = clamp((fade_t - from_min) / max(from_max - from_min, 0.000001), 0.0, 1.0);
}
