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

func _navigation(root: VBoxContainer, active: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	_label(row, "ASTER VALLEY   /   OPEN ROAD", 13, ShellTheme.TEAL)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_nav_tab(row, "HOME", _main_menu, active == "HOME")
	_nav_tab(row, "GARAGE", open_garage, active == "GARAGE")
	_nav_tab(row, "SETTINGS", open_settings, active == "SETTINGS")

func _nav_tab(parent: Node, title: String, on_press: Callable, selected: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(104, 38)
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", ShellTheme.TEXT if selected else ShellTheme.MUTED)
	button.add_theme_stylebox_override("normal", ShellTheme.box(
		ShellTheme.PANEL_ALT if selected else Color.TRANSPARENT,
		ShellTheme.TEAL if selected else Color.TRANSPARENT, 6, 10))
	button.add_theme_stylebox_override("hover", ShellTheme.box(ShellTheme.PANEL_ALT, ShellTheme.ACCENT, 6, 10))
	button.add_theme_stylebox_override("pressed", ShellTheme.box(ShellTheme.TEAL, ShellTheme.TEAL, 6, 10))
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button

func _surface_ratio(inner: VBoxContainer, ratio: float) -> void:
	var panel := inner.get_parent().get_parent() as Control
	if panel != null:
		panel.size_flags_stretch_ratio = ratio

func _metric(parent: Node, caption: String, value: String) -> void:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	_label(block, caption, 11, ShellTheme.MUTED)
	_label(block, value, 19, ShellTheme.TEXT)

func _menu(root: VBoxContainer) -> void:
	_navigation(root, "HOME")
	var body := _columns(root)
	var intro := _surface(body, Vector2(300, 390))
	_surface_ratio(intro, 0.78)
	_label(intro, "FREE ROAM   /   ALDER TOWN", 14, ShellTheme.TEAL)
	_label(intro, "TAKE THE\nSCENIC ROUTE.", 48)
	_label(intro, "A mountain valley made for the drive you choose. Find your line through town, forest and ridge.", 16, ShellTheme.MUTED)
	_spacer(intro)
	var credentials := HBoxContainer.new()
	credentials.add_theme_constant_override("separation", 10)
	intro.add_child(credentials)
	_label(credentials, "OFFLINE", 12, ShellTheme.ACCENT)
	_label(credentials, "3 ORIGINAL CARS", 12, ShellTheme.TEAL)
	_label(credentials, "FREE ROAM", 12, ShellTheme.MUTED)
	var start := _action(intro, "START DRIVING   /   FREE ROAM", enter_free_roam, true)
	start.custom_minimum_size = Vector2(0, 58)
	var shortcuts := HBoxContainer.new()
	shortcuts.add_theme_constant_override("separation", 10)
	intro.add_child(shortcuts)
	_action(shortcuts, "GARAGE   /   03 CARS", open_garage)
	_action(shortcuts, "SETTINGS", open_settings)
	_action(intro, "QUIT TO DESKTOP", func(): get_tree().quit())
	var showcase := _surface(body, Vector2(360, 390))
	_surface_ratio(showcase, 1.22)
	var car_id := save.selected_car()
	var car_info: Dictionary = Catalog.car(car_id)
	var preset: Dictionary = PlayerCarFactory.PRESETS[car_id]
	var frame := HBoxContainer.new()
	showcase.add_child(frame)
	_label(frame, "LIVE SHOWROOM", 13, ShellTheme.TEAL)
	var live_tag := _label(frame, "CURRENT VEHICLE", 12, ShellTheme.MUTED)
	live_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(showcase, str(car_info.get("class", "SPORTS CAR")).to_upper(), 13, ShellTheme.ACCENT)
	_label(showcase, Catalog.car_name(car_id), 30)
	_preview(showcase, car_id)
	var specs := HBoxContainer.new()
	specs.add_theme_constant_override("separation", 14)
	showcase.add_child(specs)
	_metric(specs, "TORQUE", "%d Nm" % roundi(float(preset["torque"])))
	_metric(specs, "WEIGHT", "%d kg" % roundi(float(preset["mass"])))
	_metric(specs, "DRIVE", "AWD" if float(preset["front_split"]) > 0.0 else "RWD")
	_footer(root, "ENTER / A DRIVE   •   GARAGE TO CHANGE CAR   •   ESC / B BACK   •   F11 FULLSCREEN")

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
	view.fov = 43.0
	view.position = Vector3(5.0, 2.7, 6.2)
	view.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)

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
	_navigation(root, "GARAGE")
	_heading(root, "YOUR GARAGE", "Choose the car you want to take into Aster Valley.")
	var body := _columns(_scroll(root))
	var collection := _surface(body, Vector2(260, 360))
	_surface_ratio(collection, 0.72)
	_label(collection, "YOUR COLLECTION   /   03", 13, ShellTheme.ACCENT)
	var cars: Array = Catalog.CARS
	for index in range(cars.size()):
		var item: Dictionary = cars[index]
		var id := str(item["id"])
		var info: Dictionary = Catalog.car(id)
		var status := "CURRENT" if save.selected_car() == id else "READY"
		var card := _action(collection, "%02d   /   %s   •   %s" % [
			index + 1, Catalog.car_name(id).to_upper(), status],
			_inspect.bind(id), inspected_car == id)
		card.custom_minimum_size = Vector2(0, 58)
		card.add_theme_font_size_override("font_size", 16)
		_label(collection, str(info.get("class", "SPORTS CAR")).to_upper() + "   •   " + str(info.get("tagline", "")), 12, ShellTheme.MUTED)
		if inspected_car == id:
			first_focus = card
	_spacer(collection)
	_label(collection, "SELECT A VEHICLE TO VIEW ITS LIVE SHOWROOM MODEL.", 12, ShellTheme.TEAL)
	_action(collection, "BACK TO HOME", _main_menu)

	var details := _surface(body, Vector2(360, 430))
	_surface_ratio(details, 1.28)
	var info: Dictionary = Catalog.car(inspected_car)
	var preset: Dictionary = PlayerCarFactory.PRESETS[inspected_car]
	_label(details, str(info.get("class", "SPORTS CAR")).to_upper() + "   /   ASTER VALLEY COLLECTION", 13, ShellTheme.TEAL)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	details.add_child(title_row)
	var title := _label(title_row, Catalog.car_name(inspected_car), 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choice := "CURRENT CAR" if save.selected_car() == inspected_car else "SELECT THIS CAR"
	var select := _action(title_row, choice, _choose_car, true)
	select.size_flags_horizontal = Control.SIZE_SHRINK_END
	select.custom_minimum_size = Vector2(220, 54)
	_label(details, str(info.get("tagline", "")), 16, ShellTheme.MUTED)
	_preview(details, inspected_car)
	var specs := HBoxContainer.new()
	specs.add_theme_constant_override("separation", 14)
	details.add_child(specs)
	_metric(specs, "POWER", "%d hp" % int(info.get("power_hp", 0)))
	_metric(specs, "TORQUE", "%d Nm" % roundi(float(preset["torque"])))
	_metric(specs, "WEIGHT", "%d kg" % roundi(float(preset["mass"])))
	_metric(specs, "DRIVETRAIN", "AWD" if float(preset["front_split"]) > 0.0 else "RWD")
	if save.selected_car() == inspected_car:
		_label(details, "ACTIVE FOR YOUR NEXT DRIVE", 12, ShellTheme.ACCENT)
	if not game.notification.is_empty():
		_label(details, game.notification, 14, ShellTheme.TEAL)
	_footer(root, "↑ / ↓ CHOOSE CAR   •   ENTER / A SELECT   •   ESC / B BACK")

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
