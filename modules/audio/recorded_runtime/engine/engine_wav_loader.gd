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
	if not file:
		return null

	var riff := file.get_buffer(4).get_string_from_ascii()
	if riff != "RIFF":
		return null

	var _file_size := file.get_32()
	var wave := file.get_buffer(4).get_string_from_ascii()
	if wave != "WAVE":
		return null

	var channels: int = 1
	var sample_rate: int = 48000
	var bits_per_sample: int = 16
	var data_bytes := PackedByteArray()

	while file.get_position() < file.get_length():
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		if chunk_id == "fmt ":
			var _format_tag := file.get_16()
			channels = file.get_16()
			sample_rate = file.get_32()
			var _avg_bytes_per_sec := file.get_32()
			var _block_align := file.get_16()
			bits_per_sample = file.get_16()
			var extra := chunk_size - 16
			if extra > 0:
				file.seek(file.get_position() + extra)
		elif chunk_id == "data":
			data_bytes = file.get_buffer(chunk_size)
		else:
			file.seek(file.get_position() + chunk_size)

	if data_bytes.is_empty():
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	match bits_per_sample:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data_bytes
	return stream
