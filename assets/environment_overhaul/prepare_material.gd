extends RefCounted
## Normalize only the verified, original opaque vertex-colored B assets.
## Godot's imported flags differ from the glTF declaration; never mutate cached meshes.
static func source_valid(path: String) -> bool:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary or not doc.get("materials") is Array or not doc.get("meshes") is Array:
		return false
	if doc.materials.size() != 1 or doc.meshes.size() != 1:
		return false
	var material: Dictionary = doc.materials[0]
	if material.get("doubleSided") != true or material.get("alphaMode", "OPAQUE") != "OPAQUE":
		return false
	for primitive: Dictionary in doc.meshes[0].get("primitives", []):
		if not primitive.get("attributes", {}).has("COLOR_0") or primitive.get("material") != 0:
			return false
	return not doc.meshes[0].get("primitives", []).is_empty()

static func prepare(mesh: Mesh) -> ArrayMesh:
	if not mesh is ArrayMesh or mesh.get_surface_count() == 0:
		return null
	var prepared := mesh.duplicate() as ArrayMesh
	if prepared == null:
		return null
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null or material.albedo_texture != null or material.normal_enabled:
			return null
		if not (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR):
			return null
		if absf(material.roughness - 0.88) >= 0.01 or absf(material.metallic) >= 0.01 or not material.albedo_color.is_equal_approx(Color.WHITE):
			return null
		var copy := material.duplicate() as StandardMaterial3D
		copy.vertex_color_use_as_albedo = true
		copy.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		copy.cull_mode = BaseMaterial3D.CULL_DISABLED
		prepared.surface_set_material(surface, copy)
	return prepared
