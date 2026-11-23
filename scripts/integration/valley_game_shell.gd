extends "res://modules/game_shell/scripts/game_shell.gd"
## Hosts the corrected shell and connects it to the real free-roam scene.

const FreeRoam = preload("res://scenes/free_roam/aster_valley.tscn")
const Drive = preload("aster_valley_drive.gd")
const ValleyEnvironment = preload("aster_valley_environment.gd")
const CuratedCar = preload("curated_car_visual.gd")
const DrivingHud = preload("driving_hud.gd")
const MenuBackground = preload("res://assets/ui/dashboard/menu_background.gdshader")
const DASH_DISPLAY := preload("res://assets/ui/fonts/BarlowCondensed-BoldItalic.ttf")
const DASH_BODY := preload("res://assets/ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
const DASH_PAPER := Color("#fff6e8")
const LIVE_SAVE_PATH := "user://aster_valley_free_roam_v2.json"

const VALLEY_MAP = preload("res://assets/ui/dashboard/valley_map.svg")
const GARAGE_THUMBNAILS := {
	"vela_gt": preload("res://assets/ui/dashboard/vela_gt.png"),
	"orion_rs": preload("res://assets/ui/dashboard/orion_rs.png"),
	"kestrel_xr": preload("res://assets/ui/dashboard/kestrel_xr.png"),
}
const DASH_INK := Color("#19252a")
const DASH_MUTED := Color("#475752")
const DASH_ORANGE := Color("#ff7448")

var _hud: DrivingHud
var _hud_tick := 0.0

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
	theme.default_font = DASH_BODY
	theme.set_stylebox("slider", "HSlider", ShellTheme.box(Color("#273c49"), Color.TRANSPARENT, 4, 3))
	theme.set_stylebox("grabber_area", "HSlider", ShellTheme.box(Color("#54cdb3"), Color.TRANSPARENT, 4, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", ShellTheme.box(Color("#a1fae5"), Color.TRANSPARENT, 4, 3))
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
	# While driving in FREE_ROAM, A is Drift/Handbrake and B is unused; never let them trigger UI actions!
	if screen == "FREE_ROAM" and event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_A or jb.button_index == JOY_BUTTON_B:
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

func _apply_setting(key: String, value: Variant) -> void:
	if key == "graphics_quality":
		ValleyEnvironment.apply_quality(get_viewport(), str(value))
	elif key == "controller_sensitivity":
		if drive != null:
			drive.steering_sensitivity = float(value)
	else:
		super._apply_setting(key, value)

func _process(delta: float) -> void:
	if screen != "FREE_ROAM" or drive == null or drive.adapter == null or not is_instance_valid(_hud):
		return
	game.notification_s = maxf(0.0, game.notification_s - delta)
	_hud_tick += delta
	if _hud_tick < 1.0 / 30.0:
		return
	_hud_tick = fmod(_hud_tick, 1.0 / 30.0)
	var car := drive.adapter.vehicle
	var drift := car.get_node_or_null("DriftController")
	_hud.update_telemetry(drive.adapter.get_speed_mps(), drive.adapter.get_gear_display(),
		car.motor_rpm / maxf(car.max_rpm, 1.0), car.get_global_transform_interpolated(),
		drift != null and bool(drift.get("is_drifting")), game.notification if game.notification_s > 0.0 else "")

func _render() -> void:
	_hud = null
	if screen in ["MENU", "GARAGE", "SETTINGS", "PAUSE"]:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var root := _dashboard()
		match screen:
			"MENU": _menu(root)
			"GARAGE": _garage(root)
			"SETTINGS": _preferences(root)
			"PAUSE": _pause(root)
		if first_focus != null:
			_focus_after_layout(first_focus)
		return
	if screen != "FREE_ROAM":
		mouse_filter = Control.MOUSE_FILTER_STOP
		super._render()
		return
	_base()
	for child in get_children():
		child.hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud = DrivingHud.new()
	_hud.name = "DrivingHUD"
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_tick = 1.0

func _on_viewport_resized() -> void:
	if screen in ["MENU", "GARAGE", "SETTINGS", "PAUSE"]:
		if layout_is_narrow != _dashboard_stacked():
			_render()
		return
	super._on_viewport_resized()

func _dashboard_stacked() -> bool:
	var available := get_viewport_rect().size
	return available.x < 890.0 or available.x < available.y * 1.22

func _dashboard() -> VBoxContainer:
	var root := _base()
	layout_is_narrow = _dashboard_stacked()
	var backdrop := get_child(0) as ColorRect
	if screen == "PAUSE":
		backdrop.color = Color("#081c27b5")
	else:
		var paint := ShaderMaterial.new()
		paint.shader = MenuBackground
		backdrop.material = paint
	get_child(1).hide()
	var margin := root.get_parent() as MarginContainer
	var side := 24 if layout_is_narrow else 58
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 25)
	root.add_theme_constant_override("separation", 17)
	return root

func _dashboard_label(parent: Node, title: String, text_size: int, tint: Color, weight := 550) -> Label:
	var label := _label(parent, title, text_size, tint)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", DASH_DISPLAY if weight >= 700 and text_size >= 24 else DASH_BODY)
	return label

func _dashboard_header(root: VBoxContainer) -> Array[Button]:
	var masthead := HBoxContainer.new()
	masthead.add_theme_constant_override("separation", 13)
	root.add_child(masthead)
	var mark := _dashboard_label(masthead, "AV", 24, DASH_INK, 800)
	mark.custom_minimum_size = Vector2(51, 46)
	mark.size_flags_horizontal = Control.SIZE_FILL
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_stylebox_override("normal", ShellTheme.box(DASH_ORANGE, Color.TRANSPARENT, 3, 0))
	var wordmark := _dashboard_label(masthead, "ASTER VALLEY", 37, DASH_PAPER, 800)
	wordmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 0)
	masthead.add_child(status)
	_dashboard_label(status, "ACTIVE CAR", 13, Color("#a5cbcd"), 700).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dashboard_label(status, Catalog.car_name(save.selected_car()), 29, DASH_PAPER, 750).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", 6)
	root.add_child(rail)
	if screen == "SETTINGS":
		return [_dashboard_tab(rail, "‹  BACK", _go_back, false)]
	var home_context := screen == "MENU" or return_screen == "MENU"
	var home := _dashboard_tab(rail, "HOME" if home_context else "BACK", func():
		if screen != "MENU":
			_go_back(), screen == "MENU")
	var garage := _dashboard_tab(rail, "GARAGE", func():
		if screen != "GARAGE":
			open_garage(), screen == "GARAGE")
	# The current tab has an active indicator and is skipped by directional focus.
	home.focus_mode = Control.FOCUS_NONE if screen == "MENU" else Control.FOCUS_ALL
	garage.focus_mode = Control.FOCUS_NONE if screen == "GARAGE" else Control.FOCUS_ALL
	var line := ColorRect.new()
	line.color = Color("#a5d3cb73")
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_END
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(line)
	return [home, garage]

func _dashboard_tab(parent: Node, title: String, callback: Callable, current: bool) -> Button:
	var button := _action(parent, title, callback)
	button.custom_minimum_size = Vector2(136, 43)
	button.size_flags_horizontal = Control.SIZE_FILL
	button.add_theme_font_override("font", DASH_BODY)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color.WHITE if current else DASH_INK)
	button.add_theme_color_override("font_hover_color", DASH_INK)
	button.add_theme_color_override("font_pressed_color", DASH_INK)
	button.add_theme_color_override("font_focus_color", DASH_INK)
	button.add_theme_stylebox_override("normal", ShellTheme.box(DASH_INK if current else Color("#dbebe5"), Color.TRANSPARENT, 3, 0))
	button.add_theme_stylebox_override("hover", ShellTheme.box(DASH_ORANGE, Color.TRANSPARENT, 3, 0))
	button.add_theme_stylebox_override("pressed", ShellTheme.box(DASH_ORANGE.darkened(0.12), Color.TRANSPARENT, 3, 0))
	button.add_theme_stylebox_override("focus", _dashboard_focus())
	return button

func _dashboard_focus() -> StyleBoxFlat:
	var style := ShellTheme.box(Color.TRANSPARENT, DASH_ORANGE, 4, 0)
	style.set_border_width_all(4)
	style.draw_center = false
	return style

func _dashboard_tile(parent: Node, title: String, callback: Callable, tint: Color, height: int) -> Button:
	var button := _action(parent, "", callback)
	button.accessibility_name = title
	button.custom_minimum_size.y = height
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.add_theme_stylebox_override("normal", ShellTheme.box(tint, Color.TRANSPARENT, 3, 0))
	button.add_theme_stylebox_override("hover", ShellTheme.box(tint.lightened(0.1), Color.TRANSPARENT, 3, 0))
	button.add_theme_stylebox_override("pressed", ShellTheme.box(tint.darkened(0.1), Color.TRANSPARENT, 3, 0))
	# An overlay sits above the map or render texture and stays within the button bounds.
	var outline := Panel.new()
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.add_theme_stylebox_override("panel", _dashboard_focus())
	button.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.hide()
	button.focus_entered.connect(outline.show)
	button.focus_exited.connect(outline.hide)
	button.mouse_entered.connect(outline.show)
	button.mouse_exited.connect(func(): outline.visible = button.has_focus())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _tile_content(tile: Control, padding: int) -> VBoxContainer:
	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "right", "bottom", "left"]:
		inset.add_theme_constant_override("margin_" + side, padding)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	inset.add_child(stack)
	return stack

func _tile_art(parent: Control, texture: Texture2D) -> TextureRect:
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = texture
	parent.add_child(art)
	parent.move_child(art, 0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return art

func _dashboard_panels(root: VBoxContainer) -> BoxContainer:
	if not layout_is_narrow:
		return _columns(root)
	var content := _scroll(root)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return _columns(content)

func _dashboard_footer(root: VBoxContainer, hints: String, right: String) -> void:
	var row := HBoxContainer.new()
	root.add_child(row)
	_dashboard_label(row, hints, 16, DASH_PAPER)
	var note := _dashboard_label(row, right, 16, DASH_PAPER, 700)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _link_focus(from: Button, side: Side, to: Button) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))

func _menu(root: VBoxContainer) -> void:
	var tabs := _dashboard_header(root)
	var body := _dashboard_panels(root)
	var drive_tile := _dashboard_tile(body, "Free Roam", enter_free_roam, Color("#16484b"), 650 if layout_is_narrow else 390)
	drive_tile.size_flags_stretch_ratio = 1.73
	_tile_art(drive_tile, VALLEY_MAP)
	var featured := _tile_content(drive_tile, 31)
	_dashboard_label(featured, "ALDER TOWN  /  STARTING POINT", 15, Color("#def5e7"), 700)
	_spacer(featured)
	_dashboard_label(featured, "FREE ROAM", 98 if not layout_is_narrow else 66, Color("#fff6e8"), 800)
	_dashboard_label(featured, "Explore Aster Valley", 21, Color("#c8e0d9"))
	var drive_action := "START DRIVE   →" if drive == null else "RESUME DRIVE   →"
	var start_badge := _dashboard_label(featured, drive_action, 16, DASH_INK, 800)
	start_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start_badge.custom_minimum_size = Vector2(169, 37)
	start_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_badge.add_theme_stylebox_override("normal", ShellTheme.box(DASH_ORANGE, Color.TRANSPARENT, 2, 0))

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 13)
	body.add_child(side)
	var garage_tile := _dashboard_tile(side, "Garage", open_garage, Color("#182736"), 490 if layout_is_narrow else 300)
	var showroom := _showroom(garage_tile, save.selected_car())
	garage_tile.move_child(showroom, 0)
	showroom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile_shade(garage_tile)
	var garage_content := _tile_content(garage_tile, 21)
	_dashboard_label(garage_content, "%d CARS" % Catalog.CARS.size(), 15, Color("#dce9ef"), 700)
	_spacer(garage_content)
	var car_line := HBoxContainer.new()
	garage_content.add_child(car_line)
	car_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dashboard_label(car_line, "Garage", 43, Color("#f7f4e8"), 800)
	var arrow := _dashboard_label(car_line, "→", 29, Color("#f7f4e8"), 700)
	arrow.size_flags_horizontal = Control.SIZE_SHRINK_END

	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 12)
	side.add_child(utility)
	var settings := _utility_tile(utility, "Settings", "Controls & display", open_settings, Color("#14646b"))
	var quit := _utility_tile(utility, "Quit Game", "Exit to desktop", func(): get_tree().quit(), Color("#633d66"))
	first_focus = drive_tile
	_link_focus(drive_tile, SIDE_BOTTOM, garage_tile)
	_link_focus(drive_tile, SIDE_RIGHT, garage_tile)
	_link_focus(drive_tile, SIDE_TOP, tabs[1])
	_link_focus(tabs[1], SIDE_BOTTOM, garage_tile)
	_link_focus(garage_tile, SIDE_TOP, tabs[1])
	_link_focus(garage_tile, SIDE_LEFT, drive_tile)
	_link_focus(garage_tile, SIDE_BOTTOM, settings)
	_link_focus(settings, SIDE_TOP, garage_tile)
	_link_focus(settings, SIDE_LEFT, drive_tile)
	_link_focus(settings, SIDE_RIGHT, quit)
	_link_focus(quit, SIDE_TOP, garage_tile)
	_link_focus(quit, SIDE_LEFT, settings)
	_dashboard_footer(root, "Arrows / D-pad   Navigate      Enter / A   Select", "F11   Fullscreen")

func _tile_shade(tile: Control) -> void:
	var stops := Gradient.new()
	stops.offsets = PackedFloat32Array([0.62, 1.0])
	stops.colors = PackedColorArray([Color("#141f3000"), Color("#101a2aee")])
	var wash := GradientTexture2D.new()
	wash.gradient = stops
	wash.fill_to = Vector2.DOWN
	var shade := _tile_art(tile, wash)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	tile.move_child(shade, 1)

func _utility_tile(row: Node, title: String, detail: String, callback: Callable, tint: Color) -> Button:
	var button := _dashboard_tile(row, title, callback, tint, 106)
	var content := _tile_content(button, 17)
	_spacer(content)
	_dashboard_label(content, title, 25, Color("#fff6e8"), 750)
	_dashboard_label(content, detail, 15, Color("#d2d9e6"))
	return button

func _preview(parent: Node, car_id: String) -> void:
	_showroom(parent, car_id)

func _showroom(parent: Node, car_id: String) -> Control:
	var preview := Preview.new()
	preview.name = "Showroom"
	parent.add_child(preview)
	var quality := 1.2 if save.data["settings"]["graphics_quality"] == "high" else _quality_scale()
	preview.set_quality(quality)
	var model := CuratedCar.load_model(car_id)
	if model == null:
		preview.set_car(car_id)
	else:
		preview.set_model(model)
	return preview

func _garage(root: VBoxContainer) -> void:
	var tabs := _dashboard_header(root)
	var body := _dashboard_panels(root)
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 2.74
	stage.add_theme_constant_override("separation", 12)
	body.add_child(stage)
	var showroom := _showroom(stage, inspected_car)
	showroom.custom_minimum_size.y = 500 if layout_is_narrow else 280
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 10)
	stage.add_child(roster)
	var cars: Array[Button] = []
	for item: Dictionary in Catalog.CARS:
		var car_id: String = item["id"]
		var selected := car_id == inspected_car
		var current: bool = car_id == save.selected_car()
		var tint := Color("#304958") if selected else Color("#1f303d")
		var card := _dashboard_tile(roster, item["name"], _inspect.bind(car_id), tint, 102)
		var thumbnail := _tile_art(card, GARAGE_THUMBNAILS[car_id])
		thumbnail.anchor_left = 0.47
		thumbnail.offset_top = 8
		thumbnail.offset_right = -12
		thumbnail.offset_bottom = -7
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var content := _tile_content(card, 14)
		var state := "ACTIVE CAR" if current else "IN PREVIEW" if selected else str(item["class"])
		_dashboard_label(content, state, 13, Color("#ffc28b") if current else Color("#b6cbd4"), 700)
		_spacer(content)
		_dashboard_label(content, item["name"], 25 if not layout_is_narrow else 19, Color("#f7f5ec"), 800)
		cars.append(card)
		if selected:
			first_focus = card

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 304
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ShellTheme.box(Color("#dedfd6"), Color.TRANSPARENT, 3, 24))
	body.add_child(panel)
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 11)
	panel.add_child(specs)
	var info := Catalog.car(inspected_car)
	_dashboard_label(specs, str(info["class"]), 15, DASH_MUTED, 750)
	_dashboard_label(specs, str(info["name"]), 48, DASH_INK, 800)
	_dashboard_label(specs, str(info["tagline"]), 17, DASH_MUTED)
	_spacer(specs)
	var preset: Dictionary = PlayerCarFactory.PRESETS[inspected_car]
	_garage_metric(specs, "Torque", "%d Nm" % roundi(float(preset["torque"])))
	_garage_metric(specs, "Weight", "%d kg" % roundi(float(preset["mass"])))
	_garage_metric(specs, "Drivetrain", "AWD" if float(preset["front_split"]) > 0.0 else "RWD")
	_spacer(specs)
	if game.notification_s > 0.0 and not game.notification.is_empty():
		var notice := _dashboard_label(specs, game.notification, 15, DASH_INK, 700)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var select := _dashboard_tab(specs, "SELECT VEHICLE", _choose_car, false)
	select.custom_minimum_size.y = 64
	select.add_theme_stylebox_override("normal", ShellTheme.box(DASH_ORANGE, Color.TRANSPARENT, 3, 0))
	select.add_theme_stylebox_override("focus", ShellTheme.box(Color.TRANSPARENT, DASH_INK, 3, 0))
	var back := _dashboard_tab(specs, "BACK", _go_back, false)
	for index in cars.size():
		var card := cars[index]
		var next := cars[mini(index + 1, cars.size() - 1)]
		var previous := cars[maxi(0, index - 1)]
		_link_focus(card, SIDE_BOTTOM, next)
		_link_focus(card, SIDE_TOP, tabs[0] if index == 0 else previous)
		_link_focus(card, SIDE_LEFT, previous)
		_link_focus(card, SIDE_RIGHT, select)
	_link_focus(tabs[0], SIDE_BOTTOM, first_focus)
	_link_focus(select, SIDE_LEFT, first_focus)
	_link_focus(select, SIDE_TOP, tabs[0])
	_link_focus(select, SIDE_BOTTOM, back)
	_link_focus(back, SIDE_LEFT, first_focus)
	_link_focus(back, SIDE_TOP, select)
	_dashboard_footer(root, "↑ ↓ / D-pad   Browse cars      Enter / A   Select      Esc / B   Back", "%d CARS" % Catalog.CARS.size())

func _garage_metric(parent: Node, caption: String, value: String) -> void:
	var divider := ColorRect.new()
	divider.color = Color("#b7bdb2")
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(divider)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_dashboard_label(row, caption, 17, DASH_MUTED).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dashboard_label(row, value, 25, DASH_INK, 750).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _preferences(root: VBoxContainer) -> void:
	var back := _dashboard_header(root)[0]
	_dashboard_label(root, "SETTINGS", 68, DASH_PAPER, 800)
	var panels := _dashboard_panels(root)
	var display := _settings_panel(panels, "Display", Color("#6af1ce"))
	_setting_option(display, "Graphics quality", "graphics_quality", SaveService.GRAPHICS)
	_setting_option(display, "Window mode", "window_mode", SaveService.MODES)
	_setting_option(display, "Resolution", "resolution", SaveService.RESOLUTIONS)
	_label(display, "Resolution applies in windowed mode.", 17, Color("#a8cbd0"))
	var controls := _settings_panel(panels, "Controls", Color("#ffc381"))
	_setting_slider(controls, "Controller steering sensitivity", "controller_sensitivity")
	_control_binding(controls, "Accelerate / brake", "W / S   ·   RT / LT")
	_control_binding(controls, "Steer", "A / D   ·   Left stick")
	_control_binding(controls, "Handbrake", "Space   ·   A")
	_control_binding(controls, "Camera", "C   ·   LB")
	_control_binding(controls, "Reset car", "R   ·   Y")
	var audio := _settings_panel(panels, "Audio", Color("#f6a6df"))
	_setting_slider(audio, "Master volume", "master_volume")
	_setting_slider(audio, "Music volume", "music_volume")
	_setting_slider(audio, "Effects volume", "sfx_volume")
	if AudioServer.get_bus_index("Music") < 0 or AudioServer.get_bus_index("SFX") < 0:
		_label(audio, "Music and effects levels are saved for audio that uses those channels.", 17, Color("#a8cbd0"))
	var actions := HBoxContainer.new()
	root.add_child(actions)
	_dashboard_label(actions, "Changes save as you make them", 17, DASH_PAPER)
	var done := _dashboard_tab(actions, "DONE", _go_back, false)
	done.add_theme_stylebox_override("normal", ShellTheme.box(Color("#6af1ce"), Color.TRANSPARENT, 3, 0))
	settings_error = _dashboard_label(root, "", 17, Color("#ffb392"))
	settings_error.hide()
	_dashboard_footer(root, "Arrows / D-pad   Navigate      Enter / A   Confirm", "Esc / B   Back")
	var sequence: Array[Control] = [back]
	for node: Control in panels.find_children("*", "Control", true, false):
		if node is OptionButton or node is HSlider:
			sequence.append(node)
	sequence.append(done)
	for i in range(sequence.size() - 1):
		var current := sequence[i]
		var next := sequence[i + 1]
		current.focus_neighbor_bottom = current.get_path_to(next)
		next.focus_neighbor_top = next.get_path_to(current)
	first_focus = sequence[1]

func _control_binding(parent: Control, action: String, binding: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_dashboard_label(row, action, 18, DASH_PAPER)
	_dashboard_label(row, binding, 18, Color("#b7d5d9")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _settings_panel(parent: Container, title: String, accent: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 275
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := ShellTheme.box(Color("#13252fe8"), accent.darkened(0.53), 7, 25)
	style.border_width_top = 4
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 17)
	panel.add_child(content)
	_dashboard_label(content, title, 40, accent, 800)
	return content

func _pause(root: VBoxContainer) -> void:
	_dashboard_label(root, "DRIVE PAUSED", 72, DASH_PAPER, 800)
	var body := _columns(root)
	var actions := _settings_panel(body, "Free Roam", Color("#6af1ce"))
	var resume := _dashboard_tab(actions, "RESUME DRIVE", toggle_pause, false)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.add_theme_stylebox_override("normal", ShellTheme.box(Color("#6af1ce"), Color.TRANSPARENT, 3, 0))
	var parked: bool = game.speed_kph <= 4.0
	_action(actions, "GARAGE" if parked else "PARK TO ENTER GARAGE", open_garage, false, parked)
	_action(actions, "SETTINGS", open_settings)
	_action(actions, "RETURN TO HOME", _leave_pause)
	_spacer(actions)
	var clear := Control.new()
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.size_flags_stretch_ratio = 1.85
	body.add_child(clear)
	_dashboard_footer(root, "Enter / A   Select", "Esc / Menu   Resume")


func enter_free_roam() -> void:
	if drive == null:
		drive = FreeRoam.instantiate()
		drive.shell_managed = true
		drive.steering_sensitivity = float(save.data["settings"]["controller_sensitivity"])
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
