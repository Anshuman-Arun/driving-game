extends SceneTree
## Run after root editor import. No rendering or world integration required.
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
	var assets: Array = manifest.get("assets", [])
	_check(assets.size() == 5, "Expected five species")
	var loaded: int = 0
	for entry: Dictionary in assets:
		var dimensions: Array = entry["dimensions_m"]
		var expected := Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]))
		for lod: int in range(2):
			var path: String = entry["lod%d" % lod]
			_check(FileAccess.get_sha256(path) == entry["sha256_by_path"][path], "Source hash mismatch: " + path)
			var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
			if packed == null:
				_check(false, "Cannot load imported scene: " + path)
				continue
			var instance := packed.instantiate()
			var parts: Array[Dictionary] = []
			_collect(instance, Transform3D.IDENTITY, parts)
			if parts.is_empty():
				_check(false, "No mesh: " + path)
				instance.free()
				continue
			var bounds: AABB = parts[0]["bounds"]
			var triangles: int = 0
			var surfaces: int = 0
			for part: Dictionary in parts:
				bounds = bounds.merge(part["bounds"])
				var mesh: Mesh = part["mesh"]
				for surface: int in range(mesh.get_surface_count()):
					surfaces += 1
					_check(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "Non-triangular surface: " + path)
					var arrays: Array = mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					var indices: PackedInt32Array = PackedInt32Array()
					if arrays[Mesh.ARRAY_INDEX] != null:
						indices = arrays[Mesh.ARRAY_INDEX]
					var count: int = indices.size() if not indices.is_empty() else vertices.size()
					triangles += int(count / 3.0)
					_check(count % 3 == 0 and normals.size() == vertices.size() and colors.size() == vertices.size() and uv.size() == vertices.size(), "Attribute loss: " + path)
					for vertex: Vector3 in vertices:
						_check(vertex.is_finite(), "Nonfinite imported vertex: " + path)
					for normal: Vector3 in normals:
						_check(normal.is_finite() and absf(normal.length() - 1.0) < 0.02, "Invalid imported normal: " + path)
					var material := mesh.surface_get_material(surface) as StandardMaterial3D
					_check(material != null, "Missing PBR material: " + path)
					if material != null:
						_check(material.vertex_color_use_as_albedo and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.cull_mode == BaseMaterial3D.CULL_DISABLED, "Material import mismatch: " + path)
						_check(material.albedo_texture == null, "Unexpected texture: " + path)
			var budget: Dictionary = entry["budget_by_path"][path]
			_check(triangles == int(budget["triangles"]) and surfaces == int(budget["surfaces"]), "Geometry budget mismatch: " + path)
			_check(bounds.size.is_equal_approx(expected), "Imported bounds mismatch: " + path)
			_check(absf(bounds.position.y) < 0.001 and absf(bounds.get_center().x) < 0.001 and absf(bounds.get_center().z) < 0.001, "Ground origin mismatch: " + path)
			loaded += 1
			instance.free()
	_check(loaded == 10, "Expected ten imported LODs")
	print("Vegetation import: ", loaded, "/10 scenes; failures=", failures)
	quit(0 if failures == 0 else 1)
