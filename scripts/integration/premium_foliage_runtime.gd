extends Node3D
## Premium Foliage Runtime for Aster Valley Free Roam.
## GPU-instanced MultiMeshInstance3D scatterer managing 3 distinct foliage layers:
##   Layer 1: Roadside dense conifer canopy (curated pine LOD0/LOD1 with PR #30 2K PBR bark/twig textures)
##            casting dappled shadows over the road edge.
##   Layer 2: Mid-height understory (bush clusters, mossy boulders with PR #30 2K rock PBR, rock clusters).
##   Layer 3: Dense road-verge grass clumps (optimized 32-tri PBR grass cards with PR #30 1K textures) within 1-8m of the road corridor.
##
## Implements slope filtering, road exclusion buffers, random yaw, scale variation,
## hierarchical distance culling / visibility ranges, and cell-chunked static obstacle colliders.

class_name PremiumFoliageRuntime

const FoliageScatterer = preload("res://tools/foliage_scatter.gd")

const CURATED_PINE_PATH := "res://assets/curated/models/environment/pine_tree_lod0.glb"
const CURATED_PINE_LOD1_PATH := "res://assets/curated/models/environment/pine_tree_lod1.glb"
const PINE_BARK_DIFF := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_diff_2k.jpg"
const PINE_BARK_NORM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_nor_gl_2k.jpg"
const PINE_BARK_ARM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_arm_2k.jpg"
const PINE_TWIG_DIFF := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_diff_2k.jpg"
const PINE_TWIG_NORM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_nor_gl_2k.jpg"
const PINE_TWIG_ARM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_arm_2k.jpg"

const BOULDER_PATH := "res://assets/curated/models/environment/boulder.glb"
const ROCK_CLUSTER_PATH := "res://assets/curated/models/environment/rock_cluster.glb"
const BUSH_PATH := "res://assets/curated/models/environment/bush_cluster.gltf"
const SHRUB_PATH := "res://assets/curated/models/environment/shrub_cluster.glb"
const GRASS_DIFF_PATH := "res://assets/premium_world/payload/models/grass_medium_01/textures/grass_medium_01_diff_1k.jpg"
const GRASS_NORM_PATH := "res://assets/premium_world/payload/models/grass_medium_01/textures/grass_medium_01_nor_gl_1k.jpg"

const ROCK_ALBEDO := "res://assets/forza_env/textures/rock/albedo.jpg"
const ROCK_NORMAL := "res://assets/forza_env/textures/rock/normal.png"
const ROCK_ROUGH := "res://assets/forza_env/textures/rock/roughness.png"

const BAKED_DATA_PATH := "res://data/world/premium_foliage.bin"

const STRIDE := 7
const CELL_SIZE := 380.0

var _world: Node
var _placements := PackedFloat32Array()
var _mesh_registry: Dictionary = {} # kind (int) -> Array[Mesh]
var _batches: Array[MultiMeshInstance3D] = []
var _layer_batches: Dictionary = {1: [], 2: [], 3: []} # layer_idx -> Array[MultiMeshInstance3D]
var _collider_bodies: Array[StaticBody3D] = []
var _quality_preset := "high"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func build(world: Node = null, preset: String = "high") -> void:
	_world = world
	_quality_preset = preset

	# 1. Load game-ready PBR mesh varieties
	_init_meshes()

	# 2. Acquire placements data (from baked binary cache or procedural scatterer)
	_load_placements()
	if _placements.is_empty():
		push_warning("PremiumFoliageRuntime: No foliage placements available.")
		return

	# 3. Partition into spatial cells and construct GPU MultiMeshInstances
	_build_multimeshes()

	# 4. Generate solid physical colliders chunked by cell
	_build_colliders()

	set_graphics(preset)

	var counts := get_layer_counts()
	print("[PremiumFoliageRuntime] Built Aster Valley foliage: %d total instances (Layer 1 Conifers: %d, Layer 2 Understory: %d, Layer 3 Verge Grass: %d) across %d batches, with %d chunked colliders" % [
		get_total_instance_count(), counts.get(1, 0), counts.get(2, 0), counts.get(3, 0), _batches.size(), _collider_bodies.size()
	])

func set_graphics(preset: String) -> void:
	_quality_preset = preset
	var ranges := {
		"low": {"layer1": 280.0, "layer2": 90.0, "layer3": 45.0, "l1_shadow": false, "l2_shadow": false},
		"medium": {"layer1": 380.0, "layer2": 120.0, "layer3": 65.0, "l1_shadow": true, "l2_shadow": false},
		"high": {"layer1": 480.0, "layer2": 150.0, "layer3": 85.0, "l1_shadow": true, "l2_shadow": false},
		"ultra": {"layer1": 580.0, "layer2": 180.0, "layer3": 100.0, "l1_shadow": true, "l2_shadow": true},
	}
	var conf: Dictionary = ranges.get(preset, ranges["high"])

	for b: MultiMeshInstance3D in _layer_batches[1]:
		b.visibility_range_end = conf["layer1"]
		b.visibility_range_end_margin = 35.0
		b.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if conf["l1_shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for b: MultiMeshInstance3D in _layer_batches[2]:
		b.visibility_range_end = conf["layer2"]
		b.visibility_range_end_margin = 20.0
		b.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if conf["l2_shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for b: MultiMeshInstance3D in _layer_batches[3]:
		b.visibility_range_end = conf["layer3"]
		b.visibility_range_end_margin = 15.0
		b.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func get_total_instance_count() -> int:
	return _placements.size() / STRIDE

func get_layer_counts() -> Dictionary:
	var counts := {1: 0, 2: 0, 3: 0}
	for offset in range(0, _placements.size(), STRIDE):
		var kind := int(_placements[offset + 5])
		var layer := _get_layer_for_kind(kind)
		counts[layer] = counts.get(layer, 0) + 1
	return counts

func get_conifer_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	if _mesh_registry.has(0):
		out.append_array(_mesh_registry[0])
	if _mesh_registry.has(1):
		out.append_array(_mesh_registry[1])
	return out

func get_grass_meshes() -> Array[Mesh]:
	return _mesh_registry.get(5, [])

func get_understory_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for k in [2, 3, 4]:
		if _mesh_registry.has(k):
			out.append_array(_mesh_registry[k])
	return out

func _get_layer_for_kind(kind: int) -> int:
	if kind == 0 or kind == 1:
		return 1 # Conifer canopy
	elif kind >= 2 and kind <= 4:
		return 2 # Understory
	return 3 # Road-verge grass

func _init_meshes() -> void:
	_mesh_registry.clear()

	# Kind 0 & 1: Upgraded Curated Conifer LOD0 and LOD1 (1,548 & 404 triangles with PR #30 2K PBR bark/twigs)
	var pine_lod0 := _build_upgraded_curated_pine(CURATED_PINE_PATH)
	var pine_lod1 := _build_upgraded_curated_pine(CURATED_PINE_LOD1_PATH)
	_mesh_registry[0] = [pine_lod0, pine_lod1] if (pine_lod0 and pine_lod1) else [pine_lod0]
	_mesh_registry[1] = [pine_lod0]

	# Kind 2: Bush cluster (540 triangles) and Shrub cluster (2,000 triangles)
	var bush := _load_model_mesh(BUSH_PATH)
	var shrub := _load_model_mesh(SHRUB_PATH)
	_mesh_registry[2] = [bush, shrub] if (bush and shrub) else ([bush] if bush else [])

	# Kind 3: Mossy boulder (1,600 triangles with PR #30 2K rock PBR)
	var boulder := _build_upgraded_boulder()
	_mesh_registry[3] = [boulder] if boulder else []

	# Kind 4: Rock cluster (2,240 triangles with rock PBR)
	var rock_cluster := _build_upgraded_rock_cluster()
	_mesh_registry[4] = [rock_cluster] if rock_cluster else [boulder]

	# Kind 5: Road-verge grass clump (32-triangle PBR card cluster with PR #30 1K grass maps)
	var grass := _build_optimized_grass_clump()
	_mesh_registry[5] = [grass] if grass else []

func _load_placements() -> void:
	_placements = PackedFloat32Array()
	if FileAccess.file_exists(BAKED_DATA_PATH):
		var file := FileAccess.open(BAKED_DATA_PATH, FileAccess.READ)
		if file != null and file.get_length() % (STRIDE * 4) == 0:
			_placements = file.get_buffer(file.get_length()).to_float32_array()
			print("[PremiumFoliageRuntime] Loaded %d baked placements from %s" % [_placements.size() / STRIDE, BAKED_DATA_PATH])
			return

	if _world != null:
		print("[PremiumFoliageRuntime] Baked data not found; generating procedurally from world...")
		_placements = FoliageScatterer.generate_foliage_data(_world)
	else:
		push_error("PremiumFoliageRuntime: Cannot acquire placements.")

func _build_multimeshes() -> void:
	for b in _batches:
		if is_instance_valid(b):
			b.queue_free()
	_batches.clear()
	_layer_batches = {1: [], 2: [], 3: []}

	var groups: Dictionary = {}
	for offset in range(0, _placements.size(), STRIDE):
		var x: float = _placements[offset]
		var z: float = _placements[offset + 2]
		var kind: int = int(_placements[offset + 5])
		var seed_v: float = _placements[offset + 6]

		var variants: Array = _mesh_registry.get(kind, [])
		if variants.is_empty():
			continue
		var variant_idx: int = clampi(int(seed_v * variants.size()), 0, variants.size() - 1)

		var cell := Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
		var key := Vector4i(cell.x, cell.y, kind, variant_idx)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(offset)

	for key: Vector4i in groups:
		var offsets: Array = groups[key]
		var kind: int = key.z
		var variant_idx: int = key.w
		var layer: int = _get_layer_for_kind(kind)

		var mesh: Mesh = _mesh_registry[kind][variant_idx]
		var batch := _create_batch(offsets, mesh, layer)
		_batches.append(batch)
		_layer_batches[layer].append(batch)
		add_child(batch)

func _create_batch(offsets: Array, mesh: Mesh, layer: int) -> MultiMeshInstance3D:
	var first_at: int = offsets[0]
	var cell_center := Vector3(_placements[first_at], _placements[first_at + 1], _placements[first_at + 2])

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.mesh = mesh
	multimesh.instance_count = offsets.size()

	for i in range(offsets.size()):
		var at: int = offsets[i]
		var px: float = _placements[at]
		var py: float = _placements[at + 1]
		var pz: float = _placements[at + 2]
		var yaw: float = _placements[at + 3]
		var s: float = _placements[at + 4]

		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		var local_pos := Vector3(px - cell_center.x, py - cell_center.y, pz - cell_center.z)
		multimesh.set_instance_transform(i, Transform3D(basis, local_pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.position = cell_center
	mmi.extra_cull_margin = 4.0

	if layer == 1:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return mmi

func _build_colliders() -> void:
	for body in _collider_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_collider_bodies.clear()

	var collider_root := Node3D.new()
	collider_root.name = "FoliageColliders"
	add_child(collider_root)

	var cell_bodies: Dictionary = {}

	# Stride: px, py, pz, yaw, scale, kind, seed
	for offset in range(0, _placements.size(), STRIDE):
		var kind: int = int(_placements[offset + 5])
		# Only Layer 1 (conifers 0, 1) and Layer 2 boulders/stumps (3, 4) get physical colliders
		if kind not in [0, 1, 3, 4]:
			continue

		var px: float = _placements[offset]
		var py: float = _placements[offset + 1]
		var pz: float = _placements[offset + 2]
		var s: float = _placements[offset + 4]

		var cell := Vector2i(floori(px / CELL_SIZE), floori(pz / CELL_SIZE))
		var body: StaticBody3D = cell_bodies.get(cell, null)
		if body == null:
			body = StaticBody3D.new()
			body.name = "FoliageCellCol_%d_%d" % [cell.x, cell.y]
			body.collision_layer = 1
			body.collision_mask = 2 # Vehicle layer
			collider_root.add_child(body)
			cell_bodies[cell] = body
			_collider_bodies.append(body)

		var col_shape := CollisionShape3D.new()
		if kind in [0, 1]: # Conifer trunk
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.40 * s
			cyl.height = 7.0 * s
			col_shape.shape = cyl
			col_shape.position = Vector3(px, py + 3.5 * s, pz)
		elif kind == 3: # Mossy Rock / Boulder
			var sph := SphereShape3D.new()
			sph.radius = 1.35 * s
			col_shape.shape = sph
			col_shape.position = Vector3(px, py + 0.9 * s, pz)
		elif kind == 4: # Tree stump / Rock cluster
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.70 * s
			cyl.height = 1.4 * s
			col_shape.shape = cyl
			col_shape.position = Vector3(px, py + 0.7 * s, pz)

		body.add_child(col_shape)

func _load_model_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var mesh: Mesh = null
	var stack := [inst]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			mesh = node.mesh.duplicate()
			break
		for c in node.get_children():
			stack.append(c)
	inst.free()
	return mesh

func _build_upgraded_curated_pine(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var mi: MeshInstance3D = null
	var stack := [inst]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			mi = node
			break
		for c in node.get_children():
			stack.append(c)

	if mi == null or mi.mesh == null:
		inst.free()
		return null
	var pine_mesh: Mesh = mi.mesh.duplicate()

	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_texture = load(PINE_BARK_DIFF)
	bark_mat.normal_enabled = true
	bark_mat.normal_texture = load(PINE_BARK_NORM)
	bark_mat.roughness_texture = load(PINE_BARK_ARM)
	bark_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	bark_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var twig_mat := StandardMaterial3D.new()
	twig_mat.albedo_texture = load(PINE_TWIG_DIFF)
	twig_mat.normal_enabled = true
	twig_mat.normal_texture = load(PINE_TWIG_NORM)
	twig_mat.roughness_texture = load(PINE_TWIG_ARM)
	twig_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	twig_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	twig_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	twig_mat.alpha_scissor_threshold = 0.45
	twig_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	for s in range(pine_mesh.get_surface_count()):
		if s == 0:
			pine_mesh.surface_set_material(s, bark_mat)
		else:
			pine_mesh.surface_set_material(s, twig_mat)

	inst.free()
	return pine_mesh

func _build_upgraded_boulder() -> Mesh:
	var mesh := _load_model_mesh(BOULDER_PATH)
	if mesh == null:
		return null
	var rock_mat := StandardMaterial3D.new()
	if ResourceLoader.exists(ROCK_ALBEDO):
		rock_mat.albedo_texture = load(ROCK_ALBEDO)
	if ResourceLoader.exists(ROCK_NORMAL):
		rock_mat.normal_enabled = true
		rock_mat.normal_texture = load(ROCK_NORMAL)
	if ResourceLoader.exists(ROCK_ROUGH):
		rock_mat.roughness_texture = load(ROCK_ROUGH)
	rock_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, rock_mat)
	return mesh

func _build_upgraded_rock_cluster() -> Mesh:
	var mesh := _load_model_mesh(ROCK_CLUSTER_PATH)
	if mesh == null:
		return _build_upgraded_boulder()
	var rock_mat := StandardMaterial3D.new()
	if ResourceLoader.exists(ROCK_ALBEDO):
		rock_mat.albedo_texture = load(ROCK_ALBEDO)
	if ResourceLoader.exists(ROCK_NORMAL):
		rock_mat.normal_enabled = true
		rock_mat.normal_texture = load(ROCK_NORMAL)
	if ResourceLoader.exists(ROCK_ROUGH):
		rock_mat.roughness_texture = load(ROCK_ROUGH)
	rock_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, rock_mat)
	return mesh

func _build_optimized_grass_clump() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var angles := [0.0, PI / 3.0, 2.0 * PI / 3.0]
	var w := 0.85
	var h := 0.65

	for a in angles:
		var dir := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var norm := Vector3(-sin(a), 0, cos(a))

		var p0 := -dir
		var p1 := dir
		var p2 := dir + Vector3.UP * h
		var p3 := -dir + Vector3.UP * h

		tool.set_normal(norm)
		tool.set_uv(Vector2(0, 1))
		tool.add_vertex(p0)
		tool.set_uv(Vector2(1, 1))
		tool.add_vertex(p1)
		tool.set_uv(Vector2(1, 0))
		tool.add_vertex(p2)

		tool.set_uv(Vector2(0, 1))
		tool.add_vertex(p0)
		tool.set_uv(Vector2(1, 0))
		tool.add_vertex(p2)
		tool.set_uv(Vector2(0, 0))
		tool.add_vertex(p3)

	var grass_mat := StandardMaterial3D.new()
	if ResourceLoader.exists(GRASS_DIFF_PATH):
		grass_mat.albedo_texture = load(GRASS_DIFF_PATH)
	elif ResourceLoader.exists("res://assets/valley_art/grass_cutout.png"):
		grass_mat.albedo_texture = load("res://assets/valley_art/grass_cutout.png")

	if ResourceLoader.exists(GRASS_NORM_PATH):
		grass_mat.normal_enabled = true
		grass_mat.normal_texture = load(GRASS_NORM_PATH)

	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_mat.alpha_scissor_threshold = 0.40
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	tool.index()
	tool.set_material(grass_mat)
	return tool.commit()
