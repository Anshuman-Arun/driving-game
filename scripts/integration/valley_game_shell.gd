extends "res://modules/game_shell/scripts/game_shell.gd"
## Hosts the corrected shell and connects it to the real free-roam scene.

const FreeRoam = preload("res://scenes/free_roam/aster_valley.tscn")
const Drive = preload("aster_valley_drive.gd")
const CuratedCar = preload("curated_car_visual.gd")
const LIVE_SAVE_PATH := "user://aster_valley_free_roam_v2.json"

## Emitted before the world enters the tree so presentation can subscribe to its first chassis.
signal free_roam_created(world_drive: Drive)

class LiveSession extends RefCounted:
	var drive: Drive
	var paused := true
	var notification := ""
	var notification_s := 0.0
	var stage := "FREE_ROAM"

	var speed_kph: float:
		get:
			return drive.adapter.get_speed_mps() * 3.6 if drive != null and drive.adapter != null else 0.0

	func set_paused(value: bool) -> void:
		paused = value
		if drive != null:
			drive.get_tree().paused = value

	func set_notice(text: String) -> void:
		notification = text
		notification_s = 4.0

var drive: Drive

func _init() -> void:
	save_path = LIVE_SAVE_PATH

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellTheme.make()
	_register_input_defaults()
	save = SaveService.new(save_path)
	save.load()
	# Free roam has its own profile and no race progression. All presets are available.
	save.data["unlocked_cars"] = Catalog.car_ids()
	if save.last_status == "new_profile":
		save.data["settings"]["resolution"] = "1600x900"
	inspected_car = save.selected_car()
	game = LiveSession.new()
	_apply_all_settings()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_render()

func _input(event: InputEvent) -> void:
	# B is the handbrake on the road and Back only when a menu is open.
	if screen == "FREE_ROAM" and event.is_action("shell_back") and event is InputEventJoypadButton:
		return
	if event.is_action("shell_interact") or event.is_action("shell_map") or event.is_action("shell_finish_mock"):
		return
	super._input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	# The standing world owns F11 once it exists.
	if drive == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		window.set_input_as_handled()

func _apply_all_settings() -> void:
	var launched_fullscreen := get_window().mode == Window.MODE_FULLSCREEN
	super._apply_all_settings()
	if launched_fullscreen:
		get_window().mode = Window.MODE_FULLSCREEN

func _process(delta: float) -> void:
	if screen != "FREE_ROAM":
		return
	game.notification_s = maxf(0.0, game.notification_s - delta)
	if drive == null or drive.adapter == null:
		speed_label.text = "Loading Aster Valley…"
		return
	speed_label.text = "%03d km/h   •   GEAR %s" % [roundi(game.speed_kph), drive.adapter.get_gear_display()]
	car_label.text = Catalog.car_name(drive.active_vehicle_id)
	notification_label.text = game.notification if game.notification_s > 0.0 else ""

func _render() -> void:
	if screen != "FREE_ROAM":
		mouse_filter = Control.MOUSE_FILTER_STOP
		super._render()
		return
	# Leave the 3D world visible and use the Shell theme for live telemetry.
	var stack := _base()
	get_child(0).hide() # Opaque page backdrop.
	get_child(1).hide() # Page header band.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in find_children("*", "Control", true, false):
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_label = _label(stack, Catalog.car_name(save.selected_car()), 19, ShellTheme.ACCENT)
	speed_label = _label(stack, "Loading Aster Valley…", 27)
	notification_label = _label(stack, "", 16, ShellTheme.TEAL)
	_spacer(stack)
	_footer(stack, "WASD DRIVE   •   SPACE HANDBRAKE   •   C CAMERA   •   R RESET   •   G GARAGE WHILE PARKED   •   ESC PAUSE   •   F11 FULLSCREEN")
	for node in stack.get_children():
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node is Label:
			node.add_theme_color_override("font_shadow_color", Color.BLACK)
			node.add_theme_constant_override("shadow_offset_x", 2)
			node.add_theme_constant_override("shadow_offset_y", 2)

func _menu(root: VBoxContainer) -> void:
	var body := _columns(_scroll(root))
	var left := _surface(body, Vector2(290, 450))
	_heading(left, "ASTER\nVALLEY", "Explore the valley in your selected car.")
	_spacer(left)
	_action(left, "PLAY  /  FREE ROAM", enter_free_roam, true)
	_action(left, "GARAGE  /  03 VEHICLES", open_garage)
	_action(left, "SETTINGS", open_settings)
	_action(left, "QUIT TO DESKTOP", func(): get_tree().quit())
	var right := _surface(body, Vector2(320, 420))
	_label(right, "CURRENT DRIVE   •   " + Catalog.car_name(save.selected_car()), 16, ShellTheme.ACCENT)
	_preview(right, save.selected_car())
	_footer(root)

func _preview(parent: Node, car_id: String) -> void:
	var preview := Preview.new()
	parent.add_child(preview)
	preview.set_quality(_quality_scale())
	var model := CuratedCar.load_model(car_id)
	if model == null:
		preview.set_car(car_id)
		return
	for child in preview.turntable.get_children():
		preview.turntable.remove_child(child)
		child.queue_free()
	preview.turntable.add_child(model)
	preview.turntable.rotation.y = 3.12
	var view := preview.viewport.get_camera_3d()
	view.keep_aspect = Camera3D.KEEP_WIDTH
	view.fov = 42.0
	view.position = Vector3(5.0, 2.7, 6.2)
	view.look_at(Vector3(0.0, 0.72, 0.0))

func enter_free_roam() -> void:
	if drive == null:
		drive = FreeRoam.instantiate()
		drive.shell_managed = true
		drive.scenery_enabled = bool(ProjectSettings.get_setting("aster_valley/visuals/scenery_enabled", true))
		drive.queue_vehicle_selection(save.selected_car())
		game.drive = drive
		free_roam_created.emit(drive)
		get_parent().add_child(drive)
	super.enter_free_roam()

func open_garage() -> void:
	super.open_garage()
	if screen == "GARAGE":
		game.set_paused(true)

func _garage(root: VBoxContainer) -> void:
	_heading(root, "THE GARAGE", "Select a car. Your choice is saved for the next drive.")
	var body := _columns(_scroll(root))
	var collection := _surface(body, Vector2(290, 350))
	for spec: Dictionary in Catalog.CARS:
		var id: String = spec["id"]
		var title: String = spec["name"]
		if save.selected_car() == id:
			title += "  /  ACTIVE"
		var car_button := _action(collection, title, _inspect.bind(id), inspected_car == id)
		if inspected_car == id:
			first_focus = car_button
	_spacer(collection)
	_action(collection, "BACK", _go_back)
	var details := _surface(body, Vector2(340, 350))
	var preset: Dictionary = PlayerCarFactory.PRESETS[inspected_car]
	_label(details, Catalog.car_name(inspected_car), 34)
	_label(details, "%d kg    •    %d Nm    •    %s" % [
		preset["mass"], preset["torque"], "AWD" if preset["front_split"] > 0.0 else "RWD"], 16, ShellTheme.TEAL)
	_action(details, "SELECT VEHICLE", _choose_car, true)
	_preview(details, inspected_car)
	if not game.notification.is_empty():
		_label(details, game.notification, 15, ShellTheme.TEAL)
	_footer(root)

func _choose_car() -> void:
	if screen != "GARAGE" or game.speed_kph > 4.0 or not PlayerCarFactory.PRESETS.has(inspected_car):
		return
	if save.select_car(inspected_car):
		if drive != null:
			drive.queue_vehicle_selection(inspected_car)
		game.set_notice(Catalog.car_name(inspected_car) + " READY TO DRIVE")
	else:
		game.set_notice(save.last_error)
	_render()

func _main_menu() -> void:
	game.set_paused(true)
	screen = "MENU"
	_render()

func _go_back() -> void:
	super._go_back()
	game.set_paused(screen != "FREE_ROAM")
