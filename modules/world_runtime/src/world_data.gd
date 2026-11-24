extends RefCounted
## Read-only adapter for the World Agent's road_graph_v1.json and R16 heightfield.
## Units are meters; X/Z origin is taken strictly from world_metadata_v1.json.

var metadata: Dictionary = {}
var graph: Dictionary = {}
var roads: Array = []
var lanes: Dictionary = {}
var height_samples: PackedFloat32Array = PackedFloat32Array()
var grid_width: int = 0
var grid_height: int = 0
var spacing_m: float = 0.0
var origin_x: float = 0.0
var origin_z: float = 0.0
var error_message: String = ""
var source_directory: String = ""

func load_directory(directory: String) -> bool:
	error_message = ""
	metadata = {}
	graph = {}
	roads.clear()
	lanes.clear()
	height_samples = PackedFloat32Array()
	source_directory = directory
	if directory.is_empty():
		return _fail("World data directory is empty. Set world_data_directory or --world-data-dir=PATH.")
	var raw_meta: Variant = _read_json(directory.path_join("world_metadata_v1.json"))
	if not (raw_meta is Dictionary):
		return false
	var raw_graph: Variant = _read_json(directory.path_join("road_graph_v1.json"))
	if not (raw_graph is Dictionary):
		return false
	metadata = raw_meta
	graph = raw_graph
	if not _validate_metadata():
		return false
	if not _decode_heightfield(directory.path_join("terrain_height_r16le.bin")):
		return false
	if not _validate_graph():
		return false
	return true

func _read_json(path: String) -> Variant:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		_fail("Cannot open %s (FileAccess error %d)" % [path, FileAccess.get_open_error()])
		return null
	var parser := JSON.new()
	var result: int = parser.parse(handle.get_as_text())
	if result != OK:
		_fail("Invalid JSON at %s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	if not (parser.data is Dictionary):
		_fail("Expected a JSON object in %s" % path)
		return null
	return parser.data

func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT

func _validate_metadata() -> bool:
	if metadata.get("schema_version") != 1 or metadata.get("coordinate_system") != "godot_y_up":
		return _fail("Metadata must be schema_version=1, coordinate_system=godot_y_up.")
	var h: Variant = metadata.get("heightfield")
	var b: Variant = metadata.get("bounds")
	if not (h is Dictionary) or not (b is Dictionary):
		return _fail("Metadata missing heightfield or bounds object.")
	for key in ["sample_width", "sample_height", "spacing_m", "origin_x", "origin_z", "scale_m_per_unit", "offset_m"]:
		if not h.has(key) or not _is_number(h[key]):
			return _fail("Invalid numeric heightfield field: %s" % key)
	for key in ["min_x", "max_x", "min_z", "max_z"]:
		if not b.has(key) or not _is_number(b[key]):
			return _fail("Invalid world bound: %s" % key)
	if h.get("format") != "uint16_le" or h.get("row_order") != "z_ascending_x_ascending":
		return _fail("Only uint16_le, z_ascending_x_ascending R16 rasters are supported.")
	if h.get("path") != "data/world/terrain_height_r16le.bin":
		return _fail("Unexpected heightfield path in world metadata.")
	grid_width = int(h["sample_width"])
	grid_height = int(h["sample_height"])
	spacing_m = float(h["spacing_m"])
	origin_x = float(h["origin_x"])
	origin_z = float(h["origin_z"])
	if grid_width < 2 or grid_height < 2 or grid_width > 8192 or grid_height > 8192:
		return _fail("Invalid heightfield dimensions: %dx%d" % [grid_width, grid_height])
	if spacing_m <= 0.0 or float(h["scale_m_per_unit"]) <= 0.0:
		return _fail("Heightfield spacing and elevation scale must be positive.")
	if absf(origin_x - float(b["min_x"])) > 0.001 or absf(origin_z - float(b["min_z"])) > 0.001:
		return _fail("Heightfield origin does not match metadata bounds.")
	if absf(origin_x + (grid_width - 1) * spacing_m - float(b["max_x"])) > 0.001:
		return _fail("Heightfield width does not span metadata bounds.")
	if absf(origin_z + (grid_height - 1) * spacing_m - float(b["max_z"])) > 0.001:
		return _fail("Heightfield height does not span metadata bounds.")
	return true

func _decode_heightfield(path: String) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return _fail("Cannot open R16 file %s (FileAccess error %d)" % [path, FileAccess.get_open_error()])
	var expected_bytes := grid_width * grid_height * 2
	if handle.get_length() != expected_bytes:
		return _fail("R16 byte length mismatch: got %d, expected %d at %s" % [handle.get_length(), expected_bytes, path])
	var bytes: PackedByteArray = handle.get_buffer(expected_bytes)
	if bytes.size() != expected_bytes:
		return _fail("R16 truncated while reading: %s" % path)
	var h: Dictionary = metadata["heightfield"]
	var scale: float = float(h["scale_m_per_unit"])
	var offset: float = float(h["offset_m"])
	height_samples.resize(grid_width * grid_height)
	for i in range(height_samples.size()):
		# Explicit LE; do not reinterpret these bytes as floats or host-endian uint16.
		var quantized: int = int(bytes[2 * i]) | (int(bytes[2 * i + 1]) << 8)
		height_samples[i] = float(quantized) * scale + offset
	return true

func _valid_xyz(raw: Variant) -> bool:
	if not (raw is Array) or raw.size() != 3:
		return false
	for value in raw:
		if not _is_number(value) or not is_finite(float(value)):
			return false
	return true

func _validate_graph() -> bool:
	if graph.get("schema_version") != 1 or graph.get("units") != "meters" or graph.get("coordinate_system") != "godot_y_up":
		return _fail("Road graph must use schema v1, meters and godot_y_up coordinates.")
	if not (graph.get("roads") is Array) or not (graph.get("lanes") is Array) or not (graph.get("bounds") is Dictionary):
		return _fail("Road graph is missing roads, lanes or bounds.")
	var bounds: Dictionary = graph["bounds"]
	var expected: Dictionary = metadata["bounds"]
	for key in ["min_x", "max_x", "min_z", "max_z"]:
		if not bounds.has(key) or not _is_number(bounds[key]) or absf(float(bounds[key]) - float(expected[key])) > 0.001:
			return _fail("Road graph bounds disagree with metadata: %s" % key)
	var road_ids := {}
	for raw_road in graph["roads"]:
		if not (raw_road is Dictionary) or not (raw_road.get("id") is String) or not (raw_road.get("lane_ids") is Array):
			return _fail("Malformed road record.")
		var rid: String = raw_road["id"]
		if rid.is_empty() or road_ids.has(rid):
			return _fail("Duplicate/empty road id: %s" % rid)
		road_ids[rid] = true
		roads.append(raw_road)
	for raw_lane in graph["lanes"]:
		if not (raw_lane is Dictionary) or not (raw_lane.get("id") is String):
			return _fail("Malformed lane record.")
		var lid: String = raw_lane["id"]
		if lid.is_empty() or lanes.has(lid):
			return _fail("Duplicate/empty lane id: %s" % lid)
		if not road_ids.has(raw_lane.get("road_id", "")):
			return _fail("Lane %s references unknown road." % lid)
		var pts: Variant = raw_lane.get("points")
		if not (pts is Array) or pts.size() < 2:
			return _fail("Lane %s requires at least 2 points." % lid)
		if not _is_number(raw_lane.get("width_m")) or float(raw_lane["width_m"]) <= 0.0:
			return _fail("Lane %s has invalid width." % lid)
		if not _is_number(raw_lane.get("speed_limit_kph")) or float(raw_lane["speed_limit_kph"]) < 0.0:
			return _fail("Lane %s has invalid speed limit." % lid)
		if raw_lane.get("surface") not in ["asphalt", "gravel"]:
			return _fail("Lane %s has unsupported surface." % lid)
		if not (raw_lane.get("next_lane_ids") is Array):
			return _fail("Lane %s has invalid next_lane_ids." % lid)
		var previous := Vector3.ZERO
		var first := true
		for p in pts:
			if not _valid_xyz(p):
				return _fail("Lane %s has invalid coordinate." % lid)
			var point := Vector3(float(p[0]), float(p[1]), float(p[2]))
			if point.x < origin_x - 0.5 or point.x > origin_x + (grid_width - 1) * spacing_m + 0.5:
				return _fail("Lane %s lies outside X bounds." % lid)
			if point.z < origin_z - 0.5 or point.z > origin_z + (grid_height - 1) * spacing_m + 0.5:
				return _fail("Lane %s lies outside Z bounds." % lid)
			if not first and point.distance_to(previous) < 0.0001:
				return _fail("Lane %s has duplicate consecutive points." % lid)
			previous = point
			first = false
		lanes[lid] = raw_lane
	for lane in lanes.values():
		for next_id in lane["next_lane_ids"]:
			if not (next_id is String) or not lanes.has(next_id):
				return _fail("Lane %s references a nonexistent successor." % lane["id"])
	for road in roads:
		for lane_id in road["lane_ids"]:
			if not (lane_id is String) or not lanes.has(lane_id):
				return _fail("Road %s references a nonexistent lane." % road["id"])
			if lanes[lane_id]["road_id"] != road["id"]:
				return _fail("Road/lane ownership mismatch: %s" % lane_id)
		# Physical roads require exactly matching AB and BA sampled centerlines.
		# The World Agent's junction pseudo-roads contain turn_* lanes instead.
		var rid: String = road["id"]
		var forward := "lane_%s_ab" % rid
		var reverse := "lane_%s_ba" % rid
		if lanes.has(forward) or lanes.has(reverse):
			if not lanes.has(forward) or not lanes.has(reverse):
				return _fail("Unpaired physical road: %s" % rid)
			var lane_a: Dictionary = lanes[forward]
			var lane_b: Dictionary = lanes[reverse]
			if lane_a["points"].size() != lane_b["points"].size():
				return _fail("Physical road AB/BA sample counts disagree: %s" % rid)
			if lane_a["surface"] != lane_b["surface"] or absf(float(lane_a["width_m"]) - float(lane_b["width_m"])) > 0.001:
				return _fail("Physical road AB/BA width/surface disagree: %s" % rid)
	return true

func world_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x - origin_x) / spacing_m, (z - origin_z) / spacing_m)

func height_index(ix: int, iz: int) -> float:
	return height_samples[clampi(iz, 0, grid_height - 1) * grid_width + clampi(ix, 0, grid_width - 1)]

func sample_height(x: float, z: float) -> float:
	## Bilinear sample matching the source exporter's lane-height lookup.
	var grid := world_to_grid(x, z)
	var gx := clampf(grid.x, 0.0, float(grid_width - 1))
	var gz := clampf(grid.y, 0.0, float(grid_height - 1))
	var ix := mini(int(floor(gx)), grid_width - 2)
	var iz := mini(int(floor(gz)), grid_height - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	return lerpf(lerpf(height_index(ix, iz), height_index(ix + 1, iz), tx),
		lerpf(height_index(ix, iz + 1), height_index(ix + 1, iz + 1), tx), tz)

func sample_surface_height(x: float, z: float, reference := PackedFloat32Array()) -> float:
	## Exactly matches the terrain mesh's two-triangle split, including at seams.
	var grid := world_to_grid(x, z)
	var gx := clampf(grid.x, 0.0, float(grid_width - 1))
	var gz := clampf(grid.y, 0.0, float(grid_height - 1))
	var ix := mini(int(floor(gx)), grid_width - 2)
	var iz := mini(int(floor(gz)), grid_height - 2)
	var u := gx - float(ix)
	var v := gz - float(iz)
	var raster: PackedFloat32Array = height_samples if reference.is_empty() else reference
	var origin := iz * grid_width + ix
	var a := raster[origin]
	var b := raster[origin + 1]
	var c := raster[origin + grid_width]
	var d := raster[origin + grid_width + 1]
	if u + v <= 1.0:
		return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)

func _fail(message: String) -> bool:
	error_message = message
	push_error("[WorldData] " + message)
	return false
