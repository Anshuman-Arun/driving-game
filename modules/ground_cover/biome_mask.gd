extends RefCounted
## Strict v1 reader. Missing/corrupt packages disable production cover.
const SIZE := 1000
const ORIGIN := -1000.0
const CELL := 2.0
var bytes := PackedByteArray()
var error := ""

func load_package(dir: String) -> bool:
	bytes.clear()
	error = ""
	var manifest := FileAccess.open(dir.path_join("manifest.json"), FileAccess.READ)
	if manifest == null or manifest.get_length() > 65536:
		error = "missing or oversized manifest"
		return false
	var parsed: Variant = JSON.parse_string(manifest.get_as_text())
	if not parsed is Dictionary:
		error = "invalid manifest JSON"
		return false
	var m: Dictionary = parsed
	if m.get("schema_version") != 1 or m.get("width") != SIZE or m.get("height") != SIZE or m.get("cell_size_m") != CELL or m.get("origin_x") != ORIGIN or m.get("origin_z") != ORIGIN or m.get("byte_order") != "RGBA":
		error = "incompatible mask grid"
		return false
	var data := FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.READ)
	if data == null or data.get_length() != SIZE * SIZE * 4:
		error = "missing or wrong-sized RGBA mask"
		return false
	var payload := data.get_buffer(SIZE * SIZE * 4)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(payload)
	var digest := hash_context.finish().hex_encode()
	if digest != str(m.get("sha256", "")).to_lower():
		error = "mask checksum mismatch"
		return false
	bytes = payload
	return true

func sample(x: float, z: float) -> Vector4:
	if bytes.is_empty() or not is_finite(x) or not is_finite(z) or x < ORIGIN or z < ORIGIN or x >= 1000.0 or z >= 1000.0:
		return Vector4.ZERO
	var ix := floori((x - ORIGIN) / CELL)
	var iz := floori((z - ORIGIN) / CELL)
	var i := (iz * SIZE + ix) * 4
	return Vector4(bytes[i], bytes[i+1], bytes[i+2], bytes[i+3]) / 255.0
