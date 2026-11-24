extends RefCounted
## Load a converted scene, preserve its UV/material pairings and fit it to an authored parcel.

const DIRECTORY := "res://assets/premium_runtime/"

static func fit(asset: String, limit: Vector3, largest_part_only := false) -> ArrayMesh:
	var path := DIRECTORY + asset + ".glb"
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var model := (load(path) as PackedScene).instantiate()
	var parts: Array[Dictionary] = []
	_collect(model, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		model.free()
		return null
	if largest_part_only:
		parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.bounds.get_volume() > b.bounds.get_volume())
		parts.resize(1)
	var bounds: AABB = parts[0].bounds
	for part in parts:
		bounds = bounds.merge(part.bounds)
	var size := bounds.size.max(Vector3.ONE * 0.001)
	var scale_m := minf(limit.x / size.x, minf(limit.y / size.y, limit.z / size.z))
	var bottom := bounds.get_center()
	bottom.y = bounds.position.y
	var fit_frame := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_m), -bottom * scale_m)
	var surfaces := {}
	for part in parts:
		var mesh: Mesh = part.mesh
		for index in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(index) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mesh.surface_get_material(index)
			var key := Vector2i(0 if mat == null else mat.get_instance_id(), mesh.surface_get_format(index))
			if not surfaces.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				if mat is StandardMaterial3D:
					mat = mat.duplicate()
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if mat.albedo_texture != null and mat.albedo_texture.resource_path.ends_with("_alpha.png"):
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						mat.alpha_scissor_threshold = 0.39
						mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				surfaces[key] = {"tool": tool, "material": mat}
			var tool: SurfaceTool = surfaces[key].tool
			tool.append_from(mesh, index, fit_frame * (part.frame as Transform3D))
	var result := ArrayMesh.new()
	for entry: Dictionary in surfaces.values():
		var tool: SurfaceTool = entry.tool
		tool.set_material(entry.material)
		tool.index()
		tool.commit(result)
	model.free()
	return result if result.get_surface_count() > 0 else null

static func _collect(node: Node, frame: Transform3D, parts: Array[Dictionary]) -> void:
	if node is Node3D:
		frame *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		parts.append({"mesh": node.mesh, "frame": frame, "bounds": frame * node.mesh.get_aabb()})
	for child in node.get_children():
		_collect(child, frame, parts)
