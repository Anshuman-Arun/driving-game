extends RefCounted
## CPU-generated, chunked ArrayMeshes and ConcavePolygonShape3D static collision.
## Road geometry is reconstructed from paired directed travel lanes exactly once.
## Turning lanes contribute only to broad collidable junction pads, not road strips.

const SHOULDER_M := 1.35
const ROAD_LIFT_M := 0.075
const PAD_LIFT_M := 0.085
const OUTER_BURY_M := 0.08
const PAD_MARGIN_M := 3.0
const PAD_GRID_M := 2.0

var source = null
var make_colliders: bool = true
var full_world: bool = true
var focus: Vector2 = Vector2.ZERO
var radius_m: float = 460.0
var materials: Dictionary = {}
var stats: Dictionary = {}

func build(parent: Node3D, world: Variant, all_chunks: bool, focus_xz: Vector2,
		region_radius: float, terrain_chunk_cells: int, colliders: bool,
		overrides: Dictionary = {}) -> Dictionary:
	source = world
	full_world = all_chunks
	focus = focus_xz
	radius_m = maxf(region_radius, 50.0)
	make_colliders = colliders
	stats = {
		"terrain_chunks": 0, "terrain_vertices": 0, "terrain_triangles": 0,
		"physical_corridors": 0, "road_triangles": 0, "road_vertices": 0,
		"junction_pads": 0, "junction_triangles": 0, "junction_vertices": 0,
		"static_colliders": 0, "mesh_surface_count": 0,
		"turn_paths_covered": 0, "generation_ms": 0,
		"estimated_vertex_bytes": 0
	}
	_material_setup(overrides)
	var started := Time.get_ticks_msec()
	var terrain := Node3D.new()
	terrain.name = "TerrainChunks"
	parent.add_child(terrain)
	_build_terrain(terrain, clampi(terrain_chunk_cells, 8, 128))
	var roads_root := Node3D.new()
	roads_root.name = "PhysicalRoads"
	parent.add_child(roads_root)
	for road in source.roads:
		if _is_physical_corridor(road):
			_build_corridor(roads_root, road)
	var pads_root := Node3D.new()
	pads_root.name = "IntersectionPads"
	parent.add_child(pads_root)
	_build_junction_pads(pads_root)
	stats["generation_ms"] = Time.get_ticks_msec() - started
	stats["estimated_vertex_bytes"] = (int(stats["terrain_vertices"]) +
		int(stats["road_vertices"]) + int(stats["junction_vertices"])) * 32
	return stats.duplicate(true)

func _material_setup(overrides: Dictionary) -> void:
	for name in ["terrain", "asphalt", "gravel", "shoulder"]:
		if overrides.has(name) and overrides[name] is Material:
			materials[name] = overrides[name]
			continue
		var mat := StandardMaterial3D.new()
		mat.resource_name = "WorldRuntime/" + name
		mat.roughness = 0.92
		mat.metallic = 0.0
		match name:
			"terrain":
				mat.albedo_color = Color(0.32, 0.42, 0.27)
			"asphalt":
				mat.albedo_color = Color(0.21, 0.23, 0.25)
				mat.roughness = 0.79
			"gravel":
				mat.albedo_color = Color(0.49, 0.43, 0.34)
			"shoulder":
				mat.albedo_color = Color(0.36, 0.33, 0.28)
		materials[name] = mat

func _in_view(x: float, z: float, margin: float = 0.0) -> bool:
	return full_world or Vector2(x, z).distance_to(focus) <= radius_m + margin

func _rectangle_in_view(x0: float, z0: float, x1: float, z1: float) -> bool:
	if full_world:
		return true
	var px := clampf(focus.x, x0, x1)
	var pz := clampf(focus.y, z0, z1)
	return Vector2(px, pz).distance_to(focus) <= radius_m

func _new_arrays(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if not indices.is_empty():
		arr[Mesh.ARRAY_INDEX] = indices
	return arr

func _attach_mesh(parent: Node3D, label: String, mesh: ArrayMesh, material_count: int) -> void:
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	parent.add_child(instance)
	stats["mesh_surface_count"] += material_count
	if make_colliders:
		var body := StaticBody3D.new()
		body.name = label + "_Collision"
		parent.add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		if shape.shape is ConcavePolygonShape3D:
			shape.shape.backface_collision = true
		body.add_child(shape)
		stats["static_colliders"] += 1

func _terrain_normal(ix: int, iz: int) -> Vector3:
	var sx: float = source.height_index(ix - 1, iz) - source.height_index(ix + 1, iz)
	var sz: float = source.height_index(ix, iz - 1) - source.height_index(ix, iz + 1)
	return Vector3(sx, 2.0 * source.spacing_m, sz).normalized()

func _build_terrain(parent: Node3D, cell_count: int) -> void:
	for iz0 in range(0, source.grid_height - 1, cell_count):
		for ix0 in range(0, source.grid_width - 1, cell_count):
			var width: int = mini(cell_count, source.grid_width - 1 - ix0)
			var depth: int = mini(cell_count, source.grid_height - 1 - iz0)
			var x0: float = source.origin_x + ix0 * source.spacing_m
			var z0: float = source.origin_z + iz0 * source.spacing_m
			var x1: float = x0 + width * source.spacing_m
			var z1: float = z0 + depth * source.spacing_m
			if not _rectangle_in_view(x0, z0, x1, z1):
				continue
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var uv := PackedVector2Array()
			var ind := PackedInt32Array()
			for dz in range(depth + 1):
				for dx in range(width + 1):
					var gx: int = ix0 + dx
					var gz: int = iz0 + dz
					var x: float = source.origin_x + gx * source.spacing_m
					var z: float = source.origin_z + gz * source.spacing_m
					v.append(Vector3(x, source.height_index(gx, gz), z))
					n.append(_terrain_normal(gx, gz))
					uv.append(Vector2(x / 12.0, z / 12.0))
			var stride: int = width + 1
			for dz in range(depth):
				for dx in range(width):
					var a: int = dz * stride + dx
					var b: int = a + 1
					var c: int = a + stride
					var d: int = c + 1
					# Godot clockwise +Y-facing winding; split diagonal b--c.
					# Match sample_surface_height() interpolation exactly.
					ind.append_array(PackedInt32Array([a, b, c, b, d, c]))
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _new_arrays(v, n, uv, ind))
			mesh.surface_set_material(0, materials["terrain"])
			_attach_mesh(parent, "Terrain_%d_%d" % [ix0, iz0], mesh, 1)
			stats["terrain_chunks"] += 1
			stats["terrain_vertices"] += v.size()
			stats["terrain_triangles"] += ind.size() / 3

func _is_physical_corridor(road: Dictionary) -> bool:
	# World Agent encodes each physical road as matched AB/BA directed lanes.
	# Junction pseudo-roads hold turn lanes, which must never be duplicated as strips.
	var rid: String = road["id"]
	return source.lanes.has("lane_%s_ab" % rid) and source.lanes.has("lane_%s_ba" % rid)

func corridor_points(road: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	var rid: String = road["id"]
	var a: Array = source.lanes["lane_%s_ab" % rid]["points"]
	var b: Array = source.lanes["lane_%s_ba" % rid]["points"]
	if a.size() != b.size():
		push_error("[WorldMesh] AB/BA sample count differs for " + rid)
		return result
	for i in range(a.size()):
		var pa: Array = a[i]
		var pb: Array = b[b.size() - i - 1]
		var center := Vector3(
			(float(pa[0]) + float(pb[0])) * 0.5,
			(float(pa[1]) + float(pb[1])) * 0.5,
			(float(pa[2]) + float(pb[2])) * 0.5
		)
		result.append(center)
	return result

func _section(points: PackedVector3Array, i: int, half_width: float) -> Array[Vector3]:
	var previous: Vector3 = points[maxi(0, i - 1)]
	var following: Vector3 = points[mini(points.size() - 1, i + 1)]
	var longitudinal := (following - previous).normalized()
	var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
	var lateral := Vector2(-tangent.y, tangent.x)
	var offsets := [-half_width - SHOULDER_M, -half_width, 0.0, half_width, half_width + SHOULDER_M]
	var result: Array[Vector3] = []
	for off in offsets:
		var x: float = points[i].x + lateral.x * float(off)
		var z: float = points[i].z + lateral.y * float(off)
		var ground: float = source.sample_surface_height(x, z)
		var y: float
		if absf(float(off)) > half_width + 0.001:
			y = ground - OUTER_BURY_M
		else:
			y = maxf(points[i].y, ground) + ROAD_LIFT_M
		result.append(Vector3(x, y, z))
	return result

func _append_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		u0: float, u1: float, v0: float, v1: float) -> void:
	# a,b are left/right at first station, c,d at next station.
	var flat_normal := (b - a).cross(c - a).normalized()
	if flat_normal.y < 0.0:
		flat_normal = -flat_normal
	for index in [0, 2, 1, 1, 2, 3]:
		match index:
			0:
				verts.append(a)
				uvs.append(Vector2(u0, v0))
			1:
				verts.append(b)
				uvs.append(Vector2(u1, v0))
			2:
				verts.append(c)
				uvs.append(Vector2(u0, v1))
			3:
				verts.append(d)
				uvs.append(Vector2(u1, v1))
		normals.append(flat_normal)

func _build_corridor(parent: Node3D, road: Dictionary) -> void:
	var center: PackedVector3Array = corridor_points(road)
	if center.size() < 2:
		return
	var first: Dictionary = source.lanes["lane_%s_ab" % road["id"]]
	var half_width: float = float(first["width_m"]) # one lane each side
	var surface: String = first["surface"]
	var pavement_verts := PackedVector3Array()
	var pavement_norms := PackedVector3Array()
	var pavement_uv := PackedVector2Array()
	var shoulder_verts := PackedVector3Array()
	var shoulder_norms := PackedVector3Array()
	var shoulder_uv := PackedVector2Array()
	var cumulative := 0.0
	for i in range(center.size() - 1):
		var p: Vector3 = center[i]
		var q: Vector3 = center[i + 1]
		var length: float = Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))
		if not (_in_view(p.x, p.z, 10.0) or _in_view(q.x, q.z, 10.0)):
			cumulative += length
			continue
		var a: Array[Vector3] = _section(center, i, half_width)
		var b: Array[Vector3] = _section(center, i + 1, half_width)
		_append_quad(shoulder_verts, shoulder_norms, shoulder_uv,
			a[0], a[1], b[0], b[1], 0.0, SHOULDER_M / 4.0,
			cumulative / 4.0, (cumulative + length) / 4.0)
		_append_quad(pavement_verts, pavement_norms, pavement_uv,
			a[1], a[2], b[1], b[2], 0.0, half_width / 4.0,
			cumulative / 8.0, (cumulative + length) / 8.0)
		_append_quad(pavement_verts, pavement_norms, pavement_uv,
			a[2], a[3], b[2], b[3], half_width / 4.0, half_width * 2.0 / 4.0,
			cumulative / 8.0, (cumulative + length) / 8.0)
		_append_quad(shoulder_verts, shoulder_norms, shoulder_uv,
			a[3], a[4], b[3], b[4], 0.0, SHOULDER_M / 4.0,
			cumulative / 4.0, (cumulative + length) / 4.0)
		cumulative += length
	if pavement_verts.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_new_arrays(pavement_verts, pavement_norms, pavement_uv, PackedInt32Array()))
	mesh.surface_set_material(0, materials[surface])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_new_arrays(shoulder_verts, shoulder_norms, shoulder_uv, PackedInt32Array()))
	mesh.surface_set_material(1, materials["shoulder"])
	_attach_mesh(parent, "Road_" + road["id"], mesh, 2)
	stats["physical_corridors"] += 1
	stats["road_vertices"] += pavement_verts.size() + shoulder_verts.size()
	stats["road_triangles"] += (pavement_verts.size() + shoulder_verts.size()) / 3

func _cross(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)

func _convex_hull(raw: Array[Vector2]) -> Array[Vector2]:
	if raw.size() < 3:
		return raw
	var ordered: Array[Vector2] = raw.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if is_equal_approx(a.x, b.x):
			return a.y < b.y
		return a.x < b.x
	)
	var lower: Array[Vector2] = []
	for p in ordered:
		while lower.size() > 1 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	ordered.reverse()
	for p in ordered:
		while upper.size() > 1 and _cross(upper[-2], upper[-1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return lower

func _clip_convex_cell(cell: Array[Vector2], hull: Array[Vector2]) -> Array[Vector2]:
	var polygon: Array[Vector2] = cell.duplicate()
	for j in range(hull.size()):
		if polygon.is_empty():
			break
		var edge_a: Vector2 = hull[j]
		var edge_b: Vector2 = hull[(j + 1) % hull.size()]
		var clipped: Array[Vector2] = []
		var previous: Vector2 = polygon[-1]
		var previous_side: float = _cross(edge_a, edge_b, previous)
		for current in polygon:
			var current_side: float = _cross(edge_a, edge_b, current)
			if (previous_side >= -0.00001) != (current_side >= -0.00001):
				var denom: float = previous_side - current_side
				if absf(denom) > 0.000001:
					clipped.append(previous.lerp(current, previous_side / denom))
			if current_side >= -0.00001:
				clipped.append(current)
			previous = current
			previous_side = current_side
		polygon = clipped
	return polygon

func _pad_points_for_turn(lane: Dictionary) -> Array[Vector2]:
	var points: Array = lane["points"]
	var result: Array[Vector2] = []
	var reach: float = float(lane["width_m"]) * 0.5 + PAD_MARGIN_M
	for i in range(points.size()):
		var p: Array = points[i]
		var before: Array = points[maxi(i - 1, 0)]
		var after: Array = points[mini(i + 1, points.size() - 1)]
		var dir := Vector2(float(after[0]) - float(before[0]),
			float(after[2]) - float(before[2])).normalized()
		var normal := Vector2(-dir.y, dir.x) * reach
		var center := Vector2(float(p[0]), float(p[2]))
		result.append(center + normal)
		result.append(center - normal)
		# Cardinal buffers ensure coverage even at the extreme of a tight turn.
		result.append(center + Vector2(reach, 0.0))
		result.append(center - Vector2(reach, 0.0))
		result.append(center + Vector2(0.0, reach))
		result.append(center - Vector2(0.0, reach))
	return result

func _pad_vert(p: Vector2) -> Vector3:
	return Vector3(p.x, source.sample_surface_height(p.x, p.y) + PAD_LIFT_M, p.y)

func _build_junction_pads(parent: Node3D) -> void:
	var group_points: Dictionary = {}
	var group_surfaces: Dictionary = {}
	var turn_counts: Dictionary = {}
	for lid in source.lanes:
		var lane: Dictionary = source.lanes[lid]
		if not String(lid).begins_with("turn_"):
			continue
		var parts := String(lid).split("_")
		if parts.size() < 3:
			continue
		var junction: String = parts[1]
		if not group_points.has(junction):
			var fresh_points: Array[Vector2] = []
			group_points[junction] = fresh_points
			group_surfaces[junction] = "gravel"
			turn_counts[junction] = 0
		if lane["surface"] == "asphalt":
			group_surfaces[junction] = "asphalt"
		var buffered: Array[Vector2] = _pad_points_for_turn(lane)
		for point in buffered:
			group_points[junction].append(point)
		turn_counts[junction] += 1
	for junction in group_points:
		var hull: Array[Vector2] = _convex_hull(group_points[junction])
		if hull.size() < 3:
			continue
		var min_x := INF
		var min_z := INF
		var max_x := -INF
		var max_z := -INF
		for p in hull:
			min_x = minf(min_x, p.x)
			min_z = minf(min_z, p.y)
			max_x = maxf(max_x, p.x)
			max_z = maxf(max_z, p.y)
		if not _rectangle_in_view(min_x, min_z, max_x, max_z):
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var ix0 := int(floor(min_x / PAD_GRID_M))
		var ix1 := int(ceil(max_x / PAD_GRID_M))
		var iz0 := int(floor(min_z / PAD_GRID_M))
		var iz1 := int(ceil(max_z / PAD_GRID_M))
		for iz in range(iz0, iz1):
			for ix in range(ix0, ix1):
				var x: float = ix * PAD_GRID_M
				var z: float = iz * PAD_GRID_M
				var cell: Array[Vector2] = [
					Vector2(x, z), Vector2(x + PAD_GRID_M, z),
					Vector2(x + PAD_GRID_M, z + PAD_GRID_M),
					Vector2(x, z + PAD_GRID_M)
				]
				var clipped: Array[Vector2] = _clip_convex_cell(cell, hull)
				if clipped.size() < 3:
					continue
				for k in range(1, clipped.size() - 1):
					var first := _pad_vert(clipped[0])
					var second := _pad_vert(clipped[k])
					var third := _pad_vert(clipped[k + 1])
					if (second - first).cross(third - first).length_squared() < 0.00000001:
						continue
					for v in [first, second, third]:
						vertices.append(v)
						normals.append(_pad_normal(v.x, v.z))
						uvs.append(Vector2(v.x / 8.0, v.z / 8.0))
		if vertices.is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _new_arrays(vertices, normals, uvs, PackedInt32Array()))
		mesh.surface_set_material(0, materials[group_surfaces[junction]])
		_attach_mesh(parent, "Junction_" + junction, mesh, 1)
		stats["junction_pads"] += 1
		stats["turn_paths_covered"] += int(turn_counts[junction])
		stats["junction_vertices"] += vertices.size()
		stats["junction_triangles"] += vertices.size() / 3

func _pad_normal(x: float, z: float) -> Vector3:
	var step := 1.0
	return Vector3(
		source.sample_surface_height(x - step, z) - source.sample_surface_height(x + step, z),
		2.0 * step,
		source.sample_surface_height(x, z - step) - source.sample_surface_height(x, z + step)
	).normalized()
