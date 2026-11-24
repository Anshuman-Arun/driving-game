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
