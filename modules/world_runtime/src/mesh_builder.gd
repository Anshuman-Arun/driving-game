extends RefCounted
## CPU-generated, chunked ArrayMeshes and ConcavePolygonShape3D static collision.
## Road geometry is reconstructed from paired directed travel lanes exactly once.
## Turning lanes contribute only to broad collidable junction pads, not road strips.

const RoadworksArt = preload("roadworks_art.gd")
const RoadClearance = preload("road_clearance.gd")

const SHOULDER_M := 1.35
const ROAD_LIFT_M := 0.075
const PAD_LIFT_M := 0.10
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
var roadworks: Dictionary = {}
var network: Dictionary = {}
var clearance: RoadClearance

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
		"static_colliders": 0, "shoulder_colliders": 0, "mesh_surface_count": 0,
		"turn_paths_covered": 0, "generation_ms": 0,
		"estimated_vertex_bytes": 0
	}
	roadworks = overrides.get("roadworks", {})
	network = roadworks.get("network_upgrade", {})
	clearance = RoadClearance.new() if not network.is_empty() else null
	_material_setup(overrides, parent)
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
	if not roadworks.is_empty():
		RoadworksArt.build_water(roads_root, roadworks.get("waters", []), overrides.get("crossing_water"))
	stats["generation_ms"] = Time.get_ticks_msec() - started
	stats["estimated_vertex_bytes"] = (int(stats["terrain_vertices"]) +
		int(stats["road_vertices"]) + int(stats["junction_vertices"])) * 32
	return stats.duplicate(true)

func _material_setup(overrides: Dictionary, parent: Node3D = null) -> void:
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
	if overrides.has("junction_asphalt") and overrides["junction_asphalt"] is Material:
		materials["junction_asphalt"] = overrides["junction_asphalt"]
	elif parent != null and parent.get_parent() != null and parent.get_parent().has_meta("junction_asphalt_material_override"):
		var meta_mat: Variant = parent.get_parent().get_meta("junction_asphalt_material_override")
		materials["junction_asphalt"] = meta_mat if meta_mat is Material else materials["asphalt"]
	else:
		materials["junction_asphalt"] = materials["asphalt"]

func _in_view(x: float, z: float, margin: float = 0.0) -> bool:
	return full_world or Vector2(x, z).distance_to(focus) <= radius_m + margin

func _rectangle_in_view(x0: float, z0: float, x1: float, z1: float) -> bool:
	if full_world:
		return true
	var px := clampf(focus.x, x0, x1)
	var pz := clampf(focus.y, z0, z1)
	return Vector2(px, pz).distance_to(focus) <= radius_m

func _new_arrays(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		tangents: PackedFloat32Array = PackedFloat32Array()) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if not tangents.is_empty():
		arr[Mesh.ARRAY_TANGENT] = tangents
	if not indices.is_empty():
		arr[Mesh.ARRAY_INDEX] = indices
	return arr

func _compute_triangle_tangents(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array) -> PackedFloat32Array:
	var count := verts.size()
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
	var i := 0
	while i + 2 < count:
		var p0: Vector3 = verts[i]
		var p1: Vector3 = verts[i + 1]
		var p2: Vector3 = verts[i + 2]
		var uv0: Vector2 = uvs[i]
		var uv1: Vector2 = uvs[i + 1]
		var uv2: Vector2 = uvs[i + 2]
		var e1: Vector3 = p1 - p0
		var e2: Vector3 = p2 - p0
		var du1: float = uv1.x - uv0.x
		var dv1: float = uv1.y - uv0.y
		var du2: float = uv2.x - uv0.x
		var dv2: float = uv2.y - uv0.y
		var denom: float = du1 * dv2 - du2 * dv1
		var t_raw := Vector3.RIGHT
		var b_raw := Vector3.BACK
		if absf(denom) > 0.0000001:
			var inv_d: float = 1.0 / denom
			t_raw = (e1 * dv2 - e2 * dv1) * inv_d
			b_raw = (e2 * du1 - e1 * du2) * inv_d
		for k in range(3):
			var n: Vector3 = norms[i + k]
			var t: Vector3 = t_raw - n * n.dot(t_raw)
			if t.length_squared() < 0.000001:
				t = Vector3.RIGHT - n * n.x
				if t.length_squared() < 0.000001:
					t = Vector3.FORWARD
			t = t.normalized()
			var w: float = -1.0 if n.cross(t).dot(b_raw) < 0.0 else 1.0
			var off: int = (i + k) * 4
			tangents[off] = t.x
			tangents[off + 1] = t.y
			tangents[off + 2] = t.z
			tangents[off + 3] = w
		i += 3
	return tangents

func _attach_mesh(parent: Node3D, label: String, mesh: ArrayMesh, material_count: int,
		surface: String) -> void:
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	parent.add_child(instance)
	stats["mesh_surface_count"] += material_count
	if not make_colliders:
		return
	if mesh.get_surface_count() == 1:
		_attach_collider(parent, label + "_Collision", mesh.create_trimesh_shape(), surface)
		return

	# The road/pad mesh has two unindexed surfaces. Give each triangle to exactly
	# one collider so each wheel ray gets the correct grip at the shoulder.
	_attach_collider(parent, label + "_Collision", _surface_shape(mesh, 0), surface)
	_attach_collider(parent, label + "_Shoulder_Collision", _surface_shape(mesh, 1), "shoulder")
	stats["shoulder_colliders"] += 1

func _surface_shape(mesh: ArrayMesh, surface_index: int) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	var arrays := mesh.surface_get_arrays(surface_index)
	shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
	return shape

func _attach_collider(parent: Node3D, label: String, geometry: ConcavePolygonShape3D, surface: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("world_surface", surface)
	var group := "Dirt"
	if surface == "terrain":
		group = "Grass"
	elif surface == "asphalt":
		group = "Road"
	body.add_to_group(group)
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	geometry.backface_collision = true
	collider.shape = geometry
	body.add_child(collider)
	stats["static_colliders"] += 1

func _terrain_normal(ix: int, iz: int) -> Vector3:
	var sx: float = source.height_index(ix - 1, iz) - source.height_index(ix + 1, iz)
	var sz: float = source.height_index(ix, iz - 1) - source.height_index(ix, iz + 1)
	return Vector3(sx, 2.0 * source.spacing_m, sz).normalized()

func _build_terrain(parent: Node3D, cell_count: int) -> void:
	var gw: int = source.grid_width
	var gh: int = source.grid_height
	var gw_max: int = gw - 1
	var gh_max: int = gh - 1
	var spacing: float = source.spacing_m
	var inv_uv: float = 1.0 / 12.0
	var two_spacing: float = 2.0 * spacing
	var ox: float = source.origin_x
	var oz: float = source.origin_z
	var samples: PackedFloat32Array = source.height_samples
	for iz0 in range(0, gh_max, cell_count):
		for ix0 in range(0, gw_max, cell_count):
			var width: int = mini(cell_count, gw_max - ix0)
			var depth: int = mini(cell_count, gh_max - iz0)
			var x0: float = ox + ix0 * spacing
			var z0: float = oz + iz0 * spacing
			var x1: float = x0 + width * spacing
			var z1: float = z0 + depth * spacing
			if not _rectangle_in_view(x0, z0, x1, z1):
				continue
			var stride: int = width + 1
			var vert_count: int = stride * (depth + 1)
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var uv := PackedVector2Array()
			var tang := PackedFloat32Array()
			var ind := PackedInt32Array()
			v.resize(vert_count)
			n.resize(vert_count)
			uv.resize(vert_count)
			tang.resize(vert_count * 4)
			ind.resize(depth * width * 6)
			var vi := 0
			for dz in range(depth + 1):
				var gz: int = iz0 + dz
				var z: float = oz + gz * spacing
				var row_off: int = gz * gw
				var row_up: int = (gz - 1 if gz > 0 else 0) * gw
				var row_dn: int = (gz + 1 if gz < gh_max else gh_max) * gw
				var uv_y: float = z * inv_uv
				for dx in range(width + 1):
					var gx: int = ix0 + dx
					var x: float = ox + gx * spacing
					var xl: int = gx - 1 if gx > 0 else 0
					var xr: int = gx + 1 if gx < gw_max else gw_max
					var sx: float = samples[row_off + xl] - samples[row_off + xr]
					var sz: float = samples[row_up + gx] - samples[row_dn + gx]
					var nv := Vector3(sx, two_spacing, sz).normalized()
					var tv := Vector3(1.0 - nv.x * nv.x, -nv.y * nv.x, -nv.z * nv.x).normalized()
					v[vi] = Vector3(x, samples[row_off + gx], z)
					n[vi] = nv
					uv[vi] = Vector2(x * inv_uv, uv_y)
					var toff: int = vi * 4
					tang[toff] = tv.x
					tang[toff + 1] = tv.y
					tang[toff + 2] = tv.z
					tang[toff + 3] = -1.0
					vi += 1
			var ii := 0
			for dz in range(depth):
				var row_a: int = dz * stride
				var row_c: int = row_a + stride
				for dx in range(width):
					var a: int = row_a + dx
					var b: int = a + 1
					var c: int = row_c + dx
					var d: int = c + 1
					# Godot clockwise +Y-facing winding; split diagonal b--c.
					# Match sample_surface_height() interpolation exactly.
					ind[ii] = a
					ind[ii + 1] = b
					ind[ii + 2] = c
					ind[ii + 3] = b
					ind[ii + 4] = d
					ind[ii + 5] = c
					ii += 6
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _new_arrays(v, n, uv, ind, tang))
			mesh.surface_set_material(0, materials["terrain"])
			_attach_mesh(parent, "Terrain_%d_%d" % [ix0, iz0], mesh, 1, "terrain")
			stats["terrain_chunks"] += 1
			stats["terrain_vertices"] += vert_count
			stats["terrain_triangles"] += (depth * width * 2)

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

func _section(points: PackedVector3Array, i: int, half_width: float, elevated := false, shoulder: float = SHOULDER_M) -> Array[Vector3]:
	var previous: Vector3 = points[maxi(0, i - 1)]
	var following: Vector3 = points[mini(points.size() - 1, i + 1)]
	var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
	var lateral := Vector2(-tangent.y, tangent.x)
	var offsets := [-half_width - shoulder, -half_width, 0.0, half_width, half_width + shoulder]
	var result: Array[Vector3] = []
	for off in offsets:
		var x: float = points[i].x + lateral.x * float(off)
		var z: float = points[i].z + lateral.y * float(off)
		var ground: float = source.sample_surface_height(x, z)
		var y: float
		if elevated:
			y = points[i].y + ROAD_LIFT_M
		elif absf(float(off)) > half_width + 0.001:
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

func _road_width(base: float, profile: Dictionary, station: float, full_length: float) -> float:
	if profile.is_empty():
		return base
	var radius := float(profile["wide_radius"])
	var taper := 1.0 - smoothstep(radius * 0.48, radius, absf(station - float(profile["center"])))
	taper *= smoothstep(18.0, 37.0, minf(station, full_length - station))
	return lerpf(base, float(profile["width_m"]) * 0.5, taper)

# Leave legacy bridge decks and the immediate junction seams at their original size.
func _network_factor(profile: Dictionary, station: float, full_length: float) -> float:
	var factor := smoothstep(6.0, 34.0, minf(station, full_length - station))
	if profile.has("bridge_start"):
		var gap := maxf(float(profile["bridge_start"]) - station, station - float(profile["bridge_end"]))
		factor *= smoothstep(0.0, 28.0, gap)
	return factor

func physical_half_width(road_id: String, base: float, profile: Dictionary, station: float, full_length: float) -> float:
	var legacy := _road_width(base, profile, station, full_length)
	var target := float(network.get("widths_m", {}).get(road_id, base * 2.0)) * 0.5
	return lerpf(legacy, maxf(legacy, target), _network_factor(profile, station, full_length))

func physical_shoulder(surface: String, profile: Dictionary, station: float, full_length: float) -> float:
	var target := float(network.get(surface + "_shoulder_m", SHOULDER_M))
	return lerpf(SHOULDER_M, target, _network_factor(profile, station, full_length))

func _bridge_station(profile: Dictionary, station: float) -> bool:
	return profile.has("bridge_start") and station >= float(profile["bridge_start"]) - 0.008 and station <= float(profile["bridge_end"]) + 0.008

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
	var full_length := 0.0
	for index in range(1, center.size()):
		var delta := center[index] - center[index - 1]
		full_length += Vector2(delta.x, delta.z).length()
	var profile: Dictionary = roadworks.get("roads", {}).get(str(road["id"]), {})
	var bridge_sections: Array = []
	for i in range(center.size() - 1):
		var p: Vector3 = center[i]
		var q: Vector3 = center[i + 1]
		var length: float = Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))
		if not (_in_view(p.x, p.z, 16.0) or _in_view(q.x, q.z, 16.0)):
			cumulative += length
			continue
		var end := cumulative + length
		var elevated_begin := _bridge_station(profile, cumulative)
		var elevated_end := _bridge_station(profile, end)
		var road_id := str(road["id"])
		var width_a := physical_half_width(road_id, half_width, profile, cumulative, full_length)
		var width_b := physical_half_width(road_id, half_width, profile, end, full_length)
		var shoulder_a := physical_shoulder(surface, profile, cumulative, full_length)
		var shoulder_b := physical_shoulder(surface, profile, end, full_length)
		var a := _section(center, i, width_a, elevated_begin, shoulder_a)
		var b := _section(center, i + 1, width_b, elevated_end, shoulder_b)
		if clearance != null:
			clearance.add_segment(Vector2(p.x, p.z), Vector2(q.x, q.z), maxf(width_a + shoulder_a, width_b + shoulder_b))
		if elevated_begin and elevated_end:
			if bridge_sections.is_empty():
				bridge_sections.append(a)
			bridge_sections.append(b)
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
		_new_arrays(pavement_verts, pavement_norms, pavement_uv, PackedInt32Array(),
			_compute_triangle_tangents(pavement_verts, pavement_norms, pavement_uv)))
	mesh.surface_set_material(0, materials[surface])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_new_arrays(shoulder_verts, shoulder_norms, shoulder_uv, PackedInt32Array(),
			_compute_triangle_tangents(shoulder_verts, shoulder_norms, shoulder_uv)))
	mesh.surface_set_material(1, materials["shoulder"])
	_attach_mesh(parent, "Road_" + road["id"], mesh, 2, surface)
	if not bridge_sections.is_empty():
		RoadworksArt.build_bridge(parent, str(profile["name"]).replace(" ", ""), bridge_sections, source, make_colliders)
		stats["bridges"] = int(stats.get("bridges", 0)) + 1
		if make_colliders:
			stats["static_colliders"] += 1
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
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	var unique: Array[Vector2] = []
	for p in ordered:
		if unique.is_empty() or unique[-1] != p:
			unique.append(p)
	if unique.size() < 3:
		return unique
	var lower: Array[Vector2] = []
	for p in unique:
		while lower.size() > 1 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	unique.reverse()
	for p in unique:
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
	var reach: float = float(lane["width_m"]) * 0.5 + PAD_MARGIN_M + float(network.get("junction_extra_m", 0.0))
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
		if clearance != null:
			clearance.add_polygon(hull, SHOULDER_M)
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
		var skirt_verts := PackedVector3Array()
		var skirt_norms := PackedVector3Array()
		var skirt_uvs := PackedVector2Array()
		_append_pad_skirt(hull, skirt_verts, skirt_norms, skirt_uvs)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			_new_arrays(vertices, normals, uvs, PackedInt32Array(),
				_compute_triangle_tangents(vertices, normals, uvs)))
		var pad_surface: String = group_surfaces[junction]
		var pad_mat: Material = materials["junction_asphalt"] if pad_surface == "asphalt" else materials[pad_surface]
		mesh.surface_set_material(0, pad_mat)
		var surf_count := 1
		if not skirt_verts.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				_new_arrays(skirt_verts, skirt_norms, skirt_uvs, PackedInt32Array(),
					_compute_triangle_tangents(skirt_verts, skirt_norms, skirt_uvs)))
			mesh.surface_set_material(1, materials["shoulder"])
			surf_count = 2
		_attach_mesh(parent, "Junction_" + junction, mesh, surf_count, group_surfaces[junction])
		stats["junction_pads"] += 1
		stats["turn_paths_covered"] += int(turn_counts[junction])
		stats["junction_vertices"] += vertices.size() + skirt_verts.size()
		stats["junction_triangles"] += (vertices.size() + skirt_verts.size()) / 3

func _append_pad_skirt(hull: Array[Vector2], verts: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var n: int = hull.size()
	if n < 3:
		return
	var edge_out: Array[Vector2] = []
	edge_out.resize(n)
	for j in range(n):
		var d: Vector2 = hull[(j + 1) % n] - hull[j]
		edge_out[j] = Vector2(d.y, -d.x).normalized()
	var vert_out: Array[Vector2] = []
	vert_out.resize(n)
	for j in range(n):
		var prev_n: Vector2 = edge_out[(j - 1 + n) % n]
		var next_n: Vector2 = edge_out[j]
		var avg: Vector2 = (prev_n + next_n).normalized()
		if avg.length_squared() < 0.001:
			avg = next_n
		vert_out[j] = avg * SHOULDER_M
	var cumulative := 0.0
	for j in range(n):
		var j_next: int = (j + 1) % n
		var a2: Vector2 = hull[j]
		var b2: Vector2 = hull[j_next]
		var out_a: Vector2 = a2 + vert_out[j]
		var out_b: Vector2 = b2 + vert_out[j_next]
		var edge_len: float = a2.distance_to(b2)
		if edge_len < 0.001:
			continue
		var steps: int = maxi(1, int(ceil(edge_len / PAD_GRID_M)))
		var step_len: float = edge_len / float(steps)
		for s in range(steps):
			var t0: float = float(s) / float(steps)
			var t1: float = float(s + 1) / float(steps)
			var in0: Vector2 = a2.lerp(b2, t0)
			var in1: Vector2 = a2.lerp(b2, t1)
			var o0: Vector2 = out_a.lerp(out_b, t0)
			var o1: Vector2 = out_a.lerp(out_b, t1)
			var v_in0 := _pad_vert(in0)
			var v_in1 := _pad_vert(in1)
			var v_o0 := Vector3(o0.x, source.sample_surface_height(o0.x, o0.y) - OUTER_BURY_M, o0.y)
			var v_o1 := Vector3(o1.x, source.sample_surface_height(o1.x, o1.y) - OUTER_BURY_M, o1.y)
			_append_quad(verts, norms, uvs, v_o0, v_in0, v_o1, v_in1,
				0.0, SHOULDER_M / 4.0, cumulative / 4.0, (cumulative + step_len) / 4.0)
			cumulative += step_len

func _pad_normal(x: float, z: float) -> Vector3:
	var step := 1.0
	return Vector3(
		source.sample_surface_height(x - step, z) - source.sample_surface_height(x + step, z),
		2.0 * step,
		source.sample_surface_height(x, z - step) - source.sample_surface_height(x, z + step)
	).normalized()
