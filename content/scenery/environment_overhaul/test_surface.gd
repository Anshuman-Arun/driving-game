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

func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	quit(1)
