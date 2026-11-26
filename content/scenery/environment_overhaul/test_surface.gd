extends SceneTree
## After baking the real map, compare the Python probes with the production
## world-data decoder and triangle sampler. No scene/renderer changes.

const WorldData = preload("res://modules/world_runtime/src/world_data.gd")
const DEFAULT_MANIFEST := "res://content/scenery/environment_overhaul/masks/manifest.json"

func _initialize() -> void:
	var manifest_path := DEFAULT_MANIFEST
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):
			manifest_path = arg.trim_prefix("--manifest=")
	if not FileAccess.file_exists(manifest_path):
		_fail("Missing generated biome manifest: " + manifest_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		_fail("Invalid biome manifest")
		return
	var manifest: Dictionary = parsed
	if not _check_mask(manifest_path, manifest):
		return
	var probes: Array = manifest.get("surface_probes", [])
	if probes.size() < 77:
		_fail("Missing canonical surface probes")
		return
	var data = WorldData.new()
	if not data.load_directory("res://data/world"):
		_fail("Could not load canonical world")
		return
	if not data._decode_heightfield("res://data/world/terrain_roadworks_r16le.bin"):
		_fail("Could not load roadworks terrain")
		return
	var maximum := 0.0
	for value in probes:
		var probe: Dictionary = value
		var y: float = data.sample_surface_height(float(probe["x"]), float(probe["z"]))
		var delta := absf(y - float(probe["height_m"]))
		if not is_finite(y) or delta > 0.002:
			_fail("Triangle height mismatch at " + str(probe) + ": " + str(y))
			return
		maximum = maxf(maximum, delta)
	print("PASS: %d biome surface probes; maximum error %.6f m" % [probes.size(), maximum])
	quit(0)

func _check_mask(manifest_path: String, manifest: Dictionary) -> bool:
	if int(manifest.get("schema_version", 0)) != 1 or int(manifest.get("width", 0)) != 1000 or int(manifest.get("height", 0)) != 1000:
		_fail("Invalid mask dimensions/schema")
		return false
	if float(manifest.get("cell_size_m", 0)) != 2.0 or float(manifest.get("origin_x", 0)) != -1000.0 or float(manifest.get("origin_z", 0)) != -1000.0:
		_fail("Invalid mask transform")
		return false
	if str(manifest.get("byte_order", "")) != "RGBA":
		_fail("Invalid mask byte order")
		return false
	var raw_path := manifest_path.get_base_dir().path_join("biome_rgba8.bin")
	var raw := FileAccess.get_file_as_bytes(raw_path)
	if raw.size() != 4000000 or FileAccess.get_sha256(raw_path) != str(manifest.get("sha256", "")):
		_fail("Missing, truncated or corrupt mask")
		return false
	var mask_probes: Array = manifest.get("mask_probes", [])
	if mask_probes.size() != 9:
		_fail("Missing RGBA probes")
		return false
	for value in mask_probes:
		var probe: Dictionary = value
		var i := floori((float(probe["x"]) + 1000.0) / 2.0)
		var j := floori((float(probe["z"]) + 1000.0) / 2.0)
		var rgba: Array = probe["rgba"]
		if i < 0 or i >= 1000 or j < 0 or j >= 1000 or rgba.size() != 4:
			_fail("Out of bounds RGBA probe")
			return false
		var offset := 4 * (j * 1000 + i)
		for channel in range(4):
			if int(raw[offset + channel]) != int(rgba[channel]):
				_fail("Mask row/column or channel mismatch: " + str(probe))
				return false
	var hashes: Dictionary = manifest.get("source_hashes", {})
	for name in ["data/world/world_metadata_v1.json", "data/world/road_graph_v1.json",
			"data/world/terrain_height_r16le.bin", "data/world/terrain_roadworks_r16le.bin",
			"data/world/roadworks.json", "data/world/vegetation.bin"]:
		if not hashes.has(name) or FileAccess.get_sha256("res://" + name) != str(hashes[name]):
			_fail("Stale or missing source hash: " + name)
			return false
	print("PASS: 9 RGBA probes, mask hash and core world source hashes")
	return true

func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	quit(1)
