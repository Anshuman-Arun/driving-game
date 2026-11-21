extends RefCounted
## Minimal read-only R16 terrain sampler for isolated scenery inspection.
## Matches world-runtime PR #16 triangle interpolation; not a replacement world generator.
var metadata: Dictionary = {}
var heights: PackedFloat32Array = PackedFloat32Array()
var width: int = 0
var depth: int = 0
var spacing: float = 4.0
var origin_x: float = -1000.0
var origin_z: float = -1000.0
var error_message: String = ""

func load_directory(directory: String) -> bool:
	error_message = ""
	var metadata_path: String = directory.path_join("world_metadata_v1.json")
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open authoritative metadata " + metadata_path)
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not (raw is Dictionary):
		return _fail("Invalid world metadata JSON")
	metadata = raw
	if metadata.get("schema_version") != 1 or metadata.get("coordinate_system") != "godot_y_up":
		return _fail("Unsupported world metadata contract")
	var hf_any: Variant = metadata.get("heightfield")
	if not (hf_any is Dictionary):
		return _fail("Missing R16 metadata")
	var hf: Dictionary = hf_any
	width = int(hf.get("sample_width", 0))
	depth = int(hf.get("sample_height", 0))
	spacing = float(hf.get("spacing_m", 0.0))
	origin_x = float(hf.get("origin_x", 0.0))
	origin_z = float(hf.get("origin_z", 0.0))
	if width != 501 or depth != 501 or not is_equal_approx(spacing, 4.0):
		return _fail("The staged world heightfield is not the canonical 501x501 R16")
	if hf.get("format") != "uint16_le" or hf.get("row_order") != "z_ascending_x_ascending":
		return _fail("Heightfield must be uint16 LE, z ascending/x ascending")
	var raster_path: String = directory.path_join("terrain_height_r16le.bin")
	file = FileAccess.open(raster_path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open staged world R16 " + raster_path)
	if file.get_length() != width * depth * 2:
		return _fail("Wrong authoritative R16 byte length")
	var bytes: PackedByteArray = file.get_buffer(width * depth * 2)
	if bytes.size() != width * depth * 2:
		return _fail("Truncated staged R16 heightfield")
	var scale: float = float(hf.get("scale_m_per_unit", 0.0))
	var offset: float = float(hf.get("offset_m", 0.0))
	if scale <= 0.0:
		return _fail("Nonpositive R16 height scale")
	heights.resize(width * depth)
	for i in range(heights.size()):
		heights[i] = float(int(bytes[2 * i]) | (int(bytes[2 * i + 1]) << 8)) * scale + offset
	return true

func height_index(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, depth - 1) * width + clampi(ix, 0, width - 1)]

func sample_surface_height(x: float, z: float) -> float:
	if heights.is_empty():
		return NAN
	var gx: float = clampf((x - origin_x) / spacing, 0.0, float(width - 1))
	var gz: float = clampf((z - origin_z) / spacing, 0.0, float(depth - 1))
	var ix: int = mini(int(floor(gx)), width - 2)
	var iz: int = mini(int(floor(gz)), depth - 2)
	var u: float = gx - float(ix)
	var v: float = gz - float(iz)
	var a: float = height_index(ix, iz)
	var b: float = height_index(ix + 1, iz)
	var c: float = height_index(ix, iz + 1)
	var d: float = height_index(ix + 1, iz + 1)
	if u + v <= 1.0:
		return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)

func _fail(message: String) -> bool:
	error_message = message
	push_error("[SceneryTerrain] " + message)
	return false
