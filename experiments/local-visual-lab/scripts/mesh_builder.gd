class_name MeshBuilder
extends RefCounted

## Procedural 3D mesh & MultiMesh generator for Aster Valley Local Visual Lab.
## All geometry is original and generated deterministically in GDScript.


static func build_terrain_mesh(tm: TerrainMath, grid_res: int = 176) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var extent: float = TerrainMath.WORLD_HALF_EXTENT
	var step: float = (extent * 2.0) / float(grid_res)
	var verts_per_row: int = grid_res + 1

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	positions.resize(verts_per_row * verts_per_row)
	normals.resize(verts_per_row * verts_per_row)
	colors.resize(verts_per_row * verts_per_row)
	uvs.resize(verts_per_row * verts_per_row)

	for gz in range(verts_per_row):
		var z: float = -extent + float(gz) * step
		for gx in range(verts_per_row):
			var x: float = -extent + float(gx) * step
			var idx: int = gz * verts_per_row + gx
			var y: float = tm.get_height(x, z)
			positions[idx] = Vector3(x, y, z)
			normals[idx] = tm.get_normal(x, z, 0.75)

			var prox: Dictionary = tm.query_road_proximity(x, z)
			var dist: float = prox["dist"]
			var signed_x: float = prox["signed_x"]
			var extra: float = tm.get_overlook_extra_width(prox["z"]) if signed_x > 0.0 else 0.0
			var shoulder_w: float = TerrainMath.SHOULDER_HALF_WIDTH + extra
			var gravel_w: float = 1.0 - TerrainMath.smoothstep(shoulder_w - 0.6, shoulder_w + 3.4, dist)
			colors[idx] = Color(gravel_w, 0.0, 0.0, 1.0)
			uvs[idx] = Vector2(float(gx) / float(grid_res), float(gz) / float(grid_res))

	for gz in range(grid_res):
		for gx in range(grid_res):
			var i00: int = gz * verts_per_row + gx
			var i10: int = i00 + 1
			var i01: int = i00 + verts_per_row
			var i11: int = i01 + 1

			# Counter-clockwise winding viewed from +Y
			for idx in [i00, i10, i11, i00, i11, i01]:
				st.set_normal(normals[idx])
				st.set_color(colors[idx])
				st.set_uv(uvs[idx])
				st.add_vertex(positions[idx])

	return st.commit()


static func build_distant_mountains_mesh(tm: TerrainMath, rings: int = 44, segs: int = 128) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var r_min: float = 195.0
	var r_max: float = 1480.0
	var stride: int = segs + 1
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	positions.resize((rings + 1) * stride)
	normals.resize((rings + 1) * stride)

	for ir in range(rings + 1):
		var rt: float = float(ir) / float(rings)
		# Denser near the inner rim, wider toward the horizon
		var r: float = lerpf(r_min, r_max, pow(rt, 1.45))
		for iseg in range(stride):
			var ang: float = (float(iseg) / float(segs)) * TAU
			var x: float = cos(ang) * r
			var z: float = sin(ang) * r
			var y: float = tm.get_distant_mountain_height(x, z)
			var idx: int = ir * stride + iseg
			positions[idx] = Vector3(x, y, z)

			var eps: float = 4.5
			var hl: float = tm.get_distant_mountain_height(x - eps, z)
			var hr: float = tm.get_distant_mountain_height(x + eps, z)
			var hd: float = tm.get_distant_mountain_height(x, z - eps)
			var hu: float = tm.get_distant_mountain_height(x, z + eps)
			normals[idx] = Vector3(hl - hr, 2.0 * eps, hd - hu).normalized()

	for ir in range(rings):
		for iseg in range(segs):
			var i00: int = ir * stride + iseg
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			for idx in [i00, i01, i11, i00, i11, i10]:
				st.set_normal(normals[idx])
				st.set_color(Color(0.0, 0.0, 0.0, 1.0))
				st.set_uv(Vector2(0.0, 0.0))
				st.add_vertex(positions[idx])

	return st.commit()


static func build_road_mesh(tm: TerrainMath) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n: int = tm.road_samples.size()
	var half_total: float = TerrainMath.ROAD_HALF_WIDTH + 1.15  # 4.2 + 1.15 = 5.35 m each side (10.7 m total)
	# Cross-section offsets normalized in [-1, 1] with subtle crown
	var xs: Array[float] = [-1.0, -0.84, -0.5, 0.0, 0.5, 0.84, 1.0]
	var ys: Array[float] = [-0.14, 0.02, 0.055, 0.075, 0.055, 0.02, -0.14]
	var cols: int = xs.size()

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * cols)
	uvs.resize(n * cols)

	for i in range(n):
		var c: Vector3 = tm.road_samples[i]
		var r: Vector3 = tm.road_rights[i]
		var v_dist: float = tm.road_dists[i]
		for j in range(cols):
			var lat: float = xs[j] * half_total
			var pos: Vector3 = c + r * lat + Vector3(0.0, ys[j], 0.0)
			var idx: int = i * cols + j
			verts[idx] = pos
			uvs[idx] = Vector2(xs[j] * 0.5 + 0.5, v_dist)

	for i in range(n - 1):
		for j in range(cols - 1):
			var i00: int = i * cols + j
			var i10: int = i00 + 1
			var i01: int = (i + 1) * cols + j
			var i11: int = i01 + 1
			# Winding for +Y upward normal
			for idx in [i00, i10, i11, i00, i11, i01]:
				st.set_uv(uvs[idx])
				st.add_vertex(verts[idx])

	st.generate_normals()
	return st.commit()


static func build_overlook_turnout_pad(tm: TerrainMath) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs: int = 28
	var z0: float = TerrainMath.OVERLOOK_Z - TerrainMath.OVERLOOK_Z_HALF - 4.0
	var z1: float = TerrainMath.OVERLOOK_Z + TerrainMath.OVERLOOK_Z_HALF + 4.0
	var cols: int = 4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize((segs + 1) * cols)
	uvs.resize((segs + 1) * cols)

	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var z: float = lerpf(z0, z1, t)
		var c: Vector3 = tm.road_point(z)
		var r: Vector3 = tm.road_right(z)
		var extra: float = tm.get_overlook_extra_width(z)
		var inner_x: float = TerrainMath.ROAD_HALF_WIDTH - 0.15
		var outer_x: float = TerrainMath.ROAD_HALF_WIDTH + maxf(0.4, extra + 0.25)
		for j in range(cols):
			var u: float = float(j) / float(cols - 1)
			var lat: float = lerpf(inner_x, outer_x, u)
			var drop: float = -0.09 if j == cols - 1 else 0.015
			verts[i * cols + j] = c + r * lat + Vector3(0.0, drop, 0.0)
			uvs[i * cols + j] = Vector2(u, t * 28.0)

	for i in range(segs):
		for j in range(cols - 1):
			var i00: int = i * cols + j
			var i10: int = i00 + 1
			var i01: int = (i + 1) * cols + j
			var i11: int = i01 + 1
			for idx in [i00, i10, i11, i00, i11, i01]:
				st.set_uv(uvs[idx])
				st.add_vertex(verts[idx])

	st.generate_normals()
	return st.commit()


static func build_guardrails(tm: TerrainMath) -> Node3D:
	var root := Node3D.new()
	root.name = "Guardrails"

	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.62, 0.65, 0.68)
	rail_mat.metallic = 0.72
	rail_mat.roughness = 0.36

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.24, 0.21, 0.18)
	post_mat.roughness = 0.85

	var refl_mat := StandardMaterial3D.new()
	refl_mat.albedo_color = Color(0.95, 0.72, 0.18)
	refl_mat.emission_enabled = true
	refl_mat.emission = Color(1.0, 0.72, 0.16)
	refl_mat.emission_energy_multiplier = 0.55

	# Two guardrail runs along the lakeside (east) drop-off, leaving an opening for the overlook deck
	var ranges: Array[Vector2] = [
		Vector2(-165.0, -34.0),
		Vector2(0.0, 165.0),
	]

	var post_transforms: Array[Transform3D] = []
	var refl_transforms: Array[Transform3D] = []

	var st_rail := SurfaceTool.new()
	st_rail.begin(Mesh.PRIMITIVE_TRIANGLES)

	for seg_range in ranges:
		var z_start: float = seg_range.x
		var z_end: float = seg_range.y
		var steps: int = int(ceil((z_end - z_start) / 2.8))
		var prev_left_b := Vector3.ZERO
		var prev_left_t := Vector3.ZERO
		var prev_right_b := Vector3.ZERO
		var prev_right_t := Vector3.ZERO

		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var z: float = lerpf(z_start, z_end, t)
			var c: Vector3 = tm.road_point(z)
			var r: Vector3 = tm.road_right(z)
			var fwd: Vector3 = tm.road_tangent(z)
			var base: Vector3 = c + r * (TerrainMath.ROAD_HALF_WIDTH + 0.85)
			base.y = c.y - 0.04

			var p_lb: Vector3 = base - r * 0.08 + Vector3(0.0, 0.48, 0.0)
			var p_lt: Vector3 = base - r * 0.08 + Vector3(0.0, 0.82, 0.0)
			var p_rb: Vector3 = base + r * 0.06 + Vector3(0.0, 0.48, 0.0)
			var p_rt: Vector3 = base + r * 0.06 + Vector3(0.0, 0.82, 0.0)

			if i > 0:
				# Front face (facing road)
				st_rail.add_vertex(prev_left_b)
				st_rail.add_vertex(p_lb)
				st_rail.add_vertex(p_lt)
				st_rail.add_vertex(prev_left_b)
				st_rail.add_vertex(p_lt)
				st_rail.add_vertex(prev_left_t)
				# Top face
				st_rail.add_vertex(prev_left_t)
				st_rail.add_vertex(p_lt)
				st_rail.add_vertex(p_rt)
				st_rail.add_vertex(prev_left_t)
				st_rail.add_vertex(p_rt)
				st_rail.add_vertex(prev_right_t)
				# Back face (facing lake)
				st_rail.add_vertex(prev_right_t)
				st_rail.add_vertex(p_rt)
				st_rail.add_vertex(p_rb)
				st_rail.add_vertex(prev_right_t)
				st_rail.add_vertex(p_rb)
				st_rail.add_vertex(prev_right_b)

			prev_left_b = p_lb
			prev_left_t = p_lt
			prev_right_b = p_rb
			prev_right_t = p_rt

			# Vertical post every step
			var post_basis := Basis(r, Vector3.UP, fwd).orthonormalized()
			var post_pos: Vector3 = base + r * 0.09 + Vector3(0.0, 0.35, 0.0)
			post_transforms.append(Transform3D(post_basis, post_pos))

			if i % 3 == 0:
				var refl_pos: Vector3 = base - r * 0.09 + Vector3(0.0, 0.72, 0.0)
				refl_transforms.append(Transform3D(post_basis, refl_pos))

	st_rail.generate_normals()
	var rail_mi := MeshInstance3D.new()
	rail_mi.name = "GuardrailBeams"
	rail_mi.mesh = st_rail.commit()
	rail_mi.material_override = rail_mat
	root.add_child(rail_mi)

	# Posts MultiMesh
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.14, 1.05, 0.14)
	var posts_mmi := MultiMeshInstance3D.new()
	posts_mmi.name = "GuardrailPosts"
	var posts_mm := MultiMesh.new()
	posts_mm.transform_format = MultiMesh.TRANSFORM_3D
	posts_mm.mesh = post_box
	posts_mm.instance_count = post_transforms.size()
	for i in range(post_transforms.size()):
		posts_mm.set_instance_transform(i, post_transforms[i])
	posts_mmi.multimesh = posts_mm
	posts_mmi.material_override = post_mat
	root.add_child(posts_mmi)

	# Delineator reflectors MultiMesh
	var refl_box := BoxMesh.new()
	refl_box.size = Vector3(0.04, 0.14, 0.08)
	var refl_mmi := MultiMeshInstance3D.new()
	refl_mmi.name = "GuardrailReflectors"
	var refl_mm := MultiMesh.new()
	refl_mm.transform_format = MultiMesh.TRANSFORM_3D
	refl_mm.mesh = refl_box
	refl_mm.instance_count = refl_transforms.size()
	for i in range(refl_transforms.size()):
		refl_mm.set_instance_transform(i, refl_transforms[i])
	refl_mmi.multimesh = refl_mm
	refl_mmi.material_override = refl_mat
	root.add_child(refl_mmi)

	return root


static func build_overlook_deck(tm: TerrainMath) -> Node3D:
	var deck := Node3D.new()
	deck.name = "ScenicOverlookDeck"

	var z_mid: float = TerrainMath.OVERLOOK_Z
	var c: Vector3 = tm.road_point(z_mid)
	var r: Vector3 = tm.road_right(z_mid)
	var fwd: Vector3 = tm.road_tangent(z_mid)
	var basis := Basis(r, Vector3.UP, fwd).orthonormalized()
	deck.transform = Transform3D(basis, c + r * (TerrainMath.ROAD_HALF_WIDTH + TerrainMath.OVERLOOK_EXTRA_EAST + 0.8) + Vector3(0.0, 0.02, 0.0))

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.32, 0.22, 0.14)
	wood_mat.roughness = 0.82

	var dark_wood_mat := StandardMaterial3D.new()
	dark_wood_mat.albedo_color = Color(0.20, 0.14, 0.09)
	dark_wood_mat.roughness = 0.86

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.36, 0.35, 0.33)
	stone_mat.roughness = 0.88

	# Main cantilevered deck platform
	var plat := MeshInstance3D.new()
	var plat_box := BoxMesh.new()
	plat_box.size = Vector3(4.2, 0.28, 16.0)
	plat.mesh = plat_box
	plat.position = Vector3(1.4, -0.05, 0.0)
	plat.material_override = wood_mat
	deck.add_child(plat)

	# Stone retaining base under deck
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(3.4, 4.2, 15.6)
	wall.mesh = wall_box
	wall.position = Vector3(0.8, -2.2, 0.0)
	wall.material_override = stone_mat
	deck.add_child(wall)

	# Timber railing posts + top & mid rails along lakeside edge
	for iz in range(-4, 5):
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.16, 1.15, 0.16)
		post.mesh = pb
		post.position = Vector3(3.35, 0.56, float(iz) * 1.95)
		post.material_override = dark_wood_mat
		deck.add_child(post)

	for ry in [0.62, 1.08]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.12, 0.10, 15.8)
		rail.mesh = rb
		rail.position = Vector3(3.35, ry, 0.0)
		rail.material_override = wood_mat
		deck.add_child(rail)

	# Two scenic wooden benches facing Eastwater Lake
	for bz in [-4.5, 4.5]:
		var bench := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.55, 0.10, 2.2)
		bench.mesh = bb
		bench.position = Vector3(1.1, 0.48, bz)
		bench.material_override = wood_mat
		deck.add_child(bench)

	return deck


## Builds a realistic multi-tier conifer tree (separate trunk & canopy meshes).
static func build_pine_meshes() -> Dictionary:
	# 1. Tapered bark trunk
	var st_trunk := SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_segs: int = 7
	var trunk_h: float = 11.5
	var r_bot: float = 0.42
	var r_top: float = 0.08
	for i in range(trunk_segs):
		var a0: float = float(i) / float(trunk_segs) * TAU
		var a1: float = float(i + 1) / float(trunk_segs) * TAU
		var b0 := Vector3(cos(a0) * r_bot, -0.5, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, -0.5, sin(a1) * r_bot)
		var t0 := Vector3(cos(a0) * r_top, trunk_h, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, trunk_h, sin(a1) * r_top)
		st_trunk.add_vertex(b0)
		st_trunk.add_vertex(b1)
		st_trunk.add_vertex(t1)
		st_trunk.add_vertex(b0)
		st_trunk.add_vertex(t1)
		st_trunk.add_vertex(t0)
	st_trunk.generate_normals()

	# 2. Multi-tier irregular star-shaped drooping conifer boughs (6 tiers)
	var st_canopy := SurfaceTool.new()
	st_canopy.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers: Array[Dictionary] = [
		{"y_base": 2.4, "y_top": 6.0, "rad": 3.45, "droop": 0.65, "lobes": 9, "rot": 0.0},
		{"y_base": 4.4, "y_top": 8.0, "rad": 2.95, "droop": 0.55, "lobes": 9, "rot": 0.35},
		{"y_base": 6.4, "y_top": 9.8, "rad": 2.45, "droop": 0.45, "lobes": 8, "rot": 0.72},
		{"y_base": 8.3, "y_top": 11.5, "rad": 1.90, "droop": 0.36, "lobes": 8, "rot": 0.18},
		{"y_base": 10.1, "y_top": 13.0, "rad": 1.32, "droop": 0.25, "lobes": 7, "rot": 0.55},
		{"y_base": 11.7, "y_top": 14.3, "rad": 0.72, "droop": 0.12, "lobes": 6, "rot": 0.90},
	]

	for tier in tiers:
		var y_base: float = tier["y_base"]
		var y_top: float = tier["y_top"]
		var rad: float = tier["rad"]
		var droop: float = tier["droop"]
		var lobes: int = tier["lobes"]
		var rot: float = tier["rot"]
		var ring_pts: int = lobes * 2
		var apex := Vector3(0.0, y_top, 0.0)
		var ring := PackedVector3Array()
		ring.resize(ring_pts)
		for k in range(ring_pts):
			var ang: float = rot + float(k) / float(ring_pts) * TAU
			var is_tip: bool = (k % 2 == 0)
			var rr: float = rad * (1.0 if is_tip else 0.56)
			var dy: float = -droop if is_tip else 0.12
			ring[k] = Vector3(cos(ang) * rr, y_base + dy, sin(ang) * rr)

		for k in range(ring_pts):
			var p0: Vector3 = ring[k]
			var p1: Vector3 = ring[(k + 1) % ring_pts]
			var u0: float = 1.0 if (k % 2 == 0) else 0.35
			var u1: float = 1.0 if ((k + 1) % 2 == 0) else 0.35
			st_canopy.set_uv(Vector2(0.5, 0.25))
			st_canopy.add_vertex(apex)
			st_canopy.set_uv(Vector2(0.0, u1))
			st_canopy.add_vertex(p1)
			st_canopy.set_uv(Vector2(1.0, u0))
			st_canopy.add_vertex(p0)

	st_canopy.generate_normals()
	return {"trunk": st_trunk.commit(), "canopy": st_canopy.commit()}


## Builds a deciduous autumn-accent birch/alder tree (trunk + multi-cluster organic crown).
static func build_birch_meshes() -> Dictionary:
	var st_trunk := SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = 6
	for i in range(segs):
		var a0: float = float(i) / float(segs) * TAU
		var a1: float = float(i + 1) / float(segs) * TAU
		var b0 := Vector3(cos(a0) * 0.22, -0.4, sin(a0) * 0.22)
		var b1 := Vector3(cos(a1) * 0.22, -0.4, sin(a1) * 0.22)
		var t0 := Vector3(cos(a0) * 0.08 + 0.18, 6.2, sin(a0) * 0.08)
		var t1 := Vector3(cos(a1) * 0.08 + 0.18, 6.2, sin(a1) * 0.08)
		st_trunk.add_vertex(b0)
		st_trunk.add_vertex(b1)
		st_trunk.add_vertex(t1)
		st_trunk.add_vertex(b0)
		st_trunk.add_vertex(t1)
		st_trunk.add_vertex(t0)
	st_trunk.generate_normals()

	# Organic clustered crown made of 5 displaced icospheres
	var st_crown := SurfaceTool.new()
	st_crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clusters: Array[Dictionary] = [
		{"c": Vector3(0.0, 6.8, 0.0), "r": 2.35},
		{"c": Vector3(1.3, 5.8, 0.7), "r": 1.75},
		{"c": Vector3(-1.2, 5.9, -0.6), "r": 1.85},
		{"c": Vector3(-0.4, 5.3, 1.3), "r": 1.55},
		{"c": Vector3(0.7, 7.9, -0.4), "r": 1.45},
	]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 5
	sphere.radius = 1.0
	sphere.height = 2.0
	var arr: Array = sphere.get_mesh_arrays()
	var sp_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sp_idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	for cl in clusters:
		var center: Vector3 = cl["c"]
		var rad: float = cl["r"]
		for ii in range(0, sp_idx.size(), 3):
			for k in range(3):
				var v: Vector3 = sp_verts[sp_idx[ii + k]]
				var jitter: float = 1.0 + 0.16 * sin(v.x * 5.2 + v.y * 4.1) * cos(v.z * 4.7)
				var p: Vector3 = center + v * rad * jitter
				var tip_t: float = clampf((v.y + 1.0) * 0.5, 0.15, 1.0)
				st_crown.set_uv(Vector2(0.5, tip_t))
				st_crown.add_vertex(p)

	st_crown.generate_normals()
	return {"trunk": st_trunk.commit(), "canopy": st_crown.commit()}


## Builds a faceted alpine granite boulder mesh.
static func build_boulder_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.radius = 1.0
	sphere.height = 1.65
	var arr: Array = sphere.get_mesh_arrays()
	var sp_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sp_idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ii in range(0, sp_idx.size(), 3):
		var tri: Array[Vector3] = []
		for k in range(3):
			var v: Vector3 = sp_verts[sp_idx[ii + k]]
			var n1: float = sin(v.x * 3.1 + 0.7) * cos(v.z * 2.7 - 0.4)
			var n2: float = sin(v.y * 4.3 + v.x * 2.2) * 0.14
			var scale_f: float = 0.88 + 0.22 * n1 + n2
			var p := Vector3(v.x * scale_f * 1.15, v.y * scale_f * 0.78, v.z * scale_f)
			if p.y < -0.35:
				p.y = lerpf(p.y, -0.35, 0.55)
			tri.append(p)
		var face_n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		for p in tri:
			st.set_normal(face_n)
			st.add_vertex(p)

	return st.commit()


## Builds a 5-blade curved grass tuft mesh (UV.y = 0 at root, 1 at tip).
static func build_grass_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var angles: Array[float] = [0.0, 1.26, 2.51, 3.77, 5.03]
	var heights: Array[float] = [0.64, 0.50, 0.60, 0.46, 0.56]
	var leans: Array[float] = [0.18, 0.14, 0.20, 0.15, 0.17]

	for b in range(angles.size()):
		var ang: float = angles[b]
		var h: float = heights[b]
		var lean: float = leans[b]
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))

		var w0: float = 0.075
		var w1: float = 0.048
		var p0l: Vector3 = -side * w0
		var p0r: Vector3 = side * w0
		var p1l: Vector3 = dir * (lean * 0.38) - side * w1 + Vector3(0.0, h * 0.52, 0.0)
		var p1r: Vector3 = dir * (lean * 0.38) + side * w1 + Vector3(0.0, h * 0.52, 0.0)
		var p2: Vector3 = dir * lean + Vector3(0.0, h, 0.0)

		# Lower quad
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0l)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p0r)
		st.set_uv(Vector2(1.0, 0.55)); st.add_vertex(p1r)

		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0l)
		st.set_uv(Vector2(1.0, 0.55)); st.add_vertex(p1r)
		st.set_uv(Vector2(0.0, 0.55)); st.add_vertex(p1l)

		# Upper tapered tip
		st.set_uv(Vector2(0.0, 0.55)); st.add_vertex(p1l)
		st.set_uv(Vector2(1.0, 0.55)); st.add_vertex(p1r)
		st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(p2)

	st.generate_normals()
	return st.commit()


## Builds a sleek, original static fictional sports coupe ("Vela GT" visual reference sculpture)
## for scale, metallic clearcoat reflection, and emissive tail/headlight validation.
static func build_showcase_coupe() -> Node3D:
	var car := Node3D.new()
	car.name = "VelaGT_VisualReference"

	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.68, 0.11, 0.09) # Deep metallic crimson
	paint_mat.metallic = 0.78
	paint_mat.roughness = 0.17
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 1.0
	paint_mat.clearcoat_roughness = 0.06

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.04, 0.06, 0.09)
	glass_mat.metallic = 0.25
	glass_mat.roughness = 0.05
	glass_mat.clearcoat_enabled = true
	glass_mat.clearcoat = 1.0

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.08, 0.085, 0.095)
	trim_mat.roughness = 0.45
	trim_mat.metallic = 0.3

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.06, 0.06, 0.065)
	wheel_mat.roughness = 0.78

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.76, 0.78, 0.82)
	rim_mat.metallic = 0.92
	rim_mat.roughness = 0.18

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.96, 0.88)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.94, 0.82)
	head_mat.emission_energy_multiplier = 3.2

	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.95, 0.08, 0.06)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.10, 0.06)
	tail_mat.emission_energy_multiplier = 2.6

	# Lower sculpted chassis (~4.45 m long, 1.92 m wide)
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(1.92, 0.56, 4.42)
	body.mesh = body_box
	body.position = Vector3(0.0, 0.54, 0.0)
	body.material_override = paint_mat
	car.add_child(body)

	# Sleek tapered hood / nose
	var nose := MeshInstance3D.new()
	var nose_box := BoxMesh.new()
	nose_box.size = Vector3(1.86, 0.34, 1.35)
	nose.mesh = nose_box
	nose.position = Vector3(0.0, 0.74, -1.35)
	nose.rotation_degrees = Vector3(7.0, 0.0, 0.0)
	nose.material_override = paint_mat
	car.add_child(nose)

	# Fastback cabin / greenhouse
	var cabin := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(1.52, 0.46, 2.05)
	cabin.mesh = cabin_box
	cabin.position = Vector3(0.0, 1.02, 0.25)
	cabin.material_override = glass_mat
	car.add_child(cabin)

	# Painted roof cap
	var roof := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(1.44, 0.08, 1.42)
	roof.mesh = roof_box
	roof.position = Vector3(0.0, 1.25, 0.20)
	roof.material_override = paint_mat
	car.add_child(roof)

	# Rear ducktail spoiler + dark diffuser
	var spoiler := MeshInstance3D.new()
	var sp_box := BoxMesh.new()
	sp_box.size = Vector3(1.76, 0.07, 0.26)
	spoiler.mesh = sp_box
	spoiler.position = Vector3(0.0, 0.92, 2.08)
	spoiler.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	spoiler.material_override = trim_mat
	car.add_child(spoiler)

	var diffuser := MeshInstance3D.new()
	var diff_box := BoxMesh.new()
	diff_box.size = Vector3(1.82, 0.22, 0.24)
	diffuser.mesh = diff_box
	diffuser.position = Vector3(0.0, 0.32, 2.15)
	diffuser.material_override = trim_mat
	car.add_child(diffuser)

	# LED Headlights + full-width crimson tail-light bar
	for sx in [-0.66, 0.66]:
		var hl := MeshInstance3D.new()
		var hlb := BoxMesh.new()
		hlb.size = Vector3(0.42, 0.09, 0.08)
		hl.mesh = hlb
		hl.position = Vector3(sx, 0.66, -2.21)
		hl.material_override = head_mat
		car.add_child(hl)

	var tl := MeshInstance3D.new()
	var tlb := BoxMesh.new()
	tlb.size = Vector3(1.68, 0.08, 0.07)
	tl.mesh = tlb
	tl.position = Vector3(0.0, 0.72, 2.21)
	tl.material_override = tail_mat
	car.add_child(tl)

	# 4 Wheels + alloy rims
	var wheel_positions: Array[Vector3] = [
		Vector3(-0.92, 0.34, -1.38),
		Vector3(0.92, 0.34, -1.38),
		Vector3(-0.92, 0.34, 1.38),
		Vector3(0.92, 0.34, 1.38),
	]
	for wp in wheel_positions:
		var tire := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.34
		tc.bottom_radius = 0.34
		tc.height = 0.26
		tc.radial_segments = 20
		tire.mesh = tc
		tire.position = wp
		tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		tire.material_override = wheel_mat
		car.add_child(tire)

		var rim := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 0.23
		rc.bottom_radius = 0.23
		rc.height = 0.28
		rc.radial_segments = 16
		rim.mesh = rc
		rim.position = wp
		rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		rim.material_override = rim_mat
		car.add_child(rim)

	return car
