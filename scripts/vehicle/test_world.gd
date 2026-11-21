class_name DrivingTestWorld
extends Node3D
## Original deterministic 500 x 500 m prototype. One Godot unit = one meter.
## A graded spline ribbon and heightfield mesh have independent static collisions.
const SIZE := 500.0
const CELL := 4.0
const ROAD_WIDTH := 8.4
const SHOULDER_WIDTH := 12.0
var road_points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20261121
	_bake_road()
	_build_terrain()
	_build_road()
	_build_barriers()
	_build_trees()
	_build_signs()
	_build_lighting()
	_build_boundary()

func _base_height(x: float, z: float) -> float:
	return 1.2 + 2.0 * sin(x / 80.0) * cos(z / 104.0) + 1.6 * sin(z / 79.0) + 0.45 * cos(x / 33.0)

func _bake_road() -> void:
	# South start -> long northbound acceleration straight -> S-bends -> hairpin.
	var controls: Array[Vector2] = [
		Vector2(-176, 212), Vector2(-178, 110), Vector2(-169, -54),
		Vector2(-123, -139), Vector2(-52, -157), Vector2(15, -119),
		Vector2(82, -143), Vector2(157, -148), Vector2(201, -102),
		Vector2(202, -49), Vector2(170, -8), Vector2(109, 5),
		Vector2(58, 14), Vector2(46, 65), Vector2(83, 111),
		Vector2(144, 163), Vector2(193, 201)
	]
	for i in range(controls.size() - 1):
		var a: Vector2 = controls[maxi(i - 1, 0)]
		var b: Vector2 = controls[i]
		var c: Vector2 = controls[i + 1]
		var d: Vector2 = controls[mini(i + 2, controls.size() - 1)]
		var steps := maxi(2, ceili(b.distance_to(c) / 2.5))
		for j in range(steps):
			var p := _catmull(a, b, c, d, float(j) / steps)
			road_points.append(Vector3(p.x, _base_height(p.x, p.y), p.y))
	var end: Vector2 = controls.back()
	road_points.append(Vector3(end.x, _base_height(end.x, end.y), end.y))
	# Suppress high-frequency undulations under the road without flattening hills.
	for repetition in range(5):
		var heights := PackedFloat32Array()
		for p in road_points:
			heights.append(p.y)
		for i in range(1, road_points.size() - 1):
			var graded := road_points[i]
			graded.y = heights[i - 1] * 0.25 + heights[i] * 0.50 + heights[i + 1] * 0.25
			road_points[i] = graded

func _catmull(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)

func _nearest_index(x: float, z: float) -> int:
	var best := 1.0e20
	var best_i := 0
	for i in road_points.size():
		var p := road_points[i]
		var dx := p.x - x
		var dz := p.z - z
		var distance_sq := dx * dx + dz * dz
		if distance_sq < best:
			best = distance_sq
			best_i = i
	return best_i

func height_at(x: float, z: float) -> float:
	var index := _nearest_index(x, z)
	var p := road_points[index]
	var distance := Vector2(x, z).distance_to(Vector2(p.x, p.z))
	var weight := clampf((16.0 - distance) / 10.0, 0.0, 1.0)
	weight = weight * weight * (3.0 - 2.0 * weight)
	return lerpf(_base_height(x, z), p.y, weight)

func respawn_near(position: Vector3) -> Transform3D:
	var index := _nearest_index(position.x, position.z)
	# Don't spawn on the endpoints where the spline tangent may be degenerate.
	index = clampi(index, 1, road_points.size() - 2)
	var p := road_points[index]
	var direction := (road_points[index + 1] - road_points[index - 1]).normalized()
	direction.y = 0.0
	direction = direction.normalized()
	return Transform3D(Basis.looking_at(direction, Vector3.UP), p + Vector3.UP * 0.72)

func start_transform() -> Transform3D:
	return respawn_near(Vector3(-177, 0, 165))

func _build_terrain() -> void:
	var side := int(SIZE / CELL) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in range(side):
		var z := -SIZE * 0.5 + row * CELL
		for col in range(side):
			var x := -SIZE * 0.5 + col * CELL
			var y := height_at(x, z)
			vertices.append(Vector3(x, y, z))
			var slope_x := _base_height(x + 1.0, z) - _base_height(x - 1.0, z)
			var slope_z := _base_height(x, z + 1.0) - _base_height(x, z - 1.0)
			normals.append(Vector3(-slope_x, 2.0, -slope_z).normalized())
	for row in range(side - 1):
		for col in range(side - 1):
			var a := row * side + col
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var mesh := _array_mesh(vertices, normals, indices)
	var mat := _mat(Color(0.21, 0.34, 0.18), 0.92)
	_static_mesh("Grass", mesh, mat, true, "Grass")

func _build_road() -> void:
	# Dirt shoulder collision and asphalt collision are both real StaticBody3D.
	var shoulder := _ribbon_mesh(SHOULDER_WIDTH, 0.045, 0.0)
	_static_mesh("GradedShoulder", shoulder, _mat(Color(0.32, 0.28, 0.20), 0.95), true, "Dirt")
	var asphalt := _ribbon_mesh(ROAD_WIDTH, 0.13, 0.0)
	_static_mesh("PavedRoad", asphalt, _mat(Color(0.105, 0.116, 0.132), 0.84), true, "Road")
	_static_mesh("LeftEdge", _stripe_mesh(-3.95, false), _mat(Color(0.90, 0.89, 0.75), 0.63), false, "")
	_static_mesh("RightEdge", _stripe_mesh(3.95, false), _mat(Color(0.90, 0.89, 0.75), 0.63), false, "")
	_static_mesh("DashedCenter", _stripe_mesh(0.0, true), _mat(Color(0.93, 0.70, 0.17), 0.70), false, "")

func _tangent(index: int) -> Vector2:
	var previous := road_points[maxi(0, index - 1)]
	var following := road_points[mini(index + 1, road_points.size() - 1)]
	return Vector2(following.x - previous.x, following.z - previous.z).normalized()

func _offset_point(index: int, sideways: float, vertical: float) -> Vector3:
	var p := road_points[index]
	var tangent := _tangent(index)
	var right := Vector2(-tangent.y, tangent.x)
	return Vector3(p.x + right.x * sideways, p.y + vertical, p.z + right.y * sideways)

func _ribbon_mesh(width: float, vertical: float, offset: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in road_points.size():
		vertices.append(_offset_point(i, offset - width * 0.5, vertical))
		vertices.append(_offset_point(i, offset + width * 0.5, vertical))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in range(road_points.size() - 1):
		var a := i * 2
		indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	return _array_mesh(vertices, normals, indices)

func _stripe_mesh(offset: float, dashed: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(road_points.size() - 1):
		if dashed and i % 7 > 3:
			continue
		var a := _offset_point(i, offset - 0.065, 0.145)
		var b := _offset_point(i, offset + 0.065, 0.145)
		var c := _offset_point(i + 1, offset - 0.065, 0.145)
		var d := _offset_point(i + 1, offset + 0.065, 0.145)
		var base := vertices.size()
		vertices.append_array(PackedVector3Array([a, b, c, d]))
		for j in range(4):
			normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	return _array_mesh(vertices, normals, indices)

func _array_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _static_mesh(label: String, mesh: ArrayMesh, mat: Material, collision: bool, surface: String) -> void:
	var root := StaticBody3D.new()
	root.name = label
	root.collision_layer = 1
	root.collision_mask = 0
	if surface != "":
		root.add_to_group(surface)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	root.add_child(visual)
	if collision:
		var collider := CollisionShape3D.new()
		collider.shape = mesh.create_trimesh_shape()
		root.add_child(collider)
	add_child(root)

func _build_barriers() -> void:
	# High-speed outside of the hairpin; rails are collidable boxes.
	var rail_mat := _mat(Color(0.68, 0.70, 0.67), 0.52)
	for i in range(0, road_points.size(), 5):
		var p := road_points[i]
		if p.x < 153.0 or p.z < -143.0 or p.z > 10.0:
			continue
		var direction := _tangent(i)
		var edge := _offset_point(i, 6.65, 0.63)
		var length := 7.5
		var barrier := StaticBody3D.new()
		barrier.name = "Guardrail"
		barrier.collision_layer = 1
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.20, 0.80, length)
		var coll := CollisionShape3D.new()
		coll.shape = shape
		barrier.add_child(coll)
		var visual := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		visual.mesh = box
		visual.material_override = rail_mat
		barrier.add_child(visual)
		barrier.global_position = edge
		barrier.rotation.y = atan2(-direction.x, -direction.y)
		add_child(barrier)

func _build_trees() -> void:
	# Two instanced meshes per tree; no unlicensed texture/mesh files.
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	for i in range(330):
		var x := _rng.randf_range(-244.0, 244.0)
		var z := _rng.randf_range(-244.0, 244.0)
		var index := _nearest_index(x, z)
		var closest := road_points[index]
		if Vector2(x, z).distance_to(Vector2(closest.x, closest.z)) < 17.0:
			continue
		var y := height_at(x, z)
		var height := _rng.randf_range(4.0, 10.0)
		var scale := _rng.randf_range(0.8, 1.4)
		trunks.append(Transform3D(Basis().scaled(Vector3(scale, height * 0.30, scale)), Vector3(x, y + height * 0.15, z)))
		crowns.append(Transform3D(Basis().scaled(Vector3(scale * 2.1, height * 0.72, scale * 2.1)), Vector3(x, y + height * 0.59, z)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.20
	trunk.bottom_radius = 0.32
	trunk.height = 1.0
	_multimesh("ForestTrunks", trunk, _mat(Color(0.26, 0.18, 0.12), 1.0), trunks)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 0.72
	crown.height = 1.0
	_multimesh("ForestCanopies", crown, _mat(Color(0.09, 0.23, 0.17), 0.95), crowns)

func _multimesh(label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = mm
	visual.material_override = material
	add_child(visual)

func _build_signs() -> void:
	var post := _mat(Color(0.72, 0.73, 0.68), 0.75)
	var yellow := _mat(Color(0.91, 0.54, 0.10), 0.63)
	for i in range(0, road_points.size(), 18):
		var p := _offset_point(i, -7.0, 0.0)
		_decorative_box("MarkerPost", Vector3(0.20, 1.3, 0.20), p + Vector3.UP * 0.65, post)
		_decorative_box("Reflector", Vector3(0.30, 0.21, 0.09), p + Vector3.UP * 1.22, yellow)

func _decorative_box(label: String, size: Vector3, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)

func _build_boundary() -> void:
	# Solid invisible guard edges stop accidental falls beyond the heightfield.
	for edge in range(4):
		var bound := StaticBody3D.new()
		bound.name = "Boundary"
		bound.collision_layer = 1
		var box := BoxShape3D.new()
		box.size = Vector3(500, 16, 3) if edge < 2 else Vector3(3, 16, 500)
		var shape := CollisionShape3D.new()
		shape.shape = box
		bound.add_child(shape)
		match edge:
			0: bound.position = Vector3(0, 6, -251)
			1: bound.position = Vector3(0, 6, 251)
			2: bound.position = Vector3(-251, 6, 0)
			3: bound.position = Vector3(251, 6, 0)
		add_child(bound)

func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "ValleyAtmosphere"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.54, 0.70, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.67, 0.75, 0.84)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.rotation_degrees = Vector3(-44, -30, 0)
	sun.light_color = Color(1.0, 0.86, 0.69)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
