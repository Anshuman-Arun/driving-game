extends SceneTree
## Run after root editor import. No rendering or world integration required.
const MaterialAdapter := preload("res://assets/environment_overhaul/prepare_material.gd")
const MANIFEST := "res://assets/environment_overhaul/manifest.json"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _collect(node: Node, frame: Transform3D, result: Array[Dictionary]) -> void:
	if node is Node3D:
		frame *= (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			result.append({"mesh": instance.mesh, "bounds": frame * instance.mesh.get_aabb()})
	for child in node.get_children():
		_collect(child, frame, result)

func _run() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or manifest.get("schema_version") != 1:
		_check(false, "Invalid vegetation manifest")
		quit(1)
		return
	if not manifest.get("assets") is Array:
		_check(false, "Missing assets array")
		quit(1)
		return
	var assets: Array = manifest["assets"]
	var seen: Dictionary = {}
	_check(assets.size() == 5, "Expected five species")
	var loaded: int = 0
	for raw_entry: Variant in assets:
		if not raw_entry is Dictionary:
			_check(false, "Invalid manifest entry")
			continue
		var entry: Dictionary = raw_entry
		var species: String = str(entry.get("species_id", ""))
		if species not in ["shrub", "fern", "sapling", "reed", "wildflower"] or seen.has(species):
			_check(false, "Unknown or duplicate species: " + species)
			continue
		seen[species] = true
		if not entry.get("dimensions_m") is Array or entry["dimensions_m"].size() != 3 or not entry.get("sha256_by_path") is Dictionary or not entry.get("budget_by_path") is Dictionary:
			_check(false, "Malformed asset metadata: " + species)
			continue
		var dimensions: Array = entry["dimensions_m"]
		var expected := Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]))
		if not expected.is_finite() or expected.x <= 0.0 or expected.y <= 0.0 or expected.z <= 0.0:
			_check(false, "Invalid dimensions: " + species)
			continue
		var near_triangles: int = 0
		for lod: int in range(2):
			var path: String = str(entry.get("lod%d" % lod, ""))
			if path != "res://assets/environment_overhaul/%s_lod%d.gltf" % [species, lod] or not entry["sha256_by_path"].has(path) or not entry["budget_by_path"].has(path):
				_check(false, "Invalid resource path or metadata: " + path)
				continue
			if FileAccess.get_sha256(path) != entry["sha256_by_path"][path]:
				_check(false, "Source hash mismatch: " + path)
				continue
			_check(MaterialAdapter.source_valid(path), "Source material declaration mismatch: " + path)
			var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
			if packed == null:
				_check(false, "Cannot load imported scene: " + path)
				continue
			var instance := packed.instantiate()
			var parts: Array[Dictionary] = []
			_collect(instance, Transform3D.IDENTITY, parts)
			if parts.size() != 1:
				_check(false, "Expected one imported mesh: " + path)
				instance.free()
				continue
			var bounds: AABB = parts[0]["bounds"]
			var triangles: int = 0
			var surfaces: int = 0
			for part: Dictionary in parts:
				bounds = bounds.merge(part["bounds"])
				var raw: Mesh = part["mesh"]
				var mesh := MaterialAdapter.prepare(raw)
				_check(mesh != null and mesh != raw, "Production material preparation: " + path)
				if mesh == null:
					continue
				for raw_surface in raw.get_surface_count():
					var raw_material := raw.surface_get_material(raw_surface) as StandardMaterial3D
					if raw_material != null:
						print("Raw import flags ", path, ": vertex_color=", raw_material.vertex_color_use_as_albedo, ", transparency=", raw_material.transparency, ", cull=", raw_material.cull_mode)
						_check(raw_material != mesh.surface_get_material(raw_surface), "Material must be copied: " + path)
				for surface: int in range(mesh.get_surface_count()):
					surfaces += 1
					_check(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "Non-triangular surface: " + path)
					var arrays: Array = mesh.surface_get_arrays(surface)
					if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
						_check(false, "Missing imported attribute arrays: " + path)
						continue
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					var indices: PackedInt32Array = PackedInt32Array()
					if arrays[Mesh.ARRAY_INDEX] != null:
						indices = arrays[Mesh.ARRAY_INDEX]
					var count: int = indices.size() if not indices.is_empty() else vertices.size()
					triangles += int(count / 3.0)
					if count == 0 or count % 3 != 0 or normals.size() != vertices.size() or colors.size() != vertices.size() or uv.size() != vertices.size():
						_check(false, "Attribute loss: " + path)
						continue
					for vertex: Vector3 in vertices:
						_check(vertex.is_finite(), "Nonfinite imported vertex: " + path)
					for normal: Vector3 in normals:
						_check(normal.is_finite() and absf(normal.length() - 1.0) < 0.02, "Invalid imported normal: " + path)
					for vertex_index: int in range(vertices.size()):
						var color: Color = colors[vertex_index]
						_check(is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and absf(color.a - 1.0) < 0.01 and color.r >= 0.0 and color.g >= 0.0 and color.b >= 0.0 and color.r <= 1.0 and color.g <= 1.0 and color.b <= 1.0, "Invalid vertex color: " + path)
						_check(uv[vertex_index].is_finite() and uv[vertex_index].x >= -0.001 and uv[vertex_index].x <= 1.001 and uv[vertex_index].y >= -0.001 and uv[vertex_index].y <= 1.001, "Invalid imported UV: " + path)
					for i: int in range(0, count, 3):
						var a: int = i if indices.is_empty() else indices[i]
						var b: int = i + 1 if indices.is_empty() else indices[i + 1]
						var c: int = i + 2 if indices.is_empty() else indices[i + 2]
						if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
							_check(false, "Imported index outside vertex range: " + path)
							continue
						_check((vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() > 1e-10, "Degenerate imported triangle: " + path)
					var material := mesh.surface_get_material(surface) as StandardMaterial3D
					_check(material != null, "Missing PBR material: " + path)
					if material != null:
						_check(material.vertex_color_use_as_albedo and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.cull_mode == BaseMaterial3D.CULL_DISABLED, "Material import mismatch: " + path)
						_check(material.albedo_texture == null and not material.normal_enabled, "Unexpected texture: " + path)
						_check(absf(material.roughness - 0.88) < 0.01 and absf(material.metallic) < 0.01 and material.albedo_color.is_equal_approx(Color.WHITE), "Unexpected material factors: " + path)
			var budget: Dictionary = entry["budget_by_path"][path]
			_check(triangles == int(budget["triangles"]) and surfaces == int(budget["surfaces"]), "Geometry budget mismatch: " + path)
			_check((bounds.size - expected).abs().length() < 0.002, "Imported bounds mismatch: " + path)
			if lod == 0:
				near_triangles = triangles
			else:
				_check(near_triangles > 0 and float(triangles) <= float(near_triangles) * 0.65, "Imported LOD reduction mismatch: " + path)
			_check(absf(bounds.position.y) < 0.001 and absf(bounds.get_center().x) < 0.001 and absf(bounds.get_center().z) < 0.001, "Ground origin mismatch: " + path)
			loaded += 1
			instance.free()
	_check(loaded == 10, "Expected ten imported LODs")
	print("Vegetation import: ", loaded, "/10 scenes; failures=", failures)
	quit(0 if failures == 0 else 1)
