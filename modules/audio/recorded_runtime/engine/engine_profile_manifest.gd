class_name EngineProfileManifest
extends RefCounted
## Manifest data container and anchor search helper for recorded engine profiles.
## Parses payload/engines/{profile}/manifest.json.

var profile_name: String = ""
var source_url: String = ""
var source_character: String = ""
var bank_status: String = ""
var license: String = ""
var loops: Array[Dictionary] = []
var on_anchors: Array[Dictionary] = []
var off_anchors: Array[Dictionary] = []
var min_rpm: float = 1000.0
var max_rpm: float = 8000.0
var has_off_layer: bool = false
var manifest_directory: String = ""


static func load_for_profile(profile: String, custom_base_dir: String = "") -> RefCounted:
	var script: GDScript = load("res://modules/audio/recorded_runtime/engine/engine_profile_manifest.gd")
	var manifest: RefCounted = script.new()
	var candidates: Array[String] = []

	if custom_base_dir != "":
		candidates.append(custom_base_dir.path_join(profile).path_join("manifest.json"))
		candidates.append(custom_base_dir.path_join("manifest.json"))

	candidates.append("res://assets/audio/recorded/payload/engines/%s/manifest.json" % profile)
	candidates.append("assets/audio/recorded/payload/engines/%s/manifest.json" % profile)
	candidates.append("res://../../assets/audio/recorded/payload/engines/%s/manifest.json" % profile)

	var json_text := ""
	var found_path := ""

	for path in candidates:
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				json_text = file.get_as_text()
				found_path = path
				break

	if json_text == "":
		push_error("EngineProfileManifest: manifest.json not found for profile: " + profile)
		return null

	manifest.manifest_directory = found_path.get_base_dir()
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		push_error("EngineProfileManifest: Invalid JSON in " + found_path)
		return null

	if not manifest.parse_dictionary(parsed as Dictionary):
		return null

	return manifest


func parse_dictionary(data: Dictionary) -> bool:
	profile_name = str(data.get("profile", ""))
	source_url = str(data.get("source", ""))
	source_character = str(data.get("source_character", ""))
	bank_status = str(data.get("status", ""))
	license = str(data.get("license", ""))
	loops.clear()
	on_anchors.clear()
	off_anchors.clear()

	var raw_loops: Variant = data.get("loops", [])
	if not (raw_loops is Array):
		push_error("EngineProfileManifest: 'loops' missing or not an array")
		return false

	var lowest := 999999.0
	var highest := 0.0

	for item in raw_loops:
		if not (item is Dictionary):
			continue
		var loop_dict: Dictionary = item
		var rpm := float(loop_dict.get("rpm", 0.0))
		var layer := str(loop_dict.get("layer", "on")).to_lower()
		var file := str(loop_dict.get("file", ""))
		var gain := float(loop_dict.get("gain", 1.0))
		var duration := float(loop_dict.get("duration_s", 1.0))

		var entry := {
			"rpm": rpm,
			"layer": layer,
			"file": file,
			"gain": gain,
			"duration_s": duration,
			"full_path": manifest_directory.path_join(file) if manifest_directory != "" else file
		}

		loops.append(entry)
		if layer == "on":
			on_anchors.append(entry)
			lowest = minf(lowest, rpm)
			highest = maxf(highest, rpm)
		elif layer == "off":
			off_anchors.append(entry)
			lowest = minf(lowest, rpm)
			highest = maxf(highest, rpm)

	# Sort anchors by ascending RPM
	var sort_func := func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["rpm"]) < float(b["rpm"])

	on_anchors.sort_custom(sort_func)
	off_anchors.sort_custom(sort_func)

	has_off_layer = off_anchors.size() > 0
	min_rpm = lowest if lowest < 999999.0 else 1000.0
	max_rpm = highest if highest > 0.0 else 8000.0

	return true


func get_anchors_for_layer(layer: String) -> Array[Dictionary]:
	if layer == "off":
		return off_anchors if has_off_layer else on_anchors
	return on_anchors


func find_bracketing_anchors(layer: String, rpm: float) -> Dictionary:
	var anchors := get_anchors_for_layer(layer)
	if anchors.is_empty():
		return {}

	if anchors.size() == 1:
		return {
			"low": anchors[0],
			"high": anchors[0],
			"t": 0.0,
			"is_single": true
		}

	var first_rpm := float(anchors[0]["rpm"])
	if rpm <= first_rpm:
		return {
			"low": anchors[0],
			"high": anchors[0],
			"t": 0.0,
			"is_single": true
		}

	var last_idx := anchors.size() - 1
	var last_rpm := float(anchors[last_idx]["rpm"])
	if rpm >= last_rpm:
		return {
			"low": anchors[last_idx],
			"high": anchors[last_idx],
			"t": 1.0,
			"is_single": true
		}

	for i in range(last_idx):
		var r0 := float(anchors[i]["rpm"])
		var r1 := float(anchors[i + 1]["rpm"])
		if rpm >= r0 and rpm <= r1:
			var span := maxf(1.0, r1 - r0)
			var t := clampf((rpm - r0) / span, 0.0, 1.0)
			return {
				"low": anchors[i],
				"high": anchors[i + 1],
				"t": t,
				"is_single": false
			}

	return {
		"low": anchors[last_idx],
		"high": anchors[last_idx],
		"t": 1.0,
		"is_single": true
	}
