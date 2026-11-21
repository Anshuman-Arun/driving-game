extends SceneTree
## Graphical regression. Run on a desktop with -- --capture-dir <existing folder>.
const Demo = preload("res://scenes/demo.tscn")

var app: Control
var failures := 0
var captures := 0
var folder := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 3:
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await _settle()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _settle()

func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	await _settle()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _settle()

func _focus_text() -> String:
	var focused := root.gui_get_focus_owner() as Button
	return focused.text if focused else ""

func _capture(size_label: String, name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size_parts := size_label.split("x")
	var expected := Vector2i(int(size_parts[0]), int(size_parts[1]))
	_check(image.get_size() == expected, "Screenshot dimensions %s expected %s" % [image.get_size(), expected])
	_check(image.save_png(folder.path_join("%s-%s.png" % [size_label, name])) == OK, "PNG written")
	captures += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var verify := args.find("--verify-profile")
	if verify >= 0 and verify + 1 < args.size():
		await _verify_profile(args[verify + 1])
		print("GAME SHELL RESTART: %d failures" % failures)
		quit(0 if failures == 0 else 1)
		return
	var option := args.find("--capture-dir")
	if DisplayServer.get_name() == "headless" or option < 0 or option + 1 >= args.size():
		push_error("Run using a graphical backend and -- --capture-dir <existing folder>")
		quit(2)
		return
	folder = args[option + 1]
	for size_label in ["1280x720", "1600x900", "1920x1080"]:
		await _exercise(size_label)
	print("GAME SHELL VISUAL: %d screenshots, %d failures" % [captures, failures])
	quit(0 if failures == 0 else 1)

func _new_demo(profile: String) -> void:
	app = Demo.instantiate()
	app.save_path = profile
	root.add_child(app)
	await _settle()

func _exercise(size_label: String) -> void:
	var profile := "user://visual_qa_%s_%d.json" % [size_label, Time.get_ticks_usec()]
	await _new_demo(profile)
	app._save_option("resolution", size_label)
	await _settle()
	_check(_focus_text().begins_with("PLAY"), "Main menu gives Play initial focus")
	await _capture(size_label, "menu")

	await _key(KEY_DOWN)
	_check(_focus_text().begins_with("GARAGE"), "Down moves focus to Garage")
	await _key(KEY_ENTER)
	_check(app.screen == "GARAGE", "Keyboard enters Garage")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _key(KEY_ENTER)
	_check(app.inspected_car == "orion_rs", "Keyboard inspects the Orion")
	_check(_focus_text().begins_with("ORION"), "Inspecting Orion preserves focus on its row")
	await _capture(size_label, "garage")
	await _key(KEY_ESCAPE)

	await _key(KEY_ENTER)
	_check(app.screen == "FREE_ROAM", "Play opens free roam")
	await _key(KEY_ESCAPE)
	_check(app.screen == "PAUSE" and app.game.paused, "Escape pauses free roam")
	await _capture(size_label, "pause")
	await _pad(JOY_BUTTON_START)
	_check(app.screen == "FREE_ROAM" and not app.game.paused, "Synthetic Start resumes free roam")
	await _key(KEY_E)
	_check(app.screen == "EVENTS", "E discovers races")
	var event_scroll: ScrollContainer = app.find_children("*", "ScrollContainer", true, false)[0]
	_check(event_scroll.get_global_rect().encloses(root.gui_get_focus_owner().get_global_rect()),
		"Initial event focus is visible")
	await _capture(size_label, "events")
	await _pad(JOY_BUTTON_A)
	_check(app.screen == "RACE" and app.game.stage == "COUNTDOWN", "Synthetic A starts focused event")
	var race_scroll: ScrollContainer = app.find_children("*", "ScrollContainer", true, false)[0]
	_check(race_scroll.get_global_rect().encloses(app.countdown_label.get_global_rect()),
		"Countdown is visible without scrolling")
	_check(race_scroll.get_global_rect().encloses(app.map_view.get_global_rect()),
		"Race minimap is visible without scrolling")
	await _capture(size_label, "race-countdown")
	await _key(KEY_ESCAPE)
	var countdown: float = app.game.countdown_s
	app.game.advance(20.0)
	_check(app.screen == "PAUSE" and app.game.countdown_s == countdown, "Race pause freezes countdown")
	await _pad(JOY_BUTTON_B)
	app.game.advance(4.0)
	await _key(KEY_F)
	_check(app.screen == "RESULTS" and app.game.result.get("record_saved", false), "Mock result persisted")
	await _capture(size_label, "results")
	app._return_from_race()

	for event_id in ["ridge_climb", "eastwater_dash"]:
		app.open_events()
		app._start_event(event_id)
		app.game.advance(4.0)
		app.game.finish_event()
		app._return_from_race()
	app.open_garage()
	await _settle()
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	_check(_focus_text() == "SELECT VEHICLE", "Keyboard reaches garage selection")
	await _key(KEY_ENTER)
	_check(app.save.selected_car() == "orion_rs", "Keyboard selects an unlocked vehicle")
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_check(app.save.selected_car() == "kestrel_xr", "All three garage cars reachable and unlocked choices persist")
	await _capture(size_label, "garage-unlocked")

	app._main_menu()
	await _settle()
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(app.screen == "SETTINGS", "Keyboard opens Settings")
	var quality := root.gui_get_focus_owner() as OptionButton
	_check(quality != null, "Quality dropdown receives focus")
	if quality:
		await _key(KEY_ENTER)
		var popup := quality.get_popup()
		_check(popup.visible, "Keyboard opens quality popup")
		await _key(KEY_DOWN)
		await _key(KEY_ENTER)
		_check(not popup.visible and app.save.data["settings"]["graphics_quality"] == "high",
			"Keyboard closes the dropdown and commits its quality choice")
		_check(root.gui_get_focus_owner() == quality, "Focus returns to the dropdown")
	var sliders := app.find_children("*", "HSlider", true, false)
	sliders[0].grab_focus()
	for step in 4:
		await _key(KEY_LEFT)
	_check(is_equal_approx(float(app.save.data["settings"]["controller_sensitivity"]), 0.45),
		"Keyboard updates and persists the sensitivity slider")
	app._save_option("window_mode", "fullscreen")
	await _settle()
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen setting applied")
	app._save_option("window_mode", "windowed")
	await _settle()
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Windowed setting applied")
	app._save_option("master_volume", 0.75)
	await _capture(size_label, "settings")
	var settings_scroll: ScrollContainer = app.find_children("*", "ScrollContainer", true, false)[0]
	for step in 4:
		await _key(KEY_DOWN)
	_check(_focus_text() == "SAVE & BACK", "Settings footer action is reachable by keyboard")
	_check(settings_scroll.get_global_rect().encloses(root.gui_get_focus_owner().get_global_rect()),
		"Settings scroll follows keyboard focus")
	await _capture(size_label, "settings-scrolled")
	app.queue_free()
	await _settle()

	# Deliberately damage only the isolated test profile. The previous save contains
	# the selected car, resolution and sensitivity.
	var damaged := FileAccess.open(profile, FileAccess.WRITE)
	_check(damaged != null, "QA corrupt-save fixture created")
	if damaged:
		damaged.store_string("{ truncated QA fixture")
		damaged.close()
	await _new_demo(profile)
	_check(app.save.last_status == "recovered_backup", "Fresh shell recovers corrupt profile from backup")
	_check(app.save.selected_car() == "kestrel_xr", "Recovered profile restores car")
	_check(is_equal_approx(float(app.save.data["settings"]["controller_sensitivity"]), 0.45), "Recovered profile restores sensitivity")
	_check(app.save.data["settings"]["resolution"] == size_label, "Recovered profile restores resolution")
	_check(app.save.last_error.is_empty(), "Recovery can republish primary")
	if size_label == "1920x1080":
		print("RESTART PROFILE ", profile)
	await _capture(size_label, "recovered-menu")
	app.queue_free()
	await _settle()

func _verify_profile(profile: String) -> void:
	await _new_demo(profile)
	_check(app.save.last_status == "loaded", "Repaired primary loads in a fresh process")
	_check(app.save.selected_car() == "kestrel_xr", "Selected car survives process restart")
	_check(app.save.data["settings"]["graphics_quality"] == "high", "Graphics quality survives process restart")
	_check(app.save.data["settings"]["resolution"] == "1920x1080", "Resolution survives process restart")
	_check(is_equal_approx(float(app.save.data["settings"]["controller_sensitivity"]), 0.45),
		"Sensitivity survives process restart")
	app.queue_free()
	await _settle()
