extends RefCounted
## Data-only catalog loader; route and checkpoint semantics are checked by RaceEngine.
var events: Dictionary = {}
var last_error: String = ""

func parse_text(json_text: String) -> bool:
	events.clear()
	last_error = ""
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary) or parsed.get("schema_version") != 1 or not (parsed.get("events") is Array):
		last_error = "Expected {schema_version:1, events:[...]}"
		return false
	for raw in parsed["events"]:
		if not (raw is Dictionary) or not (raw.get("id") is String) or str(raw["id"]).is_empty() or events.has(raw["id"]):
			last_error = "Invalid or duplicate event ID"
			events.clear()
			return false
		if not (raw.get("kind") in ["circuit", "sprint"]) or not (raw.get("lane_route") is Array) or not (raw.get("checkpoints") is Array):
			last_error = "Invalid event shape: " + str(raw["id"])
			events.clear()
			return false
		var event_def: Dictionary = raw.duplicate(true)
		event_def["schema_version"] = 1
		events[raw["id"]] = event_def
	return true

func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "Event file not found: " + path
		return false
	return parse_text(FileAccess.get_file_as_string(path))

func get_event(id: String) -> Dictionary:
	return events[id].duplicate(true) if events.has(id) else {}
