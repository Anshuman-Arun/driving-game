extends Node3D
## Visual-only, deterministic multi-species vegetation cells with LOD switching,
## INSTANCE_CUSTOM variation, and frame-budgeted streaming.

const SHADER_TREE_BARK = preload("res://assets/environment_realism/shaders/tree_bark.gdshader")
const SHADER_TREE_FOLIAGE = preload("res://assets/environment_realism/shaders/tree_foliage.gdshader")
const SHADER_UNDERGROWTH_GRASS = preload("res://assets/environment_realism/shaders/undergrowth_grass.gdshader")
const SHADER_UNDERGROWTH_CUTOUT = preload("res://assets/environment_realism/shaders/undergrowth_cutout.gdshader")
const FOLIAGE_FALLBACK = preload("res://assets/valley_art/vegetation.gdshader")
const LEAF_DETAIL = preload("res://assets/valley_art/leaf_litter_albedo.jpg")
const BOULDER_FALLBACK = preload("res://assets/curated/models/environment/boulder.glb")
const Trees = preload("valley_tree_factory.gd")

const DATA_PATH := "res://data/world/vegetation.bin"
const STRIDE := 8
const CANOPY_CELL := 96.0
const MID_CELL := 64.0
const GROUND_CELL := 32.0
const LEAF_COUNT := 28
const MAX_BATCHES_PER_TICK := 5

const KIND_CONIFER_TALL := 0
const KIND_BROADLEAF_OAK := 1
const KIND_GRASS_MEADOW := 2
const KIND_WILDFLOWER := 3
const KIND_ROCK := 4
const KIND_CONIFER_MEDIUM := 5
const KIND_BROADLEAF_BIRCH := 6
const KIND_SAPLING_CONIFER := 7
const KIND_GRASS_SHORT := 8
const KIND_GRASS_TALL_VERGE := 9
const KIND_FERN := 10
const KIND_SHRUB_WOODLAND := 11

const TREE_KINDS := [
	KIND_CONIFER_TALL, KIND_BROADLEAF_OAK, KIND_CONIFER_MEDIUM,
	KIND_BROADLEAF_BIRCH, KIND_SAPLING_CONIFER,
]
const MID_KINDS := [KIND_ROCK, KIND_SHRUB_WOODLAND]
const GROUND_KINDS := [
	KIND_GRASS_SHORT, KIND_GRASS_MEADOW, KIND_GRASS_TALL_VERGE,
	KIND_FERN, KIND_WILDFLOWER,
]

const ASSET_PATHS := {
	KIND_CONIFER_TALL: [
		"res://assets/environment_realism/trees/conifer_tall_lod0.glb",
		"res://assets/environment_realism/trees/conifer_tall_lod1.glb",
		"res://assets/environment_realism/trees/conifer_tall_lod2.glb",
	],
	KIND_BROADLEAF_OAK: [
		"res://assets/environment_realism/trees/broadleaf_oak_lod0.glb",
		"res://assets/environment_realism/trees/broadleaf_oak_lod1.glb",
		"res://assets/environment_realism/trees/broadleaf_oak_lod2.glb",
	],
	KIND_CONIFER_MEDIUM: [
		"res://assets/environment_realism/trees/conifer_medium_lod0.glb",
		"res://assets/environment_realism/trees/conifer_medium_lod1.glb",
		"res://assets/environment_realism/trees/conifer_medium_lod2.glb",
	],
	KIND_BROADLEAF_BIRCH: [
		"res://assets/environment_realism/trees/broadleaf_birch_lod0.glb",
		"res://assets/environment_realism/trees/broadleaf_birch_lod1.glb",
		"res://assets/environment_realism/trees/broadleaf_birch_lod2.glb",
	],
	KIND_SAPLING_CONIFER: [
		"res://assets/environment_realism/trees/sapling_conifer_lod0.glb",
		"res://assets/environment_realism/trees/sapling_conifer_lod1.glb",
	],
	KIND_SHRUB_WOODLAND: [
		"res://assets/environment_realism/undergrowth/shrub_woodland_lod0.glb",
		"res://assets/environment_realism/undergrowth/shrub_woodland_lod1.glb",
	],
	KIND_ROCK: [
		"res://assets/environment_realism/undergrowth/rock_moss_lod0.glb",
		"res://assets/environment_realism/undergrowth/rock_moss_lod1.glb",
	],
	KIND_GRASS_SHORT: [
		"res://assets/environment_realism/undergrowth/grass_short_lod0.glb",
		"res://assets/environment_realism/undergrowth/grass_short_lod1.glb",
	],
	KIND_GRASS_MEADOW: [
		"res://assets/environment_realism/undergrowth/grass_meadow_lod0.glb",
		"res://assets/environment_realism/undergrowth/grass_meadow_lod1.glb",
	],
	KIND_GRASS_TALL_VERGE: [
		"res://assets/environment_realism/undergrowth/grass_tall_verge_lod0.glb",
		"res://assets/environment_realism/undergrowth/grass_tall_verge_lod1.glb",
	],
	KIND_FERN: [
		"res://assets/environment_realism/undergrowth/fern_lod0.glb",
		"res://assets/environment_realism/undergrowth/fern_lod1.glb",
	],
	KIND_WILDFLOWER: [
		"res://assets/environment_realism/undergrowth/wildflower_lod0.glb",
		"res://assets/environment_realism/undergrowth/wildflower_lod1.glb",
	],
}

var _world: Node
var _placements := PackedFloat32Array()
var _mid_cells: Dictionary = {}
var _visible_mid: Dictionary = {}
var _ground_cells: Dictionary = {}
var _visible_ground: Dictionary = {}
var _canopy: Dictionary = {}
var _lods: Dictionary = {} # kind -> Array[Mesh] ([lod0, lod1, ...])
var _white_tex: ImageTexture
var _flat_normal_tex: ImageTexture
var _last_sync_pos := Vector2(99999.0, 99999.0)
var _elapsed := 0.0
var _leaf_clock := 0.0
var _leaf_batch: MultiMesh
var _leaf_position := PackedVector3Array()
var _leaf_velocity := PackedVector3Array()
var _leaf_life := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _quality := 1

func build(world: Node, preset: String) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_world = world
	_init_fallback_textures()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null or file.get_length() % (STRIDE * 4) != 0:
		push_warning("Valley vegetation data could not be loaded.")
		return
	_placements = file.get_buffer(file.get_length()).to_float32_array()

	var canopy_buckets: Dictionary = {}
	for offset in range(0, _placements.size(), STRIDE):
		var kind := int(_placements[offset + 5])
		var px := _placements[offset]
		var pz := _placements[offset + 2]
		if kind in GROUND_KINDS:
			var key := Vector3i(floori(px / GROUND_CELL), floori(pz / GROUND_CELL), kind)
			if not _ground_cells.has(key):
				_ground_cells[key] = PackedInt32Array()
			(_ground_cells[key] as PackedInt32Array).append(offset)
		elif kind in MID_KINDS:
			var key := Vector3i(floori(px / MID_CELL), floori(pz / MID_CELL), kind)
			if not _mid_cells.has(key):
				_mid_cells[key] = PackedInt32Array()
			(_mid_cells[key] as PackedInt32Array).append(offset)
		else:
			var key := Vector3i(floori(px / CANOPY_CELL), floori(pz / CANOPY_CELL), kind)
			if not canopy_buckets.has(key):
				canopy_buckets[key] = PackedInt32Array()
			(canopy_buckets[key] as PackedInt32Array).append(offset)

	_load_all_species_lods()

	for key: Vector3i in canopy_buckets:
		var batch := _make_batch(canopy_buckets[key], key.z, 2)
		if batch != null:
			_canopy[key] = batch

	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = FOLIAGE_FALLBACK
	leaf_mat.set_shader_parameter("leaf_pattern", LEAF_DETAIL)
	_rng.seed = 20261121
	set_graphics(preset)
	_build_leaves(leaf_mat)
	print("Valley vegetation: %d placements, %d canopy batches, %d mid cells, %d ground cells" % [
		_placements.size() / STRIDE, _canopy.size(), _mid_cells.size(), _ground_cells.size()
	])

func conifer_mesh(distant := false) -> Mesh:
	var lods: Array = _lods.get(KIND_CONIFER_TALL, [])
	if lods.is_empty():
		return null
	return lods[mini(1, lods.size() - 1)] if distant else lods[0]

func broadleaf_mesh() -> Mesh:
	var lods: Array = _lods.get(KIND_BROADLEAF_OAK, [])
	return lods[0] if not lods.is_empty() else null

func set_graphics(preset: String) -> void:
	_quality = 0 if preset == "low" else (2 if preset == "high" else 1)
	_last_sync_pos = Vector2(99999.0, 99999.0)
	var tree_end: float = [460.0, 620.0, 760.0][_quality]
	var sapling_end: float = [200.0, 270.0, 340.0][_quality]
	for key: Vector3i in _canopy:
		var batch: MultiMeshInstance3D = _canopy[key]
		batch.visibility_range_end = sapling_end if key.z == KIND_SAPLING_CONIFER else tree_end
		batch.visibility_range_end_margin = 45.0 if key.z == KIND_SAPLING_CONIFER else 65.0
	var ground_end: float = [105.0, 140.0, 165.0][_quality]
	for batch: MultiMeshInstance3D in _visible_ground.values():
		batch.visibility_range_end = ground_end
		batch.visibility_range_end_margin = 20.0
	var mid_end: float = [160.0, 215.0, 265.0][_quality]
	for batch: MultiMeshInstance3D in _visible_mid.values():
		batch.visibility_range_end = mid_end
		batch.visibility_range_end_margin = 28.0

func _init_fallback_textures() -> void:
	var white_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white_img.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
	_white_tex = ImageTexture.create_from_image(white_img)
	var norm_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	norm_img.set_pixel(0, 0, Color(0.5, 0.5, 1.0, 1.0))
	_flat_normal_tex = ImageTexture.create_from_image(norm_img)

func _load_all_species_lods() -> void:
	for kind: int in ASSET_PATHS:
		var paths: Array = ASSET_PATHS[kind]
		var meshes: Array[Mesh] = []
		for lod_idx in paths.size():
			var p: String = paths[lod_idx]
			if ResourceLoader.exists(p):
				var built := _load_glb_mesh(p, kind, lod_idx)
				if built != null:
					meshes.append(built)
		if meshes.is_empty():
			if kind in [KIND_CONIFER_TALL, KIND_CONIFER_MEDIUM, KIND_SAPLING_CONIFER]:
				meshes = [Trees.build(true, false), Trees.build(true, true)]
			elif kind in [KIND_BROADLEAF_OAK, KIND_BROADLEAF_BIRCH]:
				meshes = [Trees.build(false, false), Trees.build(false, true)]
			elif kind == KIND_ROCK:
				var fallback := _load_glb_mesh("res://assets/curated/models/environment/boulder.glb", kind, 0)
				if fallback != null:
					meshes = [fallback]
		_lods[kind] = meshes

func _load_glb_mesh(path: String, kind: int, lod: int) -> ArrayMesh:
	var res := ResourceLoader.load(path)
	if res == null:
		return null
	if res is ArrayMesh:
		return _apply_species_shaders(res as ArrayMesh, kind, lod)
	if not (res is PackedScene):
		return null
	var scene: Node = (res as PackedScene).instantiate()
	var parts: Array = []
	_collect_mesh_parts(scene, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		scene.free()
		return null
	var out := ArrayMesh.new()
	for part in parts:
		var src: Mesh = part["mesh"]
		var xform: Transform3D = part["xform"]
		var has_xform := not xform.is_equal_approx(Transform3D.IDENTITY)
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			if has_xform:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in verts.size():
					verts[i] = xform * verts[i]
				arrays[Mesh.ARRAY_VERTEX] = verts
				if arrays[Mesh.ARRAY_NORMAL] != null:
					var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var nbasis := xform.basis.inverse().transposed()
					for i in norms.size():
						norms[i] = (nbasis * norms[i]).normalized()
					arrays[Mesh.ARRAY_NORMAL] = norms
			var mat: Material = src.surface_get_material(s)
			var surf_idx := out.get_surface_count()
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(surf_idx, _make_surface_material(mat, kind, lod, surf_idx))
	scene.free()
	return out

func _apply_species_shaders(src: ArrayMesh, kind: int, lod: int) -> ArrayMesh:
	for s in src.get_surface_count():
		src.surface_set_material(s, _make_surface_material(src.surface_get_material(s), kind, lod, s))
	return src

func _collect_mesh_parts(node: Node, parent_xform: Transform3D, parts: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		parts.append({"mesh": (node as MeshInstance3D).mesh, "xform": xform})
	for child in node.get_children():
		_collect_mesh_parts(child, xform, parts)

func _make_surface_material(src_mat: Material, kind: int, lod: int, surface_idx: int) -> Material:
	if kind == KIND_ROCK:
		return src_mat if src_mat != null else StandardMaterial3D.new()
	var base := src_mat as BaseMaterial3D
	var mat_name := src_mat.resource_name.to_lower() if src_mat != null else ""
	var is_tree_or_shrub := kind in TREE_KINDS or kind == KIND_SHRUB_WOODLAND
	var sm := ShaderMaterial.new()
	if is_tree_or_shrub:
		var is_foliage := (
			surface_idx > 0
			or "foliage" in mat_name or "canopy" in mat_name or "leaf" in mat_name
			or "needle" in mat_name or "bough" in mat_name or "spray" in mat_name
			or (base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
		)
		sm.shader = SHADER_TREE_FOLIAGE if is_foliage else SHADER_TREE_BARK
		if kind == KIND_SHRUB_WOODLAND:
			sm.set_shader_parameter("wind_strength", 0.055)
			if is_foliage:
				sm.set_shader_parameter("leaf_flutter", 0.018)
		elif kind == KIND_SAPLING_CONIFER:
			sm.set_shader_parameter("wind_strength", 0.065)
	else:
		var is_opaque_grass := (kind == KIND_GRASS_SHORT or kind == KIND_GRASS_MEADOW) and lod == 0
		sm.shader = SHADER_UNDERGROWTH_GRASS if is_opaque_grass else SHADER_UNDERGROWTH_CUTOUT
		if not is_opaque_grass:
			sm.set_shader_parameter("alpha_scissor", 0.38 if lod == 0 else 0.34)
			sm.set_shader_parameter("alpha_scissor_far", 0.20)
		if kind == KIND_FERN:
			sm.set_shader_parameter("wind_strength", 0.095)
			sm.set_shader_parameter("backlight_strength", 0.38)
		elif kind == KIND_WILDFLOWER:
			sm.set_shader_parameter("wind_strength", 0.11)
			sm.set_shader_parameter("dry_tint", Vector3(1.06, 1.0, 0.88))

	if base != null:
		sm.set_shader_parameter("albedo_tex", base.albedo_texture if base.albedo_texture != null else _white_tex)
		sm.set_shader_parameter("normal_tex", base.normal_texture if base.normal_texture != null else _flat_normal_tex)
		sm.set_shader_parameter("roughness_tex", base.roughness_texture if base.roughness_texture != null else _white_tex)
		sm.set_shader_parameter("ao_tex", base.ao_texture if base.ao_texture != null else _white_tex)
	else:
		sm.set_shader_parameter("albedo_tex", _white_tex)
		sm.set_shader_parameter("normal_tex", _flat_normal_tex)
		sm.set_shader_parameter("roughness_tex", _white_tex)
		sm.set_shader_parameter("ao_tex", _white_tex)
	return sm

func _get_lod_mesh(kind: int, lod: int) -> Mesh:
	var lods: Array = _lods.get(kind, [])
	if lods.is_empty():
		return null
	return lods[clampi(lod, 0, lods.size() - 1)]

func _make_batch(offsets: PackedInt32Array, kind: int, initial_lod: int) -> MultiMeshInstance3D:
	var mesh_res := _get_lod_mesh(kind, initial_lod)
	if mesh_res == null or offsets.is_empty():
		return null
	var center := Vector3(_placements[offsets[0]], 0.0, _placements[offsets[0] + 2])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh_res
	mm.instance_count = offsets.size()

	var is_tree := kind in TREE_KINDS
	for index in offsets.size():
		var at: int = offsets[index]
		var base := Vector3(_placements[at], _placements[at + 1], _placements[at + 2])
		var yaw := _placements[at + 3]
		var scale := _placements[at + 4]
		var seed := _placements[at + 6]
		var warmth := _placements[at + 7]
		var form := Vector3(scale * lerpf(0.90, 1.12, seed), scale, scale * lerpf(1.10, 0.90, seed))
		if kind == KIND_ROCK:
			form = Vector3(scale * lerpf(0.85, 1.25, seed), scale * lerpf(0.75, 1.10, warmth), scale * lerpf(1.18, 0.86, seed))
		mm.set_instance_transform(index, Transform3D(Basis(Vector3.UP, yaw).scaled(form), base - center))

		# Keep instance_color.a = 1.0 so vertex COLOR.a wind flex is never attenuated!
		var tint := Color(0.90, 0.92, 0.87, 1.0).lerp(Color(1.08, 1.04, 0.94, 1.0), seed)
		if kind == KIND_ROCK:
			tint = Color(0.74, 0.77, 0.72, 1.0).lerp(Color(0.92, 0.93, 0.88, 1.0), seed)
		elif is_tree and kind in [KIND_BROADLEAF_OAK, KIND_BROADLEAF_BIRCH] and seed > 0.72:
			tint = Color(1.08, 0.96, 0.78, 1.0)
		mm.set_instance_color(index, tint)

		var stiffness := lerpf(0.25, 0.85, clampf(1.25 - scale * 0.5, 0.0, 1.0))
		var root_ao := lerpf(0.55, 1.0, seed)
		mm.set_instance_custom_data(index, Color(seed, stiffness, warmth, root_ao))

	var draw := MultiMeshInstance3D.new()
	draw.multimesh = mm
	draw.position = center
	draw.extra_cull_margin = 3.0 if is_tree else 1.5
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)
	return draw

func _process(delta: float) -> void:
	if _lods.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_elapsed += delta
	if _elapsed >= 0.06:
		_elapsed = 0.0
		_sync_cells(camera.global_position)
	_leaf_clock += delta
	if _leaf_clock >= 1.0 / 30.0:
		_update_leaves(camera, minf(_leaf_clock, 0.1))
		_leaf_clock = 0.0

func _sync_cells(cam_pos: Vector3) -> void:
	var cam_xz := Vector2(cam_pos.x, cam_pos.z)
	var lod1_r: float = [95.0, 130.0, 165.0][_quality]
	var lod2_r: float = [200.0, 260.0, 320.0][_quality]
	var shadow_tree_r_sq: float = pow([125.0, 185.0, 235.0][_quality], 2.0)
	var shadow_sap_r_sq: float = pow([65.0, 90.0, 115.0][_quality], 2.0)

	# 1. Canopy LOD + shadow distance hysteresis
	for key: Vector3i in _canopy:
		var middle := Vector2((key.x + 0.5) * CANOPY_CELL, (key.y + 0.5) * CANOPY_CELL)
		var dist_sq := middle.distance_squared_to(cam_xz)
		var batch: MultiMeshInstance3D = _canopy[key]
		var mm := batch.multimesh
		var lods: Array = _lods.get(key.z, [])
		if lods.size() >= 2:
			var cur_mesh := mm.mesh
			var c1 := lod1_r + (14.0 if cur_mesh == lods[0] else -14.0)
			var target_lod := 0 if dist_sq < c1 * c1 else 1
			if lods.size() >= 3 and target_lod == 1:
				var c2 := lod2_r + (18.0 if cur_mesh == lods[1] else -18.0)
				if dist_sq >= c2 * c2:
					target_lod = 2
			var target_mesh: Mesh = lods[mini(target_lod, lods.size() - 1)]
			if cur_mesh != target_mesh:
				mm.mesh = target_mesh
		var s_sq := shadow_sap_r_sq if key.z == KIND_SAPLING_CONIFER else shadow_tree_r_sq
		var s_mode := (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if dist_sq < s_sq
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if batch.cast_shadow != s_mode:
			batch.cast_shadow = s_mode

	# 2. Stream Mid cells (shrubs & rocks) and Ground cells (grass, ferns, wildflowers)
	var mid_load_r: float = [155.0, 210.0, 260.0][_quality]
	var mid_unload_r_sq := pow(mid_load_r + 32.0, 2.0)
	var mid_lod1_r: float = [52.0, 72.0, 92.0][_quality]
	var mid_shadow_r_sq := pow([60.0, 85.0, 110.0][_quality], 2.0)
	var rock_shadow_r_sq := pow([110.0, 160.0, 210.0][_quality], 2.0)

	var ground_load_r: float = [105.0, 140.0, 165.0][_quality]
	var ground_unload_r_sq := pow(ground_load_r + 24.0, 2.0)
	var ground_lod1_r: float = [34.0, 44.0, 54.0][_quality]

	# Unload far cells first
	for key: Vector3i in _visible_mid.keys():
		var middle := Vector2((key.x + 0.5) * MID_CELL, (key.y + 0.5) * MID_CELL)
		var dist_sq := middle.distance_squared_to(cam_xz)
		if dist_sq > mid_unload_r_sq:
			(_visible_mid[key] as Node3D).queue_free()
			_visible_mid.erase(key)
		else:
			var batch: MultiMeshInstance3D = _visible_mid[key]
			var lods: Array = _lods.get(key.z, [])
			if lods.size() >= 2:
				var cutoff: float = mid_lod1_r + (10.0 if batch.multimesh.mesh == lods[0] else -10.0)
				var target: Mesh = lods[0] if dist_sq < cutoff * cutoff else lods[1]
				if batch.multimesh.mesh != target:
					batch.multimesh.mesh = target
			var sh_sq := rock_shadow_r_sq if key.z == KIND_ROCK else mid_shadow_r_sq
			var sm := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if dist_sq < sh_sq else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if batch.cast_shadow != sm:
				batch.cast_shadow = sm

	for key: Vector3i in _visible_ground.keys():
		var middle := Vector2((key.x + 0.5) * GROUND_CELL, (key.y + 0.5) * GROUND_CELL)
		var dist_sq := middle.distance_squared_to(cam_xz)
		if dist_sq > ground_unload_r_sq:
			(_visible_ground[key] as Node3D).queue_free()
			_visible_ground.erase(key)
		else:
			var batch: MultiMeshInstance3D = _visible_ground[key]
			var lods: Array = _lods.get(key.z, [])
			if lods.size() >= 2:
				var cutoff: float = ground_lod1_r + (6.0 if batch.multimesh.mesh == lods[0] else -6.0)
				var target: Mesh = lods[0] if dist_sq < cutoff * cutoff else lods[1]
				if batch.multimesh.mesh != target:
					batch.multimesh.mesh = target

	# Queue missing near cells sorted closest-first, capped per tick to avoid frame hitches
	var pending: Array = []
	var mid_center := Vector2i(floori(cam_pos.x / MID_CELL), floori(cam_pos.z / MID_CELL))
	var mid_grid_r := ceili(mid_load_r / MID_CELL) + 1
	var mid_load_r_sq := mid_load_r * mid_load_r
	for gz in range(mid_center.y - mid_grid_r, mid_center.y + mid_grid_r + 1):
		for gx in range(mid_center.x - mid_grid_r, mid_center.x + mid_grid_r + 1):
			var middle := Vector2((gx + 0.5) * MID_CELL, (gz + 0.5) * MID_CELL)
			var dist_sq := middle.distance_squared_to(cam_xz)
			if dist_sq > mid_load_r_sq:
				continue
			for kind: int in MID_KINDS:
				var key := Vector3i(gx, gz, kind)
				if _mid_cells.has(key) and not _visible_mid.has(key):
					pending.append({"dist_sq": dist_sq, "key": key, "is_mid": true})

	var grd_center := Vector2i(floori(cam_pos.x / GROUND_CELL), floori(cam_pos.z / GROUND_CELL))
	var grd_grid_r := ceili(ground_load_r / GROUND_CELL) + 1
	var ground_load_r_sq := ground_load_r * ground_load_r
	for gz in range(grd_center.y - grd_grid_r, grd_center.y + grd_grid_r + 1):
		for gx in range(grd_center.x - grd_grid_r, grd_center.x + grd_grid_r + 1):
			var middle := Vector2((gx + 0.5) * GROUND_CELL, (gz + 0.5) * GROUND_CELL)
			var dist_sq := middle.distance_squared_to(cam_xz)
			if dist_sq > ground_load_r_sq:
				continue
			for kind: int in GROUND_KINDS:
				var key := Vector3i(gx, gz, kind)
				if _ground_cells.has(key) and not _visible_ground.has(key):
					pending.append({"dist_sq": dist_sq, "key": key, "is_mid": false})

	if pending.is_empty():
		return
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist_sq"] < b["dist_sq"])
	var budget := MAX_BATCHES_PER_TICK if _last_sync_pos.x < 90000.0 else pending.size()
	_last_sync_pos = cam_xz
	var ground_end: float = [105.0, 140.0, 165.0][_quality]
	var mid_end: float = [160.0, 215.0, 265.0][_quality]
	for i in mini(budget, pending.size()):
		var item: Dictionary = pending[i]
		var key: Vector3i = item["key"]
		var d_sq: float = item["dist_sq"]
		if item["is_mid"]:
			var lod := 0 if d_sq < mid_lod1_r * mid_lod1_r else 1
			var batch := _make_batch(_mid_cells[key], key.z, lod)
			if batch != null:
				batch.visibility_range_end = mid_end
				batch.visibility_range_end_margin = 28.0
				_visible_mid[key] = batch
		else:
			var lod := 0 if d_sq < ground_lod1_r * ground_lod1_r else 1
			var batch := _make_batch(_ground_cells[key], key.z, lod)
			if batch != null:
				batch.visibility_range_end = ground_end
				batch.visibility_range_end_margin = 20.0
				_visible_ground[key] = batch

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
	var oak: MultiMeshInstance3D = _canopy.get(Vector3i(tree_cell.x, tree_cell.y, KIND_BROADLEAF_OAK))
	var birch: MultiMeshInstance3D = _canopy.get(Vector3i(tree_cell.x, tree_cell.y, KIND_BROADLEAF_BIRCH))
	var count_oak := oak.multimesh.instance_count if oak != null else 0
	var count_birch := birch.multimesh.instance_count if birch != null else 0
	var target_count := (12 if _quality == 0 else LEAF_COUNT) if (count_oak + count_birch) >= 4 else 0
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
