class_name EngineWavLoader
extends RefCounted
## Robust WAV loader and loop configurator for recorded vehicle audio.
## Supports Godot ResourceLoader, AudioStreamWAV.load_from_file, and binary RIFF fallback.

static func load_wav(path: String) -> AudioStreamWAV:
	var candidate_paths: Array[String] = [path]
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.contains(":/"):
		candidate_paths.append("res://" + path)
		candidate_paths.append("res://../../" + path)
	elif path.begins_with("res://"):
		var without_res := path.trim_prefix("res://")
		candidate_paths.append(without_res)

	for p in candidate_paths:
		var stream := _try_load_single_path(p)
		if stream != null:
			return stream

	push_warning("EngineWavLoader: Could not load WAV from any candidate path for: " + path)
	return null


static func _try_load_single_path(p: String) -> AudioStreamWAV:
	# 1. Try ResourceLoader if imported
	if ResourceLoader.exists(p):
		var res: Resource = ResourceLoader.load(p)
		if res is AudioStreamWAV:
			return res

	# 2. Try AudioStreamWAV.load_from_file if available
	if ClassDB.class_has_method("AudioStreamWAV", "load_from_file"):
		if FileAccess.file_exists(p):
			var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(p)
			if stream != null and stream.data.size() > 0:
				return stream

	# 3. Direct binary RIFF/WAV parser fallback
	if FileAccess.file_exists(p):
		var stream := _load_wav_binary(p)
		if stream != null:
			return stream

	return null


# Condition a private copy of a recorded engine loop. Keep original PCM and
# attribution untouched; do not shorten the loop or change its firing cadence.
static func load_engine_loop(path: String) -> AudioStreamWAV:
	var source: AudioStreamWAV = null
	if FileAccess.file_exists(path):
		source = _load_wav_binary(path)
	if source == null:
		source = load_wav(path)
	if source == null:
		return null
	var stream := source.duplicate() as AudioStreamWAV
	if stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo:
		stream.data = condition_pcm16_seam(stream.data, stream.mix_rate)
	configure_loop(stream, true)
	return stream


# Symmetric raised-cosine correction over 2 ms on each side of the seam.
# Endpoints meet at their midpoint; the correction decays to zero away
# from the boundary. PCM length and all interior samples remain unchanged.
static func condition_pcm16_seam(data: PackedByteArray, rate: int) -> PackedByteArray:
	var frames := data.size() >> 1
	var span := mini(roundi(float(rate) * 0.002), frames >> 2)
	if span < 2:
		return data
	var first := data.decode_s16(0)
	var last := data.decode_s16((frames - 1) * 2)
	if absi(first - last) < 128:
		return data
	var midpoint := (float(first) + float(last)) * 0.5
	var out := data.duplicate()
	for i in range(span):
		var weight := 0.5 * (1.0 + cos(PI * float(i) / float(span - 1)))
		var tail := (frames - 1 - i) * 2
		out.encode_s16(i * 2, clampi(roundi(float(data.decode_s16(i * 2)) + (midpoint - first) * weight), -32768, 32767))
		out.encode_s16(tail, clampi(roundi(float(data.decode_s16(tail)) + (midpoint - last) * weight), -32768, 32767))
	return out


static func configure_loop(stream: AudioStreamWAV, is_loop: bool = true) -> void:
	if stream == null:
		return
	if is_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		var sample_frames := int(round(stream.get_length() * float(stream.mix_rate)))
		stream.loop_end = maxi(1, sample_frames)
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED


static func _load_wav_binary(path: String) -> AudioStreamWAV:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 12:
		return null
	var bytes := file.get_buffer(file.get_length())
	return parse_pcm_riff(bytes)


# Strict parser for raw PCM. RIFF chunks are word aligned; do not interpret
# float, ADPCM, or 24-bit payloads as PCM16.
static func parse_pcm_riff(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 12:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var end := 8 + int(bytes.decode_u32(4))
	if end < 12 or end > bytes.size():
		return null
	var channels := 0
	var sample_rate := 0
	var bits := 0
	var block_align := 0
	var fmt_seen := false
	var data_seen := false
	var pcm := PackedByteArray()
	var pos := 12
	while pos + 8 <= end:
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := int(bytes.decode_u32(pos + 4))
		var start := pos + 8
		var finish := start + chunk_size
		if finish > end:
			return null
		if chunk_id == "fmt ":
			if fmt_seen or chunk_size < 16 or bytes.decode_u16(start) != 1:
				return null
			fmt_seen = true
			channels = bytes.decode_u16(start + 2)
			sample_rate = bytes.decode_u32(start + 4)
			block_align = bytes.decode_u16(start + 12)
			bits = bytes.decode_u16(start + 14)
		elif chunk_id == "data":
			if data_seen:
				return null
			data_seen = true
			pcm = bytes.slice(start, finish)
		pos = finish + (chunk_size & 1)
	if not fmt_seen or not data_seen or pcm.is_empty():
		return null
	if channels < 1 or channels > 2 or sample_rate < 8000 or sample_rate > 192000 or bits not in [8, 16]:
		return null
	if block_align != channels * (bits >> 3) or pcm.size() % block_align != 0:
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	if bits == 8:
		# WAV PCM8 is unsigned; Godot FORMAT_8_BITS expects signed PCM.
		for i in range(pcm.size()):
			pcm[i] = pcm[i] ^ 0x80
	stream.data = pcm
	return stream
