extends RefCounted
## Strict v1 reader. Missing/corrupt packages disable production cover.
const SIZE := 1000
const ORIGIN := -1000.0
const CELL := 2.0
const CHANNELS := ["grass_suitability", "woodland_weight", "moisture", "exposed_rock_weight"]
const WORLD_FILES := ["world_metadata_v1.json", "road_graph_v1.json", "terrain_height_r16le.bin", "terrain_roadworks_r16le.bin", "roadworks.json"]
const SCENERY_FILES := ["content/scenery/manifest.json", "content/scenery/avoidance/race_gate_reservations_v1.json", "content/scenery/lake/water_cells_v1.json"]
var bytes := PackedByteArray()
var source_hashes: Dictionary = {}
var error := ""

func clear() -> void:
	bytes.clear()
	source_hashes.clear()

func _fail(message: String) -> bool:
	clear()
	error = message
	return false

func _digest_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value.to_lower():
		if not "0123456789abcdef".contains(character):
			return false
	return true

func load_package(dir: String) -> bool:
	clear()
	error = ""
	if dir.is_empty():
		return _fail("empty mask directory")
	var manifest := FileAccess.open(dir.path_join("manifest.json"), FileAccess.READ)
	if manifest == null or manifest.get_length() > 65536:
		return _fail("missing or oversized manifest")
	var parsed: Variant = JSON.parse_string(manifest.get_as_text())
	if not parsed is Dictionary:
		return _fail("invalid manifest JSON")
	var m: Dictionary = parsed
	if m.get("schema_version") != 1 or m.get("width") != SIZE or m.get("height") != SIZE or m.get("cell_size_m") != CELL or m.get("origin_x") != ORIGIN or m.get("origin_z") != ORIGIN or m.get("byte_order") != "RGBA":
		return _fail("incompatible mask grid")
	if m.get("channels") != CHANNELS or m.get("row_order", "z_ascending_x_ascending") != "z_ascending_x_ascending":
		return _fail("incompatible mask channels or row order")
	if not m.get("source_hashes") is Dictionary or not _digest_valid(m.get("sha256")):
		return _fail("missing or malformed mask provenance")
	var seed: Variant = m.get("seed")
	if not (seed is int or seed is float) or not is_finite(float(seed)) or floorf(float(seed)) != float(seed):
		return _fail("invalid mask seed")
	for key: Variant in m.source_hashes:
		if not key is String or not _digest_valid(m.source_hashes[key]):
			return _fail("invalid source hash")
	var data := FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.READ)
	if data == null or data.get_length() != SIZE * SIZE * 4:
		return _fail("missing or wrong-sized RGBA mask")
	var payload := data.get_buffer(SIZE * SIZE * 4)
	if payload.size() != SIZE * SIZE * 4:
		return _fail("truncated mask read")
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK or hash_context.update(payload) != OK:
		return _fail("mask checksum calculation failed")
	var digest := hash_context.finish().hex_encode()
	if digest != str(m.sha256).to_lower():
		return _fail("mask checksum mismatch")
	bytes = payload
	source_hashes = m.source_hashes.duplicate()
	return true

# Validate only fixed, trusted world filenames, never a path supplied by the manifest.
# Called once at build for the canonical production runtime; not per frame.
func _verify_hash(key: String, path: String) -> bool:
	var expected: Variant = source_hashes.get(key)
	if not _digest_valid(expected) or not FileAccess.file_exists(path):
		return _fail("missing mask source: " + key)
	if FileAccess.get_sha256(path) != str(expected).to_lower():
		return _fail("stale mask source: " + key)
	return true

func verify_world_sources(directory: String) -> bool:
	if bytes.size() != SIZE * SIZE * 4 or directory.is_empty():
		return _fail("missing source directory or mask")
	for filename: String in WORLD_FILES:
		if not _verify_hash("data/world/" + filename, directory.path_join(filename)):
			return false
	return true

# Check the other actual inputs consumed by C's generator. Paths are fixed or
# constrained to direct JSON children of the known scenery packs directory.
func verify_production_sources(world_directory: String, project_root: String = "res://") -> bool:
	if not verify_world_sources(world_directory):
		return false
	if not _verify_hash("data/world/vegetation.bin",world_directory.path_join("vegetation.bin")):
		return false
	var premium_path := world_directory.path_join("premium_foliage.bin")
	var premium_key := "data/world/premium_foliage.bin"
	if FileAccess.file_exists(premium_path) != source_hashes.has(premium_key):
		return _fail("optional premium cache availability changed")
	if source_hashes.has(premium_key) and not _verify_hash(premium_key,premium_path):
		return false
	for relative: String in SCENERY_FILES:
		if not _verify_hash(relative,project_root.path_join(relative)):
			return false
	var manifest_path := project_root.path_join("content/scenery/manifest.json")
	var scenery: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not scenery is Dictionary or not scenery.get("region_packs") is Array:
		return _fail("invalid scenery manifest")
	var packs: Array = scenery.region_packs
	if packs.is_empty() or packs.size() > 32:
		return _fail("invalid scenery pack count")
	var visited: Dictionary = {}
	for pack: Variant in packs:
		if not pack is Dictionary or not pack.get("path") is String:
			return _fail("invalid scenery pack entry")
		var relative: String = pack.path
		var prefix := "content/scenery/packs/"
		var filename := relative.trim_prefix(prefix)
		if not relative.begins_with(prefix) or filename.is_empty() or filename.contains("/") or filename.contains("\\") or filename.contains("..") or filename.contains(":") or not filename.ends_with(".json") or visited.has(relative):
			return _fail("unsafe or duplicate scenery pack path")
		visited[relative] = true
		if not _verify_hash(relative,project_root.path_join(relative)):
			return false
	return true

func sample(x: float, z: float) -> Vector4:
	if bytes.size() != SIZE * SIZE * 4 or not is_finite(x) or not is_finite(z) or x < ORIGIN or z < ORIGIN or x >= 1000.0 or z >= 1000.0:
		return Vector4.ZERO
	var ix := floori((x - ORIGIN) / CELL)
	var iz := floori((z - ORIGIN) / CELL)
	# Float division near the positive edge may round to SIZE.
	if ix < 0 or iz < 0 or ix >= SIZE or iz >= SIZE:
		return Vector4.ZERO
	var i := (iz * SIZE + ix) * 4
	return Vector4(bytes[i], bytes[i+1], bytes[i+2], bytes[i+3]) / 255.0
