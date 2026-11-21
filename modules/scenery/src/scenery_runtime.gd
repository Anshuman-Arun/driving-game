extends Node3D
## Data-driven Aster Valley scenery, independent of world/vehicle module implementation.
## Instantiate at identity world transform. World Runtime PR #16 can be passed read-only.
signal scenery_built(report: Dictionary)
signal scenery_failed(reason: String)

@export var build_on_ready: bool = false
@export var content_directory: String = ""
@export var world_data_directory: String = ""
@export var source_world_path: NodePath
@export var camera_path: NodePath
@export_enum("Low", "Medium", "High") var quality: int = 2
@export_range(64.0, 768.0, 16.0) var near_distance_m: float = 175.0
@export_range(192.0, 1200.0, 16.0) var far_distance_m: float = 470.0
@export var generate_selective_colliders: bool = true
@export var render_lake: bool = true

var report: Dictionary = {}
var error_message: String = ""
var _world: Node = null
var _terrain = null
var _source_dir: String = ""
var _content_dir: String = ""
var _generated: Node3D = null
var _cells: Array[Dictionary] = []
var _mesh_cache: Dictionary = {}
var _frame_accumulator: float = 0.0
var _camera: Camera3D = null

func _ready() -> void:
	if build_on_ready:
		build_scenery()

func _local_dir() -> String:
	var script_resource: Script = get_script()
	return script_resource.resource_path.get_base_dir()

func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()

func _discover_content_directory() -> String:
	if not content_directory.is_empty():
		return content_directory
	if FileAccess.file_exists(ProjectSettings.globalize_path("res://content/scenery/manifest.json")):
		return ProjectSettings.globalize_path("res://content/scenery")
	var sibling: String = _repo_root().path_join("content/scenery")
	if FileAccess.file_exists(sibling.path_join("manifest.json")):
		return sibling
	return ""

func _discover_world_directory() -> String:
	if not world_data_directory.is_empty():
		return world_data_directory
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-data-dir="):
			return arg.trim_prefix("--world-data-dir=")
	var in_game: String = ProjectSettings.globalize_path("res://data/world")
	if FileAccess.file_exists(in_game.path_join("world_metadata_v1.json")):
		return in_game
	var sibling: String = _repo_root().path_join("data/world")
	if FileAccess.file_exists(sibling.path_join("world_metadata_v1.json")):
		return sibling
	var staged: String = ProjectSettings.globalize_path("res://.world_source")
	if FileAccess.file_exists(staged.path_join("world_metadata_v1.json")):
		return staged
	return ""

func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "Cannot open " + path
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		error_message = "JSON error %s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()]
		return null
	return parser.data

func _fail(message: String) -> bool:
	error_message = message
	push_error("[SceneryRuntime] " + message)
	scenery_failed.emit(message)
	return false

func _reset() -> void:
	_cells.clear()
	_mesh_cache.clear()
	report = {}
	error_message = ""
	_terrain = null
	if _generated != null and is_instance_valid(_generated):
		remove_child(_generated)
		_generated.free()
	_generated = null

func build_scenery(world_runtime: Node = null, content_override: String = "", world_override: String = "") -> bool:
	_reset()
	_world = world_runtime
	if _world == null and not source_world_path.is_empty():
		_world = get_node_or_null(source_world_path)
	_content_dir = content_override if not content_override.is_empty() else _discover_content_directory()
	if _content_dir.is_empty():
		return _fail("Missing content/scenery. Use content_directory for standalone staging.")
	var raw: Variant = _read_json(_content_dir.path_join("manifest.json"))
	if not (raw is Dictionary):
		return _fail(error_message if not error_message.is_empty() else "Invalid scenery manifest")
	var manifest: Dictionary = raw
	if manifest.get("schema_version") != 1 or manifest.get("seed") != 20261121:
		return _fail("Scenery source contract or seed mismatch")
	var world_meta: Dictionary = {}
	if _world != null and _world.has_method("get_world_metadata") and _world.has_method("get_surface_height_at"):
		world_meta = _world.call("get_world_metadata")
	else:
		_source_dir = world_override if not world_override.is_empty() else _discover_world_directory()
		_terrain = load(_local_dir().path_join("scenery_terrain.gd")).new()
		if not _terrain.load_directory(_source_dir):
			return _fail(_terrain.error_message)
		world_meta = _terrain.metadata
	if world_meta.get("seed") != manifest.get("seed") or world_meta.get("regions", []).size() != 5:
		return _fail("World metadata does not match the five canonical scenery regions")
	var root := Node3D.new()
	root.name = "SceneryGenerated"
	add_child(root)
	_generated = root
	var grouped: Dictionary = {}
	var placements: int = 0
	var colliders: int = 0
	var skipped_by_quality: int = 0
	var height_mismatches: int = 0
	var assets: Dictionary = manifest.get("assets", {})
	for entry in manifest.get("region_packs", []):
		var region_id: String = str(entry.get("id", ""))
		var raw_pack: Variant = _read_json(_content_dir.path_join("packs").path_join(region_id + ".json"))
		if not (raw_pack is Dictionary):
			return _fail("Missing/invalid pack " + region_id)
		var pack: Dictionary = raw_pack
		if pack.get("region") != region_id or pack.get("seed") != 20261121:
			return _fail("Pack provenance mismatch for " + region_id)
		for raw_item in pack.get("placements", []):
			if not (raw_item is Dictionary):
				return _fail("Malformed scenery placement in " + region_id)
			var item: Dictionary = raw_item
			var asset_id: String = str(item.get("asset", ""))
			if not assets.has(asset_id):
				return _fail("Unknown scenery asset " + asset_id)
			var point: Array = item.get("position", [])
			if point.size() != 3:
				return _fail("Malformed placement position")
			var x: float = float(point[0])
			var y: float = float(point[1])
			var z: float = float(point[2])
			var surveyed_y: float = _surface_height(x, z)
			if not is_finite(surveyed_y):
				return _fail("Terrain source returned invalid height")
			if absf(y - (surveyed_y + float(item.get("terrain_offset_m", 0.0)))) > 0.105:
				height_mismatches += 1
				continue
			if not _quality_keeps(item):
				skipped_by_quality += 1
				continue
			var cell_x: int = int(floor(x / 128.0))
			var cell_z: int = int(floor(z / 128.0))
			var cell_key: String = "%d:%d:%s" % [cell_x, cell_z, asset_id]
			if not grouped.has(cell_key):
				grouped[cell_key] = {"asset": asset_id, "cell_x": cell_x, "cell_z": cell_z, "items": []}
			var adjusted: Dictionary = item.duplicate()
			adjusted["position"] = [x, surveyed_y + float(item.get("terrain_offset_m", 0.0)), z]
			grouped[cell_key]["items"].append(adjusted)
			placements += 1
			if generate_selective_colliders and _collidable_asset(asset_id):
				_add_collider(root, adjusted, asset_id)
				colliders += 1
	if height_mismatches > 0:
		return _fail("%d placements did not match authoritative surface height" % height_mismatches)
	var batches: int = 0
	var missing: Dictionary = {}
	for record in grouped.values():
		var asset_id: String = record["asset"]
		var desc: Dictionary = assets[asset_id]
		var scene_parts: Array = _get_mesh_parts(str(desc["path"]))
		if scene_parts.is_empty():
			missing[asset_id] = str(desc["path"])
			continue
		var cell_root := Node3D.new()
		cell_root.name = "%s_%d_%d" % [asset_id, int(record["cell_x"]), int(record["cell_z"])]
		root.add_child(cell_root)
		var items: Array = record["items"]
		var near_nodes: Array = _make_batches(cell_root, items, scene_parts, "Near")
		var far_nodes: Array = []
		var has_far: bool = desc.has("lod")
		if has_far:
			var far_parts: Array = _get_mesh_parts(str(desc["lod"]))
			if not far_parts.is_empty():
				far_nodes = _make_batches(cell_root, items, far_parts, "Far")
		batches += near_nodes.size() + far_nodes.size()
		var coord := Vector2((float(record["cell_x"]) + 0.5) * 128.0, (float(record["cell_z"]) + 0.5) * 128.0)
		_cells.append({"origin": coord, "asset": asset_id, "max_distance": float(desc.get("draw", 300.0)), "near": near_nodes, "far": far_nodes})
	var water_triangles: int = 0
	if render_lake:
		water_triangles = _build_lake(root, manifest)
		if water_triangles <= 0:
			return _fail("Could not construct contour-based lake")
	report = {
		"source_dir": _source_dir, "content_dir": _content_dir,
		"regions": manifest.get("region_packs", []).size(),
		"placements": placements, "skipped_quality": skipped_by_quality,
		"height_mismatches": height_mismatches, "selective_colliders": colliders,
		"chunk_asset_groups": _cells.size(), "mesh_component_batches": batches,
		"water_triangles": water_triangles, "missing_assets": missing.keys(),
		"quality": quality
	}
	print("[SceneryRuntime] ", JSON.stringify(report))
	_update_culling(true)
	scenery_built.emit(report)
	return true

func _quality_keeps(item: Dictionary) -> bool:
	if quality >= 2 or item.get("tag") == "landmark" or item.get("tag") == "streetwall":
		return true
	var threshold: int = 2 if quality == 0 else 3
	var value: int = int(str(item.get("id", "")).hash()) & 0x7fffffff
	return value % 4 < threshold

func _surface_height(x: float, z: float) -> float:
	if _world != null and _world.has_method("get_surface_height_at"):
		return float(_world.call("get_surface_height_at", x, z))
	if _terrain != null:
		return _terrain.sample_surface_height(x, z)
	return NAN

func _collidable_asset(asset: String) -> bool:
	return asset in ["house", "barn", "garage", "windmill", "arch", "overlook", "pier", "quarry", "guardrail", "barrier"]

func _add_collider(root: Node3D, item: Dictionary, asset: String) -> void:
	var dimensions := Vector3(6.0, 3.0, 6.0)
	if asset == "guardrail":
		dimensions = Vector3(4.0, 0.9, 0.5)
	elif asset == "barrier":
		dimensions = Vector3(3.0, 1.0, 0.8)
	elif asset == "house":
		dimensions = Vector3(12.0, 7.0, 9.0)
	elif asset == "barn":
		dimensions = Vector3(15.0, 8.0, 11.0)
	elif asset == "garage":
		dimensions = Vector3(14.0, 7.6, 10.0)
	elif asset == "windmill":
		dimensions = Vector3(5.0, 15.0, 5.0)
	elif asset == "arch":
		dimensions = Vector3(9.0, 6.0, 2.8)
	elif asset == "quarry":
		dimensions = Vector3(17.0, 9.0, 13.0)
	var point: Array = item["position"]
	var body := StaticBody3D.new()
	body.name = str(item["id"]) + "_Collision"
	body.position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	body.rotation.y = deg_to_rad(float(item.get("yaw_deg", 0.0)))
	body.scale = Vector3.ONE * float(item.get("scale", 1.0))
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = dimensions
	shape.shape = box_shape
	shape.position.y = dimensions.y * 0.5
	body.add_child(shape)

func _asset_path(relative: String) -> String:
	if relative.begins_with("assets/curated/"):
		var suffix: String = relative.trim_prefix("assets/curated/")
		var game_path: String = "res://assets/curated/" + suffix
		return game_path if ResourceLoader.exists(game_path) else "res://.art_source/" + suffix
	if relative.begins_with("content/scenery/models/"):
		var suffix: String = relative.trim_prefix("content/scenery/models/")
		var game_path: String = "res://content/scenery/models/" + suffix
		return game_path if ResourceLoader.exists(game_path) else "res://.models/" + suffix
	return ""

func _get_mesh_parts(relative: String) -> Array:
	if _mesh_cache.has(relative):
		return _mesh_cache[relative]
	var parts: Array = []
	var asset_path: String = _asset_path(relative)
	if not ResourceLoader.exists(asset_path):
		push_warning("[SceneryRuntime] Asset not imported: " + asset_path)
		_mesh_cache[relative] = parts
		return parts
	var resource: Resource = load(asset_path)
	if resource is PackedScene:
		var scene: Node = (resource as PackedScene).instantiate()
		_collect_meshes(scene, Transform3D.IDENTITY, parts)
		scene.free()
	elif resource is Mesh:
		parts.append({"mesh": resource, "local": Transform3D.IDENTITY})
	_mesh_cache[relative] = parts
	return parts

func _collect_meshes(node: Node, parent_transform: Transform3D, parts: Array) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		parts.append({"mesh": (node as MeshInstance3D).mesh, "local": transform})
	for child in node.get_children():
		_collect_meshes(child, transform, parts)

func _make_batches(parent: Node3D, items: Array, parts: Array, label: String) -> Array:
	var nodes: Array = []
	for k in range(parts.size()):
		var part: Dictionary = parts[k]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = part["mesh"]
		batch.instance_count = items.size()
		for i in range(items.size()):
			var item: Dictionary = items[i]
			var p: Array = item["position"]
			var angle: float = deg_to_rad(float(item.get("yaw_deg", 0.0)))
			var sc: float = float(item.get("scale", 1.0))
			var frame := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * sc), Vector3(float(p[0]), float(p[1]), float(p[2])))
			batch.set_instance_transform(i, frame * (part["local"] as Transform3D))
		var draw := MultiMeshInstance3D.new()
		draw.name = label + "_Part_" + str(k)
		draw.multimesh = batch
		parent.add_child(draw)
		nodes.append(draw)
	return nodes

func _build_lake(root: Node3D, manifest: Dictionary) -> int:
	var lake_any: Variant = manifest.get("lake")
	if not (lake_any is Dictionary):
		return 0
	var lake: Dictionary = lake_any
	var raw: Variant = _read_json(_content_dir.path_join("lake/water_cells_v1.json"))
	if not (raw is Dictionary):
		return 0
	var mask: Dictionary = raw
	if mask.get("schema_version") != 1:
		return 0
	var surface_y: float = float(lake.get("water_level_m", NAN))
	if absf(surface_y - float(mask.get("water_height_m", NAN))) > 0.0001:
		return 0
	var origin_x: float = float(mask.get("origin_x", -1000.0))
	var origin_z: float = float(mask.get("origin_z", -1000.0))
	var size_m: float = float(mask.get("spacing_m", 4.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris: int = 0
	for raw_cell in mask.get("cells", []):
		if not (raw_cell is Array) or raw_cell.size() != 2:
			return 0
		var x: float = origin_x + float(raw_cell[0]) * size_m
		var z: float = origin_z + float(raw_cell[1]) * size_m
		var a := Vector3(x, surface_y, z)
		var b := Vector3(x + size_m, surface_y, z)
		var c := Vector3(x, surface_y, z + size_m)
		var d := Vector3(x + size_m, surface_y, z + size_m)
		for pt in [a, c, b, b, c, d]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(pt.x / 24.0, pt.z / 24.0))
			st.add_vertex(pt)
		tris += 2
	var mesh: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.32, 0.39, 0.80)
	mat.metallic = 0.07
	mat.roughness = 0.17
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var surface := MeshInstance3D.new()
	surface.name = "EastwaterTerrainContouredWater"
	surface.mesh = mesh
	surface.material_override = mat
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(surface)
	return tris

func _process(delta: float) -> void:
	_frame_accumulator += delta
	if _frame_accumulator >= 0.25:
		_frame_accumulator = 0.0
		_update_culling(false)

func _update_culling(force: bool) -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null and get_viewport() != null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	var player_pos: Vector3 = _camera.global_position
	for c in _cells:
		var center: Vector2 = c["origin"]
		var d: float = Vector2(player_pos.x - center.x, player_pos.z - center.y).length()
		var asset_range: float = float(c["max_distance"])
		var near_visible: bool = d <= minf(asset_range, near_distance_m) + 96.0
		var far_visible: bool = not near_visible and d <= minf(asset_range, far_distance_m) + 96.0
		if not force and quality == 0 and d > far_distance_m + 256.0:
			near_visible = false
			far_visible = false
		for draw in c["near"]:
			(draw as MultiMeshInstance3D).visible = near_visible
		for draw in c["far"]:
			(draw as MultiMeshInstance3D).visible = far_visible
