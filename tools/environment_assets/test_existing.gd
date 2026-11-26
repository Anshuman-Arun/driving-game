extends SceneTree
## Optional scan audit. Run only after audit_existing.py passes and Godot imports real LFS bytes.
const PremiumMesh = preload("res://scripts/integration/premium_mesh.gd")
const BASE := "res://assets/premium_runtime/"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_audit("fern", "fern_fern_02_diff-fern_02_alpha.png", Vector3(1.05, 0.44, 1.05))
	_audit("fir", "fir_fir_sapling_medium_twigs_diff-fir_sapling_medium_twigs_alpha.png", Vector3(0.95, 1.65, 0.95))
	print("Premium foliage audit failures=", failures)
	quit(0 if failures == 0 else 1)

func _audit(species: String, alpha_path: String, limit: Vector3) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(BASE + alpha_path))
	if image == null or image.is_empty():
		_check(false, "Missing UV-matched opacity image: " + species)
		return
	var below: int = 0
	var above: int = 0
	var partial: int = 0
	var lowest: float = 1.0
	var highest: float = 0.0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var alpha: float = image.get_pixel(x, y).a
			lowest = minf(lowest, alpha)
			highest = maxf(highest, alpha)
			if alpha < 0.39:
				below += 1
			else:
				above += 1
			if alpha > 0.0 and alpha < 1.0:
				partial += 1
	_check(below > 0 and above > 0, "Opacity does not produce a cutout: " + species)
	print(species, " alpha image ", image.get_size(), " below/above scissor: ", below, "/", above, " partial: ", partial, " range ", lowest, "..", highest)
	var mesh := PremiumMesh.fit(species, limit)
	if mesh == null:
		_check(false, "Existing scan is not loadable: " + species)
		return
	var bounds := mesh.get_aabb()
	_check(absf(bounds.position.y) < 0.001 and absf(bounds.get_center().x) < 0.001 and absf(bounds.get_center().z) < 0.001, "Scan origin not ground-centered: " + species)
	_check(bounds.size.x <= limit.x + 0.001 and bounds.size.y <= limit.y + 0.001 and bounds.size.z <= limit.z + 0.001, "Scan exceeds requested dimensions: " + species)
	var alpha_surfaces: int = 0
	var triangles: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
			_check(false, "Missing scan attributes: " + species)
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		triangles += int(count / 3.0)
		_check(count > 0 and count % 3 == 0 and normals.size() == vertices.size() and uvs.size() == vertices.size(), "Invalid scan geometry attributes: " + species)
		for normal: Vector3 in normals:
			_check(normal.is_finite() and absf(normal.length() - 1.0) < 0.02, "Scan normal is invalid: " + species)
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			_check(false, "Missing scan material: " + species)
			continue
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			alpha_surfaces += 1
			_check(material.albedo_texture != null and material.cull_mode == BaseMaterial3D.CULL_DISABLED and absf(material.alpha_scissor_threshold - 0.39) < 0.01, "Bad cutout material: " + species)
			if material.albedo_texture != null:
				_audit_bound_alpha(material.albedo_texture, float(above) / float(above + below), species)
		if material.normal_enabled:
			var tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
			if material.normal_texture == null or not tangents is PackedFloat32Array or tangents.size() != vertices.size() * 4:
				_check(false, "Normal-mapped surface lacks tangents: " + species)
			else:
				for i: int in range(vertices.size()):
					var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
					_check(tangent.is_finite() and absf(tangent.length() - 1.0) < 0.05 and absf(absf(tangents[i * 4 + 3]) - 1.0) < 0.05, "Invalid tangent: " + species)
					if i < normals.size():
						_check(absf(tangent.dot(normals[i])) < 0.1, "Tangent is not orthogonal to normal: %s surface=%d vertex=%d dot=%f normal=%s tangent=%s" % [species, surface, i, tangent.dot(normals[i]), str(normals[i]), str(tangent)])
	_check(alpha_surfaces > 0, "No runtime alpha-scissor surface: " + species)
	print(species, " fitted bounds ", bounds, ", triangles=", triangles, ", surfaces=", mesh.get_surface_count(), ", scissor surfaces=", alpha_surfaces)

func _audit_bound_alpha(texture: Texture2D, reference_coverage: float, species: String) -> void:
	var image := texture.get_image()
	if image == null or image.is_empty():
		_check(false, "Bound scan texture has no readable image: " + species)
		return
	if image.is_compressed() and image.decompress() != OK:
		_check(false, "Cannot decompress bound scan alpha: " + species)
		return
	var total: int = image.get_width() * image.get_height()
	var opaque: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.39:
				opaque += 1
	var coverage: float = float(opaque) / float(total)
	_check(opaque > 0 and opaque < total, "Bound scan texture is not a cutout: " + species)
	# Compression may move pixels around the threshold; this is a coverage
	# sanity check, not a claim of exact pixel identity or visual alignment.
	_check(absf(coverage - reference_coverage) < 0.08, "Bound alpha coverage differs from UV-matched source: " + species)
	print(species, " bound alpha coverage=", coverage, " source=", reference_coverage, " mipmaps=", image.has_mipmaps())
