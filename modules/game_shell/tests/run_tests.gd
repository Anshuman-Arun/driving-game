extends SceneTree
## Execute: godot --headless --path modules/game_shell --script res://tests/run_tests.gd
const Save = preload("../scripts/save_service.gd")
const Mock = preload("../scripts/mock_game_state.gd")
const Shell = preload("../scripts/game_shell.gd")

var checks := 0
var fails: Array[String] = []
var test_root: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		fails.append(message)
		push_error("FAIL: " + message)

func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fails.append("Failed to create fixture " + path)
		return
	f.store_string(text)
	f.flush()
	f.close()

func _run() -> void:
	test_root = "user://game_shell_test_" + str(Time.get_ticks_usec())
	var path := test_root + "/profile.json"
	var service := Save.new(path)
	var start: Dictionary = service.load()
	_ok(service.last_status == "new_profile", "Missing save defaults")
	_ok(start["selected_car"] == "vela_gt" and service.is_unlocked("vela_gt"), "Starting car unlocked")
	_ok(not service.select_car("orion_rs"), "Locked car cannot be selected")
	_ok(service.save(), "Fresh save writes")
	_ok(service.set_setting("graphics_quality", "low"), "Setting change writes")
	_ok(service.set_setting("controller_sensitivity", 0.35), "Sensitivity change writes")
	var reopened := Save.new(path)
	reopened.load()
	_ok(reopened.data["settings"]["graphics_quality"] == "low" and is_equal_approx(float(reopened.data["settings"]["controller_sensitivity"]), 0.35), "Settings survive reload")
	_ok(not reopened.set_setting("resolution", "7680x4320"), "Unknown resolution rejected")
	_ok(reopened.data["settings"]["resolution"] == "1280x720", "Invalid setting rolled back")
	var event1: Dictionary = reopened.record_race("alder_circuit", 57.8, 2)
	_ok(bool(event1.get("ok", false)), "Completed race persisted")
	_ok(reopened.is_unlocked("orion_rs") and not reopened.is_unlocked("kestrel_xr"), "First unique event unlocks Orion")
	_ok(reopened.select_car("orion_rs"), "Unlocked car selectable")
	_ok(bool(reopened.record_race("alder_circuit", 61.2, 1).get("ok", false)), "Second result persists")
	_ok(is_equal_approx(float(reopened.data["completed_events"]["alder_circuit"]["best_time_s"]), 57.8), "Best time not overwritten by slower replay")
	_ok(int(reopened.data["completed_events"]["alder_circuit"]["wins"]) == 1, "Win counted correctly")
	_ok(bool(reopened.record_race("ridge_climb", 48.1, 3).get("ok", false)), "Second distinct event")
	_ok(bool(reopened.record_race("eastwater_dash", 39.1, 1).get("ok", false)), "Third distinct event")
	_ok(reopened.is_unlocked("kestrel_xr"), "Third distinct event unlocks Kestrel")
	_ok(reopened.select_car("kestrel_xr"), "Kestrel selection persisted")
	var reread := Save.new(path)
	reread.load()
	_ok(reread.selected_car() == "kestrel_xr" and reread.is_unlocked("kestrel_xr"), "Unlock and selection survive restart")
	_ok(FileAccess.file_exists(path + ".bak"), "Valid backup retained")

	## Corrupt primary: recover validated previous save, not garbage.
	_put(path, "{ incomplete")
	var damaged := Save.new(path)
	var recovered: Dictionary = damaged.load()
	_ok(damaged.last_status == "recovered_backup", "Corrupt primary recovered from backup")
	_ok(Save.is_valid_v2(recovered), "Backup recovery yields valid schema")
	_ok(Save.is_valid_v2(JSON.parse_string(FileAccess.get_file_as_string(path))), "Recovered primary written back")

	## V1 migration accepts documented older keys and produces a v2 record.
	var v1_path := test_root + "/legacy.json"
	_put(v1_path, JSON.stringify({"schema_version":1,
		"selected_vehicle":"orion_rs", "unlocked_vehicles":["vela_gt","orion_rs"],
		"credits":650, "race_records":{"alder_circuit":{"best_time":58.2, "completions":2, "wins":1}},
		"options":{"graphics_quality":"high","music_volume":0.25}}))
	var migrating := Save.new(v1_path)
	var migrated: Dictionary = migrating.load()
	_ok(int(migrated["schema_version"]) == 2 and migrating.selected_car() == "orion_rs", "V1 selected car migrates")
	_ok(int(migrated["credits"]) == 650 and is_equal_approx(float(migrated["completed_events"]["alder_circuit"]["best_time_s"]),58.2), "V1 records/credits migrate")
	_ok(is_equal_approx(float(migrated["settings"]["music_volume"]), 0.25), "V1 options migrate")
	_ok(int(JSON.parse_string(FileAccess.get_file_as_string(v1_path))["schema_version"]) == 2, "V1 persisted as v2")

	## Temp recovery after interrupted write. Backup path absent, corrupt primary quarantined.
	var temp_path := test_root + "/temp.json"
	var generated: Dictionary = Save.defaults()
	generated["credits"] = 41
	_put(temp_path, "no json")
	_put(temp_path + ".tmp", JSON.stringify(generated))
	var from_temp := Save.new(temp_path)
	var temp_result: Dictionary = from_temp.load()
	_ok(from_temp.last_status == "recovered_temp" and int(temp_result["credits"]) == 41, "Interrupted temp recovered")
	_ok(FileAccess.file_exists(temp_path) and not FileAccess.file_exists(temp_path + ".tmp"), "Recovered temp promoted")

	## Exhaust corrupted inputs, load a clean default, then overwrite by quarantine.
	var invalid_path := test_root + "/broken.json"
	_put(invalid_path, "[1, 2, 3]")
	_put(invalid_path + ".bak", "not json")
	_put(invalid_path + ".tmp", "not json")
	var invalid := Save.new(invalid_path)
	invalid.load()
	_ok(invalid.last_status == "reset_corrupt" and invalid.selected_car() == "vela_gt", "Unrecoverable save loads defaults")
	_ok(invalid.save(), "Unrecoverable profile can be saved without destructive loss")
	_ok(FileAccess.file_exists(invalid_path) and Save.is_valid_v2(JSON.parse_string(FileAccess.get_file_as_string(invalid_path))), "New valid profile written")

	## Mock-only race state, pause/resume, countdown, race result.
	var mock := Mock.new(reopened)
	_ok(mock.stage == "FREE_ROAM" and mock.start_event("ridge_climb"), "Mock starts race")
	mock.advance(1.0)
	_ok(mock.stage == "COUNTDOWN" and is_equal_approx(mock.countdown_s, 2.0), "Countdown progresses")
	mock.set_paused(true)
	mock.advance(2.5)
	_ok(is_equal_approx(mock.countdown_s, 2.0), "Pause halts countdown")
	mock.set_paused(false)
	mock.advance(2.0)
	_ok(mock.stage == "RACING", "Resume reaches race state")
	mock.advance(30.0)
	_ok(mock.stage == "RESULTS" and bool(mock.result.get("record_saved", false)), "Race ends with a persisted result")
	mock.return_to_free_roam()
	_ok(mock.stage == "FREE_ROAM", "Results return to free roam")
	_ok(not mock.start_event("unknown_race"), "Unknown event rejected")

	## Instantiate actual shell and exercise menu/pause/race transition callbacks.
	var app := Shell.new()
	get_root().add_child(app)
	_ok(app.screen == "MENU" and app.first_focus != null, "Menu created with keyboard/gamepad focus target")
	app.enter_free_roam()
	_ok(app.screen == "FREE_ROAM", "Play enters HUD")
	app.toggle_pause()
	_ok(app.screen == "PAUSE" and app.game.paused, "Pause opens and freezes mock")
	app.toggle_pause()
	_ok(app.screen == "FREE_ROAM" and not app.game.paused, "Pause resumes")
	app.open_events()
	_ok(app.screen == "EVENTS", "Race discovery accessible")
	app._start_event("eastwater_dash")
	_ok(app.screen == "RACE" and app.game.stage == "COUNTDOWN", "Race UI countdown")
	app.game.advance(30.0)
	_ok(app.screen == "RESULTS", "Results UI transition")
	app._return_from_race()
	_ok(app.screen == "FREE_ROAM", "Race returns to HUD")
	app.queue_free()

	print("GAME SHELL TESTS: %d checks, %d failures" % [checks, fails.size()])
	for failure in fails:
		print("FAIL: " + failure)
	quit(0 if fails.is_empty() else 1)
