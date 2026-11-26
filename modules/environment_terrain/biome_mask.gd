extends RefCounted
## Raw Agent C mask reader. No imported-resource or C module dependency.
const DEFAULT_DIR := "res://content/scenery/environment_overhaul/masks"
const SIZE := 1000
const MAX_MANIFEST_BYTES := 65536
const CHANNELS := ["grass_suitability", "woodland_weight", "moisture", "exposed_rock_weight"]
var status := "not loaded"

func load_mask(directory: String = DEFAULT_DIR) -> Texture2D:
	var image := load_image(directory)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	if texture == null or texture.get_width() != SIZE or texture.get_height() != SIZE:
		status = "mask texture creation failed"
		return null
	return texture

func _is_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for i in range(64):
		if not value[i].to_lower() in "0123456789abcdef":
			return false
	return true

func load_image(directory: String = DEFAULT_DIR) -> Image:
	status = "disabled"
	if directory.strip_edges().is_empty():
		return null
	status = "missing mask"
	var manifest_path := directory.path_join("manifest.json")
	var data_path := directory.path_join("biome_rgba8.bin")
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(data_path):
		return null
	status = "invalid mask manifest"
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null or manifest_file.get_length() <= 0 or manifest_file.get_length() > MAX_MANIFEST_BYTES:
		return null
	var parser := JSON.new()
	var parsed := parser.parse(manifest_file.get_as_text())
	manifest_file.close()
	if parsed != OK:
		return null
	var manifest: Variant = parser.data
	if not manifest is Dictionary:
		return null
	for key in ["schema_version", "width", "height", "cell_size_m", "origin_x", "origin_z"]:
		if not manifest.has(key) or not (manifest[key] is int or manifest[key] is float):
			return null
	if manifest.schema_version != 1 or manifest.width != SIZE or manifest.height != SIZE:
		return null
	if manifest.cell_size_m != 2 or manifest.origin_x != -1000 or manifest.origin_z != -1000:
		return null
	if manifest.get("byte_order") != "RGBA":
		return null
	# Accept ordered names or explicit R/G/B/A mapping. The byte order is fixed by v1.
	var channels: Variant = manifest.get("channels", manifest.get("channel_names"))
	if channels is Dictionary:
		channels = [channels.get("R", channels.get("r")), channels.get("G", channels.get("g")), channels.get("B", channels.get("b")), channels.get("A", channels.get("a"))]
	if not channels is Array or channels.size() != 4:
		return null
	for i in range(4):
		if not channels[i] is String:
			return null
		var name: String = channels[i].to_lower().replace(" ", "_").replace("-", "_")
		var aliases: Array = [CHANNELS[i]]
		match i:
			0: aliases.append("grass")
			1: aliases.append("woodland")
			3: aliases.append_array(["rock", "exposed_rock", "rock_weight"])
		if not name in aliases:
			return null
	var hash_value: Variant = manifest.get("sha256")
	if not _is_sha256(hash_value):
		return null
	var seed: Variant = manifest.get("seed")
	if not (seed is int or seed is float) or not is_finite(float(seed)) or float(seed) != floorf(float(seed)):
		return null
	var sources: Variant = manifest.get("source_hashes")
	if not sources is Dictionary or sources.is_empty():
		return null
	for key in sources:
		if not key is String or key.is_empty() or not _is_sha256(sources[key]):
			return null
	status = "invalid mask byte length"
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null or file.get_length() != SIZE * SIZE * 4:
		return null
	var bytes := file.get_buffer(SIZE * SIZE * 4)
	file.close()
	if bytes.size() != SIZE * SIZE * 4:
		return null
	status = "mask checksum mismatch"
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK or hasher.update(bytes) != OK:
		return null
	if hasher.finish().hex_encode() != hash_value.to_lower():
		return null
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)
	if image == null or image.is_empty():
		status = "mask image failed"
		return null
	status = "valid v1 mask"
	return image
