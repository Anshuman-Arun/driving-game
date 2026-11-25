extends Node3D
## Drop-in world root. Portable between this standalone project and the parent Godot game.
## No dependency on Terrain3D, Road Generator, core driving, traffic or racing classes.
signal world_built(report: Dictionary)
signal world_failed(reason: String)

## Source scripts are loaded using the current script's location, not project root.
## This also works when modules/world_runtime is embedded in the main Godot game.

@export_dir var world_data_directory: String = ""
@export var build_on_ready: bool = true
@export var build_full_world: bool = false
@export var preview_center_xz: Vector2 = Vector2(-620.0, 560.0)
@export_range(100.0, 1500.0, 10.0) var preview_radius_m: float = 460.0
@export_range(8, 128, 8) var terrain_chunk_cells: int = 32
@export var generate_colliders: bool = true
@export var terrain_material_override: Material
@export var asphalt_material_override: Material
@export var gravel_material_override: Material
@export var shoulder_material_override: Material

var roadworks: Dictionary = {}
var crossing_water_material: Material
var _canonical_heights := PackedFloat32Array()
var data = null
var report: Dictionary = {}
var error_message: String = ""
var generated_root: Node3D = null
var road_clearance: RefCounted

func _ready() -> void:
	if build_on_ready:
		build_world()

func discover_world_directory() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-data-dir="):
			return arg.trim_prefix("--world-data-dir=").strip_edges()
	if not world_data_directory.is_empty():
		return world_data_directory
	# Root-game integration, once World PR #3 has been merged.
	var game_root := "res://data/world"
	if FileAccess.file_exists(game_root.path_join("road_graph_v1.json")):
		return game_root
	# Standalone project: authoritative world data in a sibling repository root.
	var standalone_repo_root := ProjectSettings.globalize_path("res://").path_join("../../data/world").simplify_path()
	if FileAccess.file_exists(standalone_repo_root.path_join("road_graph_v1.json")):
		return standalone_repo_root
	# Optional local staging made from read-only feat/worldgen Git objects.
	var staged := ProjectSettings.globalize_path("res://.world_source")
	if FileAccess.file_exists(staged.path_join("road_graph_v1.json")):
		return staged
	return ""

func _local_dir() -> String:
	var script_res: Script = get_script()
	return script_res.resource_path.get_base_dir()

func build_world(directory_override: String = "") -> bool:
	error_message = ""
	report = {}
	road_clearance = null
	if generated_root != null and is_instance_valid(generated_root):
		remove_child(generated_root)
		generated_root.free()
		generated_root = null
	var directory: String = directory_override if not directory_override.is_empty() else discover_world_directory()
	var local_path: String = _local_dir()
	var loaded = load(local_path.path_join("world_data.gd")).new()
	if not loaded.load_directory(directory):
		data = null
		error_message = loaded.error_message
		world_failed.emit(error_message)
		return false
	_canonical_heights = PackedFloat32Array()
	if not roadworks.is_empty():
		_canonical_heights = loaded.height_samples.duplicate()
		if not loaded._decode_heightfield(directory.path_join("terrain_roadworks_r16le.bin")):
			data = null
			error_message = loaded.error_message
			world_failed.emit(error_message)
			return false
	data = loaded
	var full := build_full_world
	for arg in OS.get_cmdline_user_args():
		if arg == "--full-world":
			full = true
	var root := Node3D.new()
	root.name = "GeneratedWorld"
	add_child(root)
	generated_root = root
	var overrides := {}
	if terrain_material_override != null:
		overrides["terrain"] = terrain_material_override
	if asphalt_material_override != null:
		overrides["asphalt"] = asphalt_material_override
	if gravel_material_override != null:
		overrides["gravel"] = gravel_material_override
	if shoulder_material_override != null:
		overrides["shoulder"] = shoulder_material_override
	if not roadworks.is_empty():
		overrides["roadworks"] = roadworks
		overrides["crossing_water"] = crossing_water_material
	var builder = load(_local_dir().path_join("mesh_builder.gd")).new()
	report = builder.build(root, data, full, preview_center_xz,
		preview_radius_m, terrain_chunk_cells, generate_colliders, overrides)
	road_clearance = builder.clearance
	report["clearance_triangles"] = road_clearance.triangle_count
	report["source_directory"] = directory
	report["graph_lane_count"] = data.lanes.size()
	report["graph_road_count"] = data.roads.size()
	report["height_samples"] = data.height_samples.size()
	report["full_world"] = full
	report["engine_static_memory_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	print("[WorldRuntime] ", JSON.stringify(report))
	world_built.emit(report)
	return true

func get_road_graph() -> Dictionary:
	## Same untouched v1 directed-lane graph for traffic/racing systems.
	return data.graph if data != null else {}

func get_world_metadata() -> Dictionary:
	return data.metadata if data != null else {}

func get_height_at(x: float, z: float) -> float:
	return data.sample_height(x, z) if data != null else NAN

func get_authored_surface_height_at(x: float, z: float) -> float:
	return data.sample_surface_height(x, z, _canonical_heights) if data != null else NAN

func get_surface_height_at(x: float, z: float) -> float:
	return data.sample_surface_height(x, z) if data != null else NAN

func get_physical_road_centerlines() -> Array[Dictionary]:
	## Adapter for Godot Road Generator 0.9.5; one record per physical corridor.
	var corridors: Array[Dictionary] = []
	if data == null:
		return corridors
	var builder = load(_local_dir().path_join("mesh_builder.gd")).new()
	builder.source = data
	for road in data.roads:
		if not builder._is_physical_corridor(road):
			continue
		var line: PackedVector3Array = builder.corridor_points(road)
		var lane: Dictionary = data.lanes["lane_%s_ab" % road["id"]]
		corridors.append({
			"id": road["id"], "name": road.get("name", road["id"]),
			"region": road.get("region", ""), "points": line,
			"width_m": 2.0 * float(lane["width_m"]), "surface": lane["surface"],
			"target_pavement_width_m": float(roadworks.get("network_upgrade", {}).get("widths_m", {}).get(road["id"], 2.0 * float(lane["width_m"]))),
			"speed_limit_kph": lane["speed_limit_kph"]
		})
	return corridors

func create_height_image_rf() -> Image:
	## Terrain3D 1.1.0 integration hook: single-channel 32-bit float height image.
	## Native Terrain3D region import/padding must be performed in its editor tooling.
	if data == null:
		return null
	var img := Image.create_empty(data.grid_width, data.grid_height, false, Image.FORMAT_RF)
	for iz in range(data.grid_height):
		for ix in range(data.grid_width):
			var v: float = data.height_index(ix, iz)
			img.set_pixel(ix, iz, Color(v, 0.0, 0.0))
	return img
