extends Node3D
## Visual-only, deterministic vegetation cells baked from the canonical world.

const FOLIAGE = preload("res://assets/valley_art/vegetation.gdshader")
const CARDS = preload("res://assets/valley_art/foliage_cards.gdshader")
const Trees = preload("valley_tree_factory.gd")
const PremiumMesh = preload("premium_mesh.gd")
const GRASS_ATLAS = preload("res://assets/valley_art/grass_cutout.png")
const LEAF_DETAIL = preload("res://assets/valley_art/leaf_litter_albedo.jpg")
const BARK = preload("res://assets/forza_env/textures/bark/albedo.jpg")
const BOULDER = preload("res://assets/curated/models/environment/boulder.glb")
const DATA_PATH := "res://data/world/vegetation.bin"
const STRIDE := 7
const CANOPY_CELL := 120.0
const GROUND_CELL := 48.0
const LEAF_COUNT := 28
const GROUND_RANGES := [75.0, 112.0, 144.0]

var _world: Node
var _placements := PackedFloat32Array()
var _ground: Dictionary = {}
var _visible_ground: Dictionary = {}
var _canopy: Dictionary = {}
var _meshes: Array[Mesh] = []
var _distant_trees: Array[Mesh] = []
var _ground_center := Vector2i(99999, 99999)
var _elapsed := 0.0
var _leaf_clock := 0.0
var _leaf_batch: MultiMesh
var _leaf_position := PackedVector3Array()
var _leaf_velocity := PackedVector3Array()
var _leaf_life := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _quality := 1
var clearance_report: Dictionary = {}
var _pilot_chunks: Dictionary = {}
var _pilot_bounds := Rect2()

func build(world: Node, preset: String) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_world = world
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null or file.get_length() % (STRIDE * 4) != 0:
		push_warning("Valley vegetation data could not be loaded.")
		return
	_placements = file.get_buffer(file.get_length()).to_float32_array()
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE
	material.set_shader_parameter("leaf_pattern", LEAF_DETAIL)
	_meshes = [
		Trees.build(true), Trees.build(false),
		_make_grass(_card_material(GRASS_ATLAS, 0.17, true)), _make_flowers(material), _rock_mesh(material),
	]
	var fern := PremiumMesh.fit("fern", Vector3(1.5, 0.92, 1.5))
	if fern != null:
		_meshes.append(fern)
	_distant_trees = [Trees.build(true, true), Trees.build(false, true)]
	_filter_placements()
	var cells: Dictionary = {}
	for offset in range(0, _placements.size(), STRIDE):
		var kind := int(_placements[offset + 5])
		var near_ground := kind in [2, 3, 5]
		var spacing := GROUND_CELL if near_ground else CANOPY_CELL
		var cell := Vector2i(floori(_placements[offset] / spacing), floori(_placements[offset + 2] / spacing))
		var key := Vector3i(cell.x, cell.y, kind)
		var buckets := _ground if near_ground else cells
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(offset)
	for key: Vector3i in cells:
		_canopy[key] = _make_batch(cells[key], key.z)
		if key.z < _distant_trees.size():
			_canopy[key].multimesh.mesh = _distant_trees[key.z]
	_rng.seed = 20261121
	set_graphics(preset)
	_build_leaves(material)
	print("Valley vegetation: %d placements, %d canopy batches, %d ground groups" % [_placements.size() / STRIDE, _canopy.size(), _ground.size()])
	print("[VegetationClearance] ", JSON.stringify(clearance_report))

func _filter_placements() -> void:
	var source := _placements
	_placements = PackedFloat32Array()
	_placements.resize(source.size())
	var kept := 0
	var blocked := [0, 0, 0, 0, 0, 0]
	var footprints: Array[AABB] = []
	for mesh in _meshes:
		footprints.append(mesh.get_aabb())
	for kind in _distant_trees.size():
		footprints[kind] = footprints[kind].merge(_distant_trees[kind].get_aabb())
	for offset in range(0, source.size(), STRIDE):
		var kind := int(source[offset + 5])
		var origin := Vector3(source[offset], source[offset + 1], source[offset + 2])
		if kind == 5 and _meshes.size() <= 5:
			kind = 3
		if kind == 3 and _meshes.size() > 5 and origin.x < -240.0 and origin.z < 180.0 and source[offset + 6] < 0.32:
			kind = 5
		var ground: float = _world.get_surface_height_at(origin.x, origin.z)
		if not is_finite(ground) or kind < 0 or kind >= footprints.size():
			continue
		origin.y = ground - (0.18 if kind < 2 else 0.04)
		var frame := _instance_frame(origin, source[offset + 3], source[offset + 4], source[offset + 6])
		var margin := 1.8 if kind < 2 or kind == 4 else 0.34
		if _world.road_clearance != null and _world.road_clearance.overlaps(frame * footprints[kind], margin):
			blocked[kind] += 1
			continue
		for field in STRIDE:
			_placements[kept + field] = source[offset + field]
		_placements[kept + 1] = ground
		_placements[kept + 5] = kind
		kept += STRIDE
	_placements.resize(kept)
	clearance_report = {"candidates": source.size() / STRIDE, "accepted": kept / STRIDE, "rejected_by_kind": blocked}

func _instance_frame(origin: Vector3, yaw: float, scale: float, seed: float) -> Transform3D:
	var form := Vector3(scale * lerpf(0.82, 1.24, seed), scale, scale * lerpf(1.17, 0.91, seed))
	return Transform3D(Basis(Vector3.UP, yaw).scaled(form), origin)

func conifer_mesh(distant := false) -> Mesh:
	if _meshes.is_empty():
		return null
	return _distant_trees[0] if distant else _meshes[0]

func broadleaf_mesh() -> Mesh:
	return _meshes[1] if not _meshes.is_empty() else null

func _card_material(atlas: Texture2D, wind: float, meadow := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CARDS
	material.set_shader_parameter("canopy", atlas)
	material.set_shader_parameter("bark", BARK)
	material.set_shader_parameter("wind", wind)
	material.set_shader_parameter("meadow", meadow)
	return material

func set_graphics(preset: String) -> void:
	_quality = 0 if preset == "low" else (2 if preset == "high" else 1)
	_ground_center = Vector2i(99999, 99999)
	for batch: MultiMeshInstance3D in _canopy.values():
		batch.visibility_range_end = [420.0, 580.0, 700.0][_quality]
		batch.visibility_range_end_margin = 55.0
	for batch: MultiMeshInstance3D in _visible_ground.values():
		batch.visibility_range_end = GROUND_RANGES[_quality]

func _make_batch(offsets: Array, kind: int) -> MultiMeshInstance3D:
	var center := Vector3(_placements[offsets[0]], 0, _placements[offsets[0] + 2])
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = _meshes[kind]
	mesh.instance_count = offsets.size()
	for index in offsets.size():
		var at: int = offsets[index]
		var base := Vector3(_placements[at], _placements[at + 1], _placements[at + 2])
		# Sink the roots slightly into hillsides without lowering roadside grass.
		base.y -= 0.18 if kind < 2 else 0.04
		var seed := _placements[at + 6]
		var scale := _placements[at + 4]
		mesh.set_instance_transform(index, _instance_frame(base - center, _placements[at + 3], scale, seed))
		var tint := Color(0.80, 0.95, 0.81).lerp(Color(1.10, 1.06, 0.83), seed)
		if kind == 0:
			tint = Color(0.64, 0.87, 0.76).lerp(Color(0.99, 1.08, 0.80), seed)
		elif kind == 1 and seed > 0.44:
			tint = Color(1.36, 0.88, 0.38).lerp(Color(1.80, 0.51, 0.24), seed)
		mesh.set_instance_color(index, tint)
	var draw := MultiMeshInstance3D.new()
	draw.multimesh = mesh
	draw.position = center
	draw.extra_cull_margin = 2.0
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)
	return draw

func _process(delta: float) -> void:
	if _meshes.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_elapsed += delta
	if _elapsed >= 0.18:
		_elapsed = 0.0
		_sync_cells(camera.global_position)
	_leaf_clock += delta
	if _leaf_clock >= 1.0 / 30.0:
		_update_leaves(camera, minf(_leaf_clock, 0.1))
		_leaf_clock = 0.0

func _sync_cells(position: Vector3) -> void:
	var center := Vector2i(floori(position.x / GROUND_CELL), floori(position.z / GROUND_CELL))
	var camera_xz := Vector2(position.x, position.z)
	var shadow_radius: float = [124.0, 190.0, 242.0][_quality]
	var shadow_radius_sq := shadow_radius * shadow_radius
	var detail_radius: float = [150.0, 210.0, 280.0][_quality]
	for key: Vector3i in _canopy:
		var middle := Vector2((key.x + 0.5) * CANOPY_CELL, (key.y + 0.5) * CANOPY_CELL)
		var distance := middle.distance_squared_to(camera_xz)
		var batch: MultiMeshInstance3D = _canopy[key]
		if key.z < _distant_trees.size():
			var multimesh := batch.multimesh
			var cutoff := detail_radius + (24.0 if multimesh.mesh == _meshes[key.z] else 0.0)
			var mesh := _meshes[key.z] if distance < cutoff * cutoff else _distant_trees[key.z]
			if multimesh.mesh != mesh:
				multimesh.mesh = mesh
		var shadow_mode := (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if distance < shadow_radius_sq
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if batch.cast_shadow != shadow_mode:
			batch.cast_shadow = shadow_mode
	if center == _ground_center:
		return
	_ground_center = center
	var radius := _quality + 1
	var wanted: Dictionary = {}
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			for species in [2, 3, 5]:
				var key := Vector3i(center.x + x, center.y + z, species)
				if not _ground.has(key):
					continue
				wanted[key] = true
				if not _visible_ground.has(key):
					var offsets: Array = _pilot_offsets(key)
					if offsets.is_empty():
						continue
					var batch := _make_batch(offsets, species)
					batch.visibility_range_end = GROUND_RANGES[_quality]
					batch.visibility_range_end_margin = 26.0
					_visible_ground[key] = batch
	for key: Vector3i in _visible_ground.keys():
		if not wanted.has(key):
			(_visible_ground[key] as Node3D).queue_free()
			_visible_ground.erase(key)

# A owns a cell only after its bounded job has published. Keep the original
# offsets and all other species unchanged; restore on eviction/failure.
func _pilot_offsets(key: Vector3i) -> Array:
	var source: Array = _ground.get(key, [])
	if key.z != 2 or _pilot_chunks.is_empty():
		return source
	var result: Array = []
	for offset: int in source:
		var pos := Vector2(_placements[offset], _placements[offset + 2])
		var chunk := Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))
		if not _pilot_bounds.has_point(pos) or not _pilot_chunks.has(chunk):
			result.append(offset)
	return result

func set_pilot_coverage(bounds: Rect2, chunks: Dictionary) -> void:
	if bounds == _pilot_bounds and chunks == _pilot_chunks:
		return
	var changed: Dictionary = {}
	for key: Vector2i in _pilot_chunks:
		if not chunks.has(key) or bounds != _pilot_bounds:
			changed[Vector3i(floori(float(key.x) / 3.0), floori(float(key.y) / 3.0), 2)] = true
	for key: Vector2i in chunks:
		if not _pilot_chunks.has(key) or bounds != _pilot_bounds:
			changed[Vector3i(floori(float(key.x) / 3.0), floori(float(key.y) / 3.0), 2)] = true
	_pilot_bounds = bounds
	_pilot_chunks = chunks.duplicate()
	var radius := _quality + 1
	for key: Vector3i in changed:
		if _visible_ground.has(key):
			var old: Node3D = _visible_ground[key]
			old.hide()
			old.queue_free()
			_visible_ground.erase(key)
		if abs(key.x - _ground_center.x) > radius or abs(key.y - _ground_center.y) > radius:
			continue
		var offsets := _pilot_offsets(key)
		if offsets.is_empty():
			continue
		var batch := _make_batch(offsets, 2)
		batch.visibility_range_end = GROUND_RANGES[_quality]
		batch.visibility_range_end_margin = 26.0
		_visible_ground[key] = batch

func _rock_mesh(material: ShaderMaterial) -> ArrayMesh:
	var asset := BOULDER.instantiate()
	var part: MeshInstance3D = asset if asset is MeshInstance3D else asset.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := part.mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in mesh.get_surface_count():
		var geometry := mesh.surface_get_arrays(layer)
		var positions: PackedVector3Array = geometry[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = geometry[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = geometry[Mesh.ARRAY_INDEX]
		var tint := Color("#706f60")
		for vertex in indices:
			var local := positions[vertex]
			var light := clampf(0.76 + local.y * 0.085 + sin((local.x + local.z) * 5.0) * 0.065, 0.66, 1.15)
			tool.set_color(Color(tint.r * light, tint.g * light, tint.b * light))
			tool.set_normal(normals[vertex])
			tool.set_uv(Vector2(-1, 0))
			tool.add_vertex(local)
	asset.free()
	tool.index()
	tool.set_material(material)
	return tool.commit()

func _make_grass(material: ShaderMaterial) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 48031
	for index in 7:
		var axis := Vector3.RIGHT.rotated(Vector3.UP, index * 2.39996)
		var base := axis.cross(Vector3.UP) * sqrt(random.randf()) * 1.38
		var width := random.randf_range(0.24, 0.47)
		var top := Vector3.UP * random.randf_range(0.12, 0.33) + axis.cross(Vector3.UP) * 0.09
		_card(tool, base - axis * width, base + axis * width,
			base - axis * width + top, base + axis * width + top, Color("#b3ac80").lerp(Color("#a4ac7f"), index / 6.0))
	for blade in 9:
		var along := Vector3.FORWARD.rotated(Vector3.UP, blade * 2.39996)
		var sideways := along.cross(Vector3.UP)
		var root := along * random.randf_range(0.2, 1.46)
		var height := random.randf_range(0.10, 0.28)
		var base_width := random.randf_range(0.022, 0.047)
		var tip := root + Vector3.UP * height + along * height * 0.77
		var tint := Color("#8d9257").lerp(Color("#afaf73"), random.randf())
		for point: Vector3 in [root - sideways * base_width, root + sideways * base_width, tip]:
			var flex := 1.0 if point == tip else 0.0
			tool.set_uv(Vector2(-2.0, flex))
			tool.set_normal(Vector3.UP)
			tool.set_color(Color(tint.r, tint.g, tint.b, flex))
			tool.add_vertex(point)
	tool.set_material(material)
	return tool.commit()

func _card(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, shade: Color, horizontal := false) -> void:
	var points := [a, b, c, d]
	var texels := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
	var normal := (c - a).cross(b - a).normalized().lerp(Vector3.UP, 0.60).normalized()
	for index in [0, 1, 2, 2, 1, 3]:
		var uv: Vector2 = texels[index]
		var flex := 1.0 - uv.y
		if horizontal:
			uv = Vector2(flex, 1.0 - uv.x)
		tool.set_uv(uv)
		tool.set_normal(normal)
		tool.set_color(Color(shade.r, shade.g, shade.b, flex))
		tool.add_vertex(points[index])

func _make_flowers(material: ShaderMaterial) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 11289
	for i in 13:
		var axis := Vector3.FORWARD.rotated(Vector3.UP, random.randf_range(0, TAU))
		var side := axis.cross(Vector3.UP)
		var root := axis * sqrt(random.randf()) * 0.92
		var height := random.randf_range(0.19, 0.72)
		var width := random.randf_range(0.018, 0.043)
		var half := root + Vector3.UP * height * 0.59 + axis * (height * 0.14)
		var tip := root + Vector3.UP * height + axis * (height * 0.76)
		var leaf_color := Color("#31553a").lerp(Color("#778448"), random.randf())
		_triangle(tool, root - side * width, root + side * width, half + side * width * 0.62, leaf_color, Vector3(0, 0, 0.54))
		_triangle(tool, root - side * width, half + side * width * 0.62, half - side * width * 0.62, leaf_color, Vector3(0, 0.54, 0.54))
		_triangle(tool, half - side * width * 0.62, half + side * width * 0.62, tip, leaf_color.lightened(0.12), Vector3(0.54, 0.54, 1))
		if i % 3 == 0:
			var bloom := half + Vector3.UP * height * 0.58
			var petals := Color("#ddcf97") if i % 2 == 0 else Color("#b4a2c7")
			_triangle(tool, half, half + side * 0.018, bloom, leaf_color, Vector3(0.54, 0.54, 1))
			for petal in 5:
				var ray := Vector3.FORWARD.rotated(Vector3.UP, petal * TAU / 5.0)
				var edge := ray.cross(Vector3.UP)
				_triangle(tool, bloom, bloom + ray * 0.10 + edge * 0.047, bloom + ray * 0.10 - edge * 0.047,
					petals, Vector3.ONE)
	tool.set_material(material)
	return tool.commit()

func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color, flex: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized().lerp(Vector3.UP, 0.37).normalized()
	for index in 3:
		var point: Vector3 = [a, b, c][index]
		tool.set_normal(normal)
		tool.set_color(tint * lerpf(0.70, 1.02, flex[index]))
		tool.set_uv(Vector2(0, flex[index]))
		tool.add_vertex(point)

func _build_leaves(material: ShaderMaterial) -> void:
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shape := [Vector3(0, 0, -0.13), Vector3(0.069, 0.010, -0.037), Vector3(0.056, 0.015, 0.055),
		Vector3(0, 0, 0.14), Vector3(-0.058, -0.004, 0.052), Vector3(-0.073, 0, -0.043)]
	for index in shape.size():
		var tint := Color("#bf8437") if index < 3 else Color("#986a37")
		_triangle(leaf, Vector3(0, 0.023, 0), shape[index], shape[(index + 1) % shape.size()], tint, Vector3.ZERO)
	leaf.set_material(material)
	_leaf_batch = MultiMesh.new()
	_leaf_batch.transform_format = MultiMesh.TRANSFORM_3D
	_leaf_batch.use_colors = true
	_leaf_batch.mesh = leaf.commit()
	_leaf_batch.instance_count = LEAF_COUNT
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = _leaf_batch
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(visual)
	_leaf_position.resize(LEAF_COUNT)
	_leaf_velocity.resize(LEAF_COUNT)
	_leaf_life.resize(LEAF_COUNT)
	_leaf_life.fill(-1.0)

func _update_leaves(camera: Camera3D, delta: float) -> void:
	var location := camera.global_position
	var tree_cell := Vector2i(floori(location.x / CANOPY_CELL), floori(location.z / CANOPY_CELL))
	var broadleaf: MultiMeshInstance3D = _canopy.get(Vector3i(tree_cell.x, tree_cell.y, 1))
	var target_count := (12 if _quality == 0 else LEAF_COUNT) if broadleaf != null and broadleaf.multimesh.instance_count >= 5 else 0
	var forward := -camera.global_basis.z.slide(Vector3.UP).normalized()
	for i in LEAF_COUNT:
		var lifetime := _leaf_life[i] - delta
		var position := _leaf_position[i]
		var velocity := _leaf_velocity[i]
		if lifetime <= 0.0 or position.distance_squared_to(location) > 40.0 * 40.0:
			lifetime = -1.0
			if i < target_count and _rng.randf() < delta * 0.62:
				position = location + forward * _rng.randf_range(7.0, 23.0) + forward.cross(Vector3.UP) * _rng.randf_range(-13, 13)
				position.y = float(_world.call("get_surface_height_at", position.x, position.z)) + _rng.randf_range(1.8, 5.5)
				if is_finite(position.y):
					velocity = Vector3(_rng.randf_range(0.12, 1.15), -0.22, _rng.randf_range(-0.2, 0.57))
					lifetime = _rng.randf_range(3.1, 5.6)
					_leaf_batch.set_instance_color(i, Color(1.0, _rng.randf_range(0.62, 1.05), _rng.randf_range(0.52, 0.98)))
		var appearance := Basis.IDENTITY.scaled(Vector3.ONE * 0.001)
		if lifetime > 0.0:
			var ground := float(_world.call("get_surface_height_at", position.x, position.z)) + 0.051
			if position.y > ground:
				velocity.y = maxf(velocity.y - 1.48 * delta, -2.05)
				position += (velocity + Vector3(sin(lifetime * 3.8 + i), 0, cos(lifetime * 2.3 - i)) * 0.64) * delta
			if position.y <= ground:
				position.y = ground
				lifetime = minf(lifetime, 0.85)
				velocity = Vector3.ZERO
			var tumble := Vector3(0.12, lifetime * 0.95 + i * 0.80, 0.0) if velocity.is_zero_approx() else Vector3(lifetime * 2.5, i, sin(lifetime * 3 + i) * 1.05)
			appearance = Basis.from_euler(tumble).scaled(Vector3.ONE * minf(1.0, lifetime * 2.0))
		_leaf_batch.set_instance_transform(i, Transform3D(appearance, position))
		_leaf_life[i] = lifetime
		_leaf_position[i] = position
		_leaf_velocity[i] = velocity
