class_name AsterAudioAssetVerifier
extends RefCounted
## Verifies recorded audio assets for Aster Valley:
## - WAV decoding and PCM 16-bit format integrity
## - Sample rate compliance (48000 Hz target for recorded payload)
## - Non-zero signal presence and dynamic range
## - Headroom and clipping detection
## - Loop endpoints and loop seam continuity
## - Loading into Godot AudioStreamWAV resources

const TARGET_SAMPLE_RATE := 48000
const MIN_PEAK_LINEAR := 0.05  # -26 dBFS minimum activity
const MAX_ALLOWED_PEAK_DBFS := 0.0  # Must not clip in source asset
const MAX_SEAM_DELTA_TOLERANCE := 4000  # PCM 16 max jump at loop seam

const ENGINE_PROFILES := ["vela_gt", "kestrel_xr", "orion_rs"]

## Verifies all recorded payload assets and fallback assets.
## Returns a comprehensive Dictionary with summary and per-file metrics.
static func verify_all(payload_root: String = "res://assets/audio/recorded/payload") -> Dictionary:
	var results := {
		"total_files": 0,
		"passed_files": 0,
		"failed_files": 0,
		"warning_files": 0,
		"all_passed": true,
		"sample_rate_target": TARGET_SAMPLE_RATE,
		"files": {},
		"manifest_checks": {},
		"errors": []
	}

	# 1. Verify engine assets per manifest
	for profile in ENGINE_PROFILES:
		var profile_result := verify_engine_profile(profile, payload_root)
		results["manifest_checks"][profile] = profile_result
		for file_key in profile_result.get("files", {}):
			results["files"][file_key] = profile_result["files"][file_key]

	# 2. Verify tire assets
	var tire_files := [
		payload_root.path_join("tires/roll_gravel.wav"),
		payload_root.path_join("tires/screech.wav")
	]
	for path in tire_files:
		var res := verify_single_file(path, true)
		results["files"][path] = res

	# 3. Verify ambience assets
	var amb_path := payload_root.path_join("ambience/mountain_wind_bed.wav")
	var amb_res := verify_single_file(amb_path, true)
	results["files"][amb_path] = amb_res

	# 4. Verify fallback assets in modules/audio/assets
	var fallback_files := [
		"res://modules/audio/assets/collision.wav",
		"res://modules/audio/assets/gearshift.wav",
		"res://modules/audio/assets/overrun.wav",
		"res://modules/audio/assets/roll_asphalt.wav",
		"res://modules/audio/assets/roll_grass.wav",
		"res://modules/audio/assets/suspension.wav",
		"res://modules/audio/assets/wind.wav"
	]
	for path in fallback_files:
		if FileAccess.file_exists(path) or FileAccess.file_exists(path.trim_prefix("res://")):
			var is_loop: bool = path.contains("roll_") or path.ends_with("wind.wav")
			var res := verify_single_file(path, is_loop, false)
			results["files"][path] = res

	# Compute aggregate metrics
	for key in results["files"]:
		var f: Dictionary = results["files"][key]
		results["total_files"] += 1
		if f.get("passed", false):
			results["passed_files"] += 1
		else:
			results["failed_files"] += 1
			results["all_passed"] = false
			results["errors"].append("%s: %s" % [key, f.get("error", "Unknown error")])
		if f.get("warnings", []).size() > 0:
			results["warning_files"] += 1

	return results


## Verifies an engine profile from its manifest.json
static func verify_engine_profile(profile: String, payload_root: String = "res://assets/audio/recorded/payload") -> Dictionary:
	var manifest_path := payload_root.path_join("engines/%s/manifest.json" % profile)
	var resolved_path := _resolve_path(manifest_path)
	
	var res := {
		"profile": profile,
		"manifest_found": false,
		"total_loops": 0,
		"passed_loops": 0,
		"missing_loops": 0,
		"files": {},
		"errors": []
	}

	if not FileAccess.file_exists(resolved_path):
		res["errors"].append("manifest.json missing at: " + resolved_path)
		return res

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if not file:
		res["errors"].append("Could not open manifest: " + resolved_path)
		return res

	var json_str := file.get_as_text()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		res["errors"].append("Invalid JSON in: " + resolved_path)
		return res

	res["manifest_found"] = true
	var manifest: Dictionary = parsed
	var loops: Array = manifest.get("loops", [])
	res["total_loops"] = loops.size()

	var base_dir := manifest_path.get_base_dir()

	for loop_entry in loops:
		if not (loop_entry is Dictionary):
			continue
		var filename: String = loop_entry.get("file", "")
		var wav_path := base_dir.path_join(filename)
		var loop_rpm: int = int(loop_entry.get("rpm", 0))
		var loop_layer: String = str(loop_entry.get("layer", "on"))

		var file_check := verify_single_file(wav_path, true, true)
		file_check["profile"] = profile
		file_check["rpm"] = loop_rpm
		file_check["layer"] = loop_layer

		# Cross-reference duration with manifest
		if loop_entry.has("duration_s"):
			var expected_dur: float = float(loop_entry["duration_s"])
			var actual_dur: float = float(file_check.get("duration_s", 0.0))
			if absf(expected_dur - actual_dur) > 0.05:
				file_check.get("warnings", []).append(
					"Duration delta from manifest: expected %.3f, got %.3f" % [expected_dur, actual_dur]
				)

		res["files"][wav_path] = file_check
		if file_check.get("passed", false):
			res["passed_loops"] += 1
		else:
			res["missing_loops"] += 1

	return res


## Verifies a single WAV audio file on disk.
static func verify_single_file(path: String, expect_loop: bool = false, enforce_48k: bool = true) -> Dictionary:
	var resolved := _resolve_path(path)
	var report := {
		"path": path,
		"resolved_path": resolved,
		"exists": false,
		"passed": false,
		"error": "",
		"warnings": [],
		"channels": 0,
		"sample_rate": 0,
		"bits_per_sample": 0,
		"frames": 0,
		"duration_s": 0.0,
		"peak_linear": 0.0,
		"peak_dbfs": -999.0,
		"rms_linear": 0.0,
		"rms_dbfs": -999.0,
		"dc_offset": 0.0,
		"clipped_samples": 0,
		"seam_delta": 0,
		"loop_begin": 0,
		"loop_end": 0,
		"loop_mode_valid": false,
		"stream_valid": false
	}

	if not FileAccess.file_exists(resolved):
		report["error"] = "File not found: " + resolved
		return report

	report["exists"] = true
	var file := FileAccess.open(resolved, FileAccess.READ)
	if not file:
		report["error"] = "Could not open file: " + resolved
		return report

	# Parse RIFF/WAVE header
	var riff_tag := file.get_buffer(4).get_string_from_ascii()
	if riff_tag != "RIFF":
		report["error"] = "Header tag is not RIFF (got: %s)" % riff_tag
		return report

	var _file_size := file.get_32()
	var wave_tag := file.get_buffer(4).get_string_from_ascii()
	if wave_tag != "WAVE":
		report["error"] = "Format tag is not WAVE (got: %s)" % wave_tag
		return report

	var format_tag: int = 1
	var channels: int = 1
	var sample_rate: int = 0
	var bits_per_sample: int = 16
	var data_bytes := PackedByteArray()

	while file.get_position() < file.get_length():
		if file.get_position() + 8 > file.get_length():
			break
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		if chunk_id == "fmt ":
			format_tag = file.get_16()
			channels = file.get_16()
			sample_rate = file.get_32()
			var _avg_bps := file.get_32()
			var _block_align := file.get_16()
			bits_per_sample = file.get_16()
			var extra := chunk_size - 16
			if extra > 0:
				file.seek(file.get_position() + extra)
		elif chunk_id == "data":
			data_bytes = file.get_buffer(chunk_size)
		else:
			file.seek(file.get_position() + chunk_size)

	file.close()

	report["channels"] = channels
	report["sample_rate"] = sample_rate
	report["bits_per_sample"] = bits_per_sample

	# Validate Format
	if format_tag != 1:
		report["error"] = "WAV format is not PCM (tag: %d)" % format_tag
		return report

	if bits_per_sample != 16:
		report["error"] = "Expected 16-bit PCM, got %d bits" % bits_per_sample
		return report

	if enforce_48k and sample_rate != TARGET_SAMPLE_RATE:
		report["error"] = "Sample rate mismatch: expected %d Hz, got %d Hz" % [TARGET_SAMPLE_RATE, sample_rate]
		return report

	if data_bytes.is_empty():
		report["error"] = "WAV data chunk is empty"
		return report

	var bytes_per_frame: int = channels * 2
	var total_frames: int = data_bytes.size() / bytes_per_frame
	report["frames"] = total_frames
	report["duration_s"] = float(total_frames) / float(sample_rate)

	if total_frames < 64:
		report["error"] = "Asset too short: %d frames" % total_frames
		return report

	# Analyze PCM signal
	var max_abs_val: int = 0
	var sum_squares: float = 0.0
	var sum_samples: float = 0.0
	var clipped_count: int = 0
	var sample_count: int = data_bytes.size() / 2

	var first_sample: int = _decode_int16(data_bytes, 0)
	var last_sample: int = _decode_int16(data_bytes, (sample_count - 1) * 2)

	for i in range(sample_count):
		var s := _decode_int16(data_bytes, i * 2)
		var abs_s := absi(s)
		if abs_s > max_abs_val:
			max_abs_val = abs_s
		if abs_s >= 32767:
			clipped_count += 1
		var norm := float(s) / 32768.0
		sum_squares += norm * norm
		sum_samples += norm

	var peak_linear := float(max_abs_val) / 32768.0
	var rms_linear := sqrt(sum_squares / float(sample_count))
	var peak_dbfs := _linear_to_db(peak_linear)
	var rms_dbfs := _linear_to_db(rms_linear)
	var dc_offset := absf(sum_samples / float(sample_count))

	report["peak_linear"] = peak_linear
	report["peak_dbfs"] = peak_dbfs
	report["rms_linear"] = rms_linear
	report["rms_dbfs"] = rms_dbfs
	report["dc_offset"] = dc_offset
	report["clipped_samples"] = clipped_count

	# Check non-zero signal
	if peak_linear < MIN_PEAK_LINEAR:
		report["error"] = "Audio signal too quiet or silent (peak: %.4f / %.1f dBFS)" % [peak_linear, peak_dbfs]
		return report

	# Check clipping in asset
	if peak_dbfs > MAX_ALLOWED_PEAK_DBFS or clipped_count > 4:
		report["error"] = "Source asset clips (> 0 dBFS or %d hard clip samples)" % clipped_count
		return report

	# Check seam delta for loops
	if expect_loop:
		var seam_delta: int = absi(last_sample - first_sample)
		report["seam_delta"] = seam_delta
		if seam_delta > MAX_SEAM_DELTA_TOLERANCE:
			report["warnings"].append("High seam delta at loop boundary: %d" % seam_delta)

	# Verify loading into Godot AudioStreamWAV
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data_bytes

	if expect_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		var sample_frames: int = int(round(stream.get_length() * float(stream.mix_rate)))
		stream.loop_end = sample_frames
		report["loop_begin"] = stream.loop_begin
		report["loop_end"] = stream.loop_end
		report["loop_mode_valid"] = (stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > 0)
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		report["loop_mode_valid"] = true

	report["stream_valid"] = (stream.data.size() == data_bytes.size() and stream.get_length() > 0.0)
	report["passed"] = report["stream_valid"] and report["error"] == ""

	return report


## Reads a signed 16-bit little-endian integer from PackedByteArray.
static func _decode_int16(bytes: PackedByteArray, offset: int) -> int:
	var b0 := bytes[offset]
	var b1 := bytes[offset + 1]
	var u := b0 | (b1 << 8)
	return u if u < 32768 else u - 65536


static func _linear_to_db(linear: float) -> float:
	if linear <= 0.0000001:
		return -144.0
	return 20.0 * (log(linear) / log(10.0))


## Resolves res:// or relative paths to filesystem paths.
static func _resolve_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	if path.begins_with("res://"):
		var rel := path.trim_prefix("res://")
		if FileAccess.file_exists(rel):
			return rel
	return path
