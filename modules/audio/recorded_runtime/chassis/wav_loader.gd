class_name ChassisWavLoader
extends RefCounted
## Utility to load AudioStreamWAV resources safely across all environments.
## Works both when assets have been imported by the Godot editor and when running
## raw unimported audio files during headless/bench runs.

static func load_wav(path: String) -> AudioStreamWAV:
	# 1. Try standard Godot ResourceLoader if imported
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is AudioStreamWAV:
			return res

	# 2. Direct RIFF/WAV binary parser via FileAccess
	if not FileAccess.file_exists(path):
		push_warning("ChassisWavLoader: File not found: " + path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ChassisWavLoader: Could not open file: " + path)
		return null

	var riff := file.get_buffer(4).get_string_from_ascii()
	if riff != "RIFF":
		push_error("ChassisWavLoader: Not a RIFF file: " + path)
		return null

	var _file_size := file.get_32()
	var wave := file.get_buffer(4).get_string_from_ascii()
	if wave != "WAVE":
		push_error("ChassisWavLoader: Not a WAVE file: " + path)
		return null

	var format_tag: int = 1
	var channels: int = 1
	var sample_rate: int = 44100
	var bits_per_sample: int = 16
	var data_bytes := PackedByteArray()

	while file.get_position() < file.get_length():
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		if chunk_id == "fmt ":
			format_tag = file.get_16()
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
		push_error("ChassisWavLoader: No audio data found in WAV: " + path)
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


static func configure_loop(stream: AudioStreamWAV, loop: bool = true) -> void:
	if stream == null:
		return
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		var sample_frames: int = int(round(stream.get_length() * float(stream.mix_rate)))
		stream.loop_end = maxi(1, sample_frames - 1)
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
