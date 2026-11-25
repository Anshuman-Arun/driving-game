extends RefCounted
## Offline versioned JSON persistence. Never requires a singleton or network access.
## Atomic temp+rename on supported filesystems; validated backup/corrupt quarantine
## covers platforms that cannot atomically replace an existing open destination.
const Catalog = preload("car_catalog.gd")
const LEGACY_CAR_IDS := ["vela_gt", "orion_rs", "kestrel_xr", "solace_gt", "aventador_svj", "mclaren_senna"]
const SCHEMA_VERSION := 2
const DEFAULT_PATH := "user://aster_valley_save_v2.json"
const GRAPHICS := ["low", "medium", "high"]
const MODES := ["windowed", "fullscreen"]
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "3440x1440"]

var path: String
var data: Dictionary = {}
var last_status: String = ""
var last_error: String = ""

func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path
	data = defaults()

static func default_settings() -> Dictionary:
	return {
		"graphics_quality":"medium", "window_mode":"windowed",
		"resolution":"1280x720", "controller_sensitivity":0.65,
		"master_volume":0.8, "music_volume":0.5, "sfx_volume":0.85
	}

static func defaults() -> Dictionary:
	return {
		"schema_version":SCHEMA_VERSION,
		"selected_car":"aventador_svj",
		"unlocked_cars":["aventador_svj", "mclaren_senna"],
		"credits":0,
		"completed_events":{},
		"settings":default_settings()
	}

static func _valid_int(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var n := float(value)
	return not is_nan(n) and not is_inf(n) and n >= 0.0 and n <= float(maximum) and n == floorf(n)

static func _valid_unit(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var n := float(value)
	return not is_nan(n) and not is_inf(n) and n >= 0.0 and n <= 1.0

static func is_valid_v2(payload: Variant, allow_retired: bool = false) -> bool:
	var valid_cars: Array = LEGACY_CAR_IDS if allow_retired else Catalog.car_ids()
	if not (payload is Dictionary):
		return false
	if not _valid_int(payload.get("schema_version"), SCHEMA_VERSION) or int(payload["schema_version"]) != SCHEMA_VERSION:
		return false
	if not (payload.get("selected_car") is String):
		return false
	if not valid_cars.has(payload["selected_car"]):
		return false
	var unlocked: Variant = payload.get("unlocked_cars")
	if not (unlocked is Array) or unlocked.is_empty() or unlocked.size() > valid_cars.size():
		return false
	var unique := {}
	for id in unlocked:
		if not (id is String) or not valid_cars.has(id) or unique.has(id):
			return false
		unique[id] = true
	if not unique.has(payload["selected_car"]):
		return false
	if not _valid_int(payload.get("credits"), 1000000000):
		return false
	var completed: Variant = payload.get("completed_events")
	if not (completed is Dictionary) or completed.size() > Catalog.event_ids().size():
		return false
	for event_id in completed.keys():
		if not (event_id is String) or not Catalog.event_ids().has(event_id):
			return false
		var record: Variant = completed[event_id]
		if not (record is Dictionary):
			return false
		if not _valid_int(record.get("completions"), 1000000) or int(record["completions"]) < 1:
			return false
		if not _valid_int(record.get("wins"), 1000000) or int(record["wins"]) > int(record["completions"]):
			return false
		var time: Variant = record.get("best_time_s")
		if typeof(time) != TYPE_FLOAT and typeof(time) != TYPE_INT:
			return false
		if is_nan(float(time)) or is_inf(float(time)) or float(time) <= 0.0 or float(time) > 10000000.0:
			return false
	var settings: Variant = payload.get("settings")
	if not (settings is Dictionary):
		return false
	if not (settings.get("graphics_quality") is String) or not GRAPHICS.has(settings["graphics_quality"]):
		return false
	if not (settings.get("window_mode") is String) or not MODES.has(settings["window_mode"]):
		return false
	if not (settings.get("resolution") is String) or not RESOLUTIONS.has(settings["resolution"]):
		return false
	for key in ["controller_sensitivity", "master_volume", "music_volume", "sfx_volume"]:
		if not _valid_unit(settings.get(key)):
			return false
	return true

static func _migrate_v1(source: Dictionary) -> Dictionary:
	## V1 accepted selected_vehicle, unlocked_vehicles, options, race_records.
	var next := defaults()
	var picked: Variant = source.get("selected_vehicle", source.get("selected_car", "vela_gt"))
	var cars: Variant = source.get("unlocked_vehicles", source.get("unlocked_cars", ["vela_gt"]))
	if cars is Array:
		for car_id in cars:
			if car_id is String and Catalog.car_ids().has(car_id) and not next["unlocked_cars"].has(car_id):
				next["unlocked_cars"].append(car_id)
	if picked is String and next["unlocked_cars"].has(picked):
		next["selected_car"] = picked
	if _valid_int(source.get("credits", 0), 1000000000):
		next["credits"] = int(source.get("credits", 0))
	var old_settings: Variant = source.get("options", source.get("settings", {}))
	if old_settings is Dictionary:
		for key in next["settings"].keys():
			if old_settings.has(key):
				var candidate: Variant = old_settings[key]
				if key == "graphics_quality" and candidate is String and GRAPHICS.has(candidate):
					next["settings"][key] = candidate
				elif key == "window_mode" and candidate is String and MODES.has(candidate):
					next["settings"][key] = candidate
				elif key == "resolution" and candidate is String and RESOLUTIONS.has(candidate):
					next["settings"][key] = candidate
				elif ["controller_sensitivity", "master_volume", "music_volume", "sfx_volume"].has(key) and _valid_unit(candidate):
					next["settings"][key] = float(candidate)
	var old_records: Variant = source.get("race_records", source.get("completed_events", {}))
	if old_records is Dictionary:
		for event_id in old_records.keys():
			if not Catalog.event_ids().has(event_id):
				continue
			var old: Variant = old_records[event_id]
			var time: Variant = old
			var wins := 0
			var completions := 1
			if old is Dictionary:
				time = old.get("best_time_s", old.get("best_time", 0.0))
				if _valid_int(old.get("completions", 1), 1000000):
					completions = maxi(1, int(old.get("completions", 1)))
				if _valid_int(old.get("wins", 0), 1000000):
					wins = mini(completions, int(old.get("wins", 0)))
			if (typeof(time) == TYPE_FLOAT or typeof(time) == TYPE_INT) and float(time) > 0.0 and not is_nan(float(time)) and not is_inf(float(time)) and float(time) <= 10000000.0:
				next["completed_events"][event_id] = {"best_time_s":float(time), "completions":completions, "wins":wins}
	return next

static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null

static func _decode(text: String):
	var value: Variant = _parse_json(text)
	if not (value is Dictionary):
		return null
	var version: Variant = value.get("schema_version", 1)
	if not _valid_int(version, SCHEMA_VERSION):
		return null
	var decoded: Dictionary = value
	if int(version) == 1:
		decoded = _migrate_v1(value)
	if not is_valid_v2(decoded, true):
		return null
	decoded = decoded.duplicate(true)
	if not Catalog.car_ids().has(decoded["selected_car"]):
		decoded["selected_car"] = "aventador_svj"
	decoded["unlocked_cars"] = Catalog.car_ids()
	return decoded

func _read_candidate(candidate_path: String):
	if not FileAccess.file_exists(candidate_path):
		return null
	return _decode(FileAccess.get_file_as_string(candidate_path))

func load() -> Dictionary:
	last_error = ""
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		var loaded: Variant = _read_candidate(candidate)
		if loaded is Dictionary:
			data = loaded
			var recovered := candidate != path
			var original: Variant = _parse_json(FileAccess.get_file_as_string(candidate))
			var migrated: bool = original is Dictionary and (int(original.get("schema_version", 1)) == 1 or original.get("selected_car") != loaded["selected_car"] or original.get("unlocked_cars") != loaded["unlocked_cars"])
			last_status = "recovered_temp" if candidate.ends_with(".tmp") else ("recovered_backup" if recovered else ("migrated_profile" if migrated else "loaded"))
			## Promote migration or recovery to canonical format, with validated backup.
			if recovered or migrated:
				_commit(false)
			return data.duplicate(true)
	var any_file := FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")
	data = defaults()
	last_status = "reset_corrupt" if any_file else "new_profile"
	if any_file:
		last_error = "No valid primary, temp, or backup save. Default profile loaded."
	return data.duplicate(true)

func save() -> bool:
	if not is_valid_v2(data):
		last_error = "Save refused: invalid schema or values."
		return false
	return _commit(true)

func _commit(rotate_backup: bool) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		last_error = "Unable to create save directory (%d)." % error
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Unable to open temporary save (%d)." % FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
	if not (_read_candidate(temporary) is Dictionary):
		last_error = "Temporary save failed read-back validation."
		return false
	var source_exists := FileAccess.file_exists(path)
	var primary_valid := source_exists and _read_candidate(path) is Dictionary
	var backup_valid := _read_candidate(path + ".bak") is Dictionary
	if primary_valid and (rotate_backup or not backup_valid):
		## A validated backup is required before Windows replace fallback, even
		## when promoting a migrated v1 primary or a recovered temp.
		error = DirAccess.copy_absolute(absolute, ProjectSettings.globalize_path(path + ".bak"))
		if error != OK or not (_read_candidate(path + ".bak") is Dictionary):
			last_error = "Could not preserve last valid save."
			return false
		backup_valid = true
	## Corrupt originals are never silently overwritten even on POSIX, where rename
	## can atomically replace a destination; preserve forensic recovery evidence.
	if source_exists and not primary_valid:
		var quarantine := absolute + ".corrupt." + str(Time.get_unix_time_from_system())
		if DirAccess.rename_absolute(absolute, quarantine) != OK:
			last_error = "Could not quarantine corrupt primary."
			return false
		source_exists = false
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if error != OK and source_exists:
		if primary_valid and not backup_valid:
			last_error = "Cannot replace save without a valid backup."
			return false
		if not primary_valid:
			## Quarantine, never erase, the corrupt original.
			var quarantine := absolute + ".corrupt." + str(Time.get_unix_time_from_system())
			if DirAccess.rename_absolute(absolute, quarantine) != OK:
				last_error = "Could not quarantine corrupt primary."
				return false
		else:
			if DirAccess.remove_absolute(absolute) != OK:
				last_error = "Could not replace existing save."
				return false
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if error != OK:
		last_error = "Could not publish temporary save (%d); recovery file retained." % error
		return false
	last_error = ""
	return true

func selected_car() -> String:
	return str(data.get("selected_car", "aventador_svj"))

func is_unlocked(car_id: String) -> bool:
	return data.get("unlocked_cars", []).has(car_id)

func select_car(car_id: String) -> bool:
	if not Catalog.car_ids().has(car_id) or not is_unlocked(car_id):
		last_error = "Vehicle is locked or unknown."
		return false
	var before := data.duplicate(true)
	data["selected_car"] = car_id
	if not save():
		data = before
		return false
	return true

func set_setting(key: String, value: Variant) -> bool:
	if not data["settings"].has(key):
		last_error = "Unknown setting."
		return false
	var before := data.duplicate(true)
	data["settings"][key] = value
	if not is_valid_v2(data) or not save():
		data = before
		last_error = "Setting not saved: invalid value or disk error."
		return false
	return true

func record_race(event_id: String, time_s: float, position: int) -> Dictionary:
	if not Catalog.event_ids().has(event_id) or is_nan(time_s) or is_inf(time_s) or time_s <= 0.0 or time_s > 10000000.0 or position < 1 or position > 6:
		last_error = "Rejected invalid race result."
		return {"ok":false, "new_unlocks":[]}
	var prior := data.duplicate(true)
	var old_unlocks: Array = data["unlocked_cars"].duplicate()
	var records: Dictionary = data["completed_events"]
	var rec: Dictionary = records.get(event_id, {"best_time_s":time_s, "wins":0, "completions":0})
	rec["best_time_s"] = minf(float(rec["best_time_s"]), time_s)
	rec["completions"] = int(rec["completions"]) + 1
	if position == 1:
		rec["wins"] = int(rec["wins"]) + 1
	records[event_id] = rec
	var reward := 300 + (150 if position == 1 else 0)
	data["credits"] = mini(1000000000, int(data["credits"]) + reward)
	if not save():
		data = prior
		return {"ok":false, "new_unlocks":[]}
	var new_unlocks: Array = []
	for id in data["unlocked_cars"]:
		if not old_unlocks.has(id):
			new_unlocks.append(id)
	return {"ok":true, "reward":reward, "new_unlocks":new_unlocks, "best_time_s":rec["best_time_s"]}
