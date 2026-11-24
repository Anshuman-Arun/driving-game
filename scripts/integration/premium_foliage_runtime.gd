extends Node3D
## Premium Foliage Runtime for Aster Valley Free Roam.
## GPU-instanced MultiMeshInstance3D scatterer managing 3 distinct foliage layers:
##   Layer 1: Roadside dense conifer canopy (fir_sapling_medium + curated conifer with PR #30 bark/twig textures)
##            casting dappled shadows over the road edge.
##   Layer 2: Mid-height understory (fern_02, mossy boulders rock_moss_set_02, deadwood tree_stump_02).
##   Layer 3: Dense road-verge grass clumps (grass_medium_01) within 1-8m of the road corridor.
##
## Implements slope filtering, road exclusion buffers, random yaw, scale variation,
## and hierarchical distance culling / visibility ranges.

class_name PremiumFoliageRuntime

const FoliageScatterer = preload("res://tools/foliage_scatter.gd")

const FIR_SAPLING_PATH := "res://assets/premium_world/payload/models/fir_sapling_medium/fir_sapling_medium_2k.gltf"
const CURATED_PINE_PATH := "res://assets/curated/models/environment/pine_tree_lod0.glb"
const PINE_BARK_DIFF := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_diff_2k.jpg"
const PINE_BARK_NORM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_nor_gl_2k.jpg"
const PINE_BARK_ARM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_bark_arm_2k.jpg"
const PINE_TWIG_DIFF := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_diff_2k.jpg"
const PINE_TWIG_NORM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_nor_gl_2k.jpg"
const PINE_TWIG_ARM := "res://assets/premium_world/payload/models/pine_tree_01/textures/pine_tree_01_twig_arm_2k.jpg"

const FERN_PATH := "res://assets/premium_world/payload/models/fern_02/fern_02_1k.gltf"
const ROCK_MOSS_PATH := "res://assets/premium_world/payload/models/rock_moss_set_02/rock_moss_set_02_2k.gltf"
const TREE_STUMP_PATH := "res://assets/premium_world/payload/models/tree_stump_02/tree_stump_02_1k.gltf"
const GRASS_MEDIUM_PATH := "res://assets/premium_world/payload/models/grass_medium_01/grass_medium_01_1k.gltf"
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

	# 1. Load or extract all PBR mesh varieties
	_init_meshes()

	# 2. Acquire placements data (from baked binary cache or procedural scatterer)
	_load_placements()
	if _placements.is_empty():
		push_warning("PremiumFoliageRuntime: No foliage placements available.")
		return

	# 3. Partition into spatial cells and construct GPU MultiMeshInstances
	_build_multimeshes()

	# 4. Generate solid physical colliders for roadside trees and boulders
	_build_colliders()

	set_graphics(preset)

	var counts := get_layer_counts()
	print("[PremiumFoliageRuntime] Built Aster Valley foliage: %d total instances (Layer 1 Conifers: %d, Layer 2 Understory: %d, Layer 3 Verge Grass: %d) across %d batches, with %d colliders" % [
		get_total_instance_count(), counts.get(1, 0), counts.get(2, 0), counts.get(3, 0), _batches.size(), _collider_bodies.size()
	])

func set_graphics(preset: String) -> void:
	_quality_preset = preset
	var ranges := {
		"low": {"layer1": 320.0, "layer2": 100.0, "layer3": 55.0, "l1_shadow": false, "l2_shadow": false},
		"medium": {"layer1": 420.0, "layer2": 140.0, "layer3": 75.0, "l1_shadow": true, "l2_shadow": false},
		"high": {"layer1": 520.0, "layer2": 180.0, "layer3": 95.0, "l1_shadow": true, "l2_shadow": true},
		"ultra": {"layer1": 650.0, "layer2": 220.0, "layer3": 115.0, "l1_shadow": true, "l2_shadow": true},
	}
	var conf: Dictionary = ranges.get(preset, ranges["ultra"])

	for b: MultiMeshInstance3D in _layer_batches[1]:
		b.visibility_range_end = conf["layer1"]
		b.visibility_range_end_margin = 45.0
		b.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if conf["l1_shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for b: MultiMeshInstance3D in _layer_batches[2]:
		b.visibility_range_end = conf["layer2"]
		b.visibility_range_end_margin = 25.0
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
	# Kind 0: fir_sapling_medium (3 LOD0 variations)
	_mesh_registry[0] = _load_gltf_meshes(FIR_SAPLING_PATH)

	# Kind 1: curated_pine upgraded with PR #30 2K bark & twig textures
	_mesh_registry[1] = [_build_upgraded_curated_pine()]

	# Kind 2: fern_02 (4 understory fern variations)
	_mesh_registry[2] = _load_gltf_meshes(FERN_PATH)

	# Kind 3: rock_moss_set_02 (mossy boulder variations)
	_mesh_registry[3] = _load_gltf_meshes(ROCK_MOSS_PATH, ["rock08", "rock10", "rock12"])

	# Kind 4: tree_stump_02 (deadwood stump variation)
	_mesh_registry[4] = _load_gltf_meshes(TREE_STUMP_PATH)

	# Kind 5: grass_medium_01 (prominent road-verge clumps: large, mid, tall)
	_mesh_registry[5] = _load_gltf_meshes(GRASS_MEDIUM_PATH, ["large", "mid", "tall"])

func _load_placements() -> void:
	_placements = PackedFloat32Array()
	# First check for baked binary file
	if FileAccess.file_exists(BAKED_DATA_PATH):
		var file := FileAccess.open(BAKED_DATA_PATH, FileAccess.READ)
		if file != null and file.get_length() % (STRIDE * 4) == 0:
			_placements = file.get_buffer(file.get_length()).to_float32_array()
			print("[PremiumFoliageRuntime] Loaded %d baked placements from %s" % [_placements.size() / STRIDE, BAKED_DATA_PATH])
			return

	# Fallback: Generate procedurally if WorldRuntime is provided
	if _world != null:
		print("[PremiumFoliageRuntime] Baked data not found; generating procedurally from world...")
		_placements = FoliageScatterer.generate_foliage_data(_world)
	else:
		push_error("PremiumFoliageRuntime: Cannot acquire placements (no baked file and no world runtime).")

func _build_multimeshes() -> void:
	for b in _batches:
		if is_instance_valid(b):
			b.queue_free()
	_batches.clear()
	_layer_batches = {1: [], 2: [], 3: []}

	# Bucket placements by cell and (kind, variant)
	# Cell key: Vector2i(x / CELL_SIZE, z / CELL_SIZE)
	# Group key: Vector4i(cell.x, cell.y, kind, variant_index)
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

	# Create MultiMeshInstance3D for each cell group
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

	# Layer 1 Conifers cast shadows over the road edge
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

	var added := 0
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

		var body := StaticBody3D.new()
		body.name = "FoliageCol_%d" % added
		body.collision_layer = 1
		body.collision_mask = 2 # Vehicle layer
		body.position = Vector3(px, py, pz)

		var col_shape := CollisionShape3D.new()
		if kind in [0, 1]: # Conifer trunk
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.40 * s
			cyl.height = 7.0 * s
			col_shape.shape = cyl
			col_shape.position.y = 3.5 * s
		elif kind == 3: # Mossy Rock / Boulder
			var sph := SphereShape3D.new()
			sph.radius = 1.35 * s
			col_shape.shape = sph
			col_shape.position.y = 0.9 * s
		elif kind == 4: # Tree stump
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.60 * s
			cyl.height = 1.2 * s
			col_shape.shape = cyl
			col_shape.position.y = 0.6 * s

		body.add_child(col_shape)
		collider_root.add_child(body)
		_collider_bodies.append(body)
		added += 1

func _load_gltf_meshes(res_path: String, name_filters: Array = []) -> Array[Mesh]:
	var out: Array[Mesh] = []
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var global_path := ProjectSettings.globalize_path(res_path)
	var err := doc.append_from_file(global_path, state)
	if err != OK:
		push_error("PremiumFoliageRuntime: Failed to load GLTF: " + res_path)
		return out
	var root := doc.generate_scene(state)
	if root == null:
		return out
	_collect_meshes(root, out, name_filters)
	root.free()
	return out

func _collect_meshes(node: Node, out: Array[Mesh], name_filters: Array = []) -> void:
	if node is MeshInstance3D and node.mesh:
		var match_filter := true
		if not name_filters.is_empty():
			match_filter = false
			for f: String in name_filters:
				if node.name.find(f) != -1:
					match_filter = true
					break
		if match_filter:
			out.append(node.mesh)
	for child in node.get_children():
		_collect_meshes(child, out, name_filters)

func _build_upgraded_curated_pine() -> Mesh:
	var packed := load(CURATED_PINE_PATH) as PackedScene
	if packed == null:
		push_error("PremiumFoliageRuntime: Could not load " + CURATED_PINE_PATH)
		return null
	var inst := packed.instantiate()
	var mi := inst.get_node_or_null("PineTreeLOD0") as MeshInstance3D
	if mi == null or mi.mesh == null:
		inst.free()
		return null
	var pine_mesh: Mesh = mi.mesh.duplicate()

	# Create upgraded StandardMaterial3D with PR #30 2K PBR textures
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

	# Surface 0: PineBark, Surfaces 1..3: PineNeedles
	pine_mesh.surface_set_material(0, bark_mat)
	pine_mesh.surface_set_material(1, twig_mat)
	pine_mesh.surface_set_material(2, twig_mat)
	pine_mesh.surface_set_material(3, twig_mat)

	inst.free()
	return pine_mesh
