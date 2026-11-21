extends Node3D
## Self-contained P0/P1 boot and presentation. No other workstream is loaded here.
var world: DrivingTestWorld
var vehicle_body: Vehicle
var adapter: VehicleAdapter
var camera: DrivingChaseCamera
var controls := DriveInput.new()
var _last_reset := -100.0
var _elapsed := 0.0
var _speed: Label
var _gear: Label
var _info: Label
var _pause_layer: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DriveInput.install()
	world = DrivingTestWorld.new()
	world.name = "500mDrivingValley"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	vehicle_body = PlayerCarFactory.create()
	vehicle_body.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(vehicle_body)
	adapter = VehicleAdapter.new(vehicle_body)
	adapter.reset_to(world.start_transform())
	camera = DrivingChaseCamera.new()
	camera.name = "ResponsiveChaseCamera"
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(camera)
	camera.setup(vehicle_body)
	_make_hud()

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var input := controls.sample(delta)
	adapter.set_drive_input(input["steer"], input["throttle"], input["brake"], input["handbrake"])
	camera.steer_hint = -input["steer"]
	_elapsed += delta
	# Recover from a tumble down the terrain edge without leaving an inert car.
	if vehicle_body.global_position.y < -16.0 and _elapsed - _last_reset > 2.0:
		_reset_to_road()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("drive_pause"):
		_toggle_pause()
	if Input.is_action_just_pressed("drive_reset") and _elapsed - _last_reset >= 0.75:
		_reset_to_road()
	if not get_tree().paused and Input.is_action_just_pressed("drive_camera"):
		camera.cycle()
	if adapter != null:
		_speed.text = "%03d" % roundi(adapter.get_speed_mps() * 3.6)
		_gear.text = "km/h    •    GEAR " + adapter.get_gear_display()
		var surface := "AIRBORNE"
		for wheel in vehicle_body.wheel_array:
			if wheel.is_colliding():
				surface = wheel.surface_type.to_upper()
				break
		_info.text = "%s    •    %s" % [surface, camera.get_mode_name()]
	_pause_layer.visible = get_tree().paused

func _reset_to_road() -> void:
	_last_reset = _elapsed
	var safe_pose := world.respawn_near(vehicle_body.global_position)
	adapter.reset_to(safe_pose)
	camera.snap_to_vehicle()

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause_layer.visible = get_tree().paused
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DrivingHUD"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var tint := ColorRect.new()
	tint.name = "SpeedBackground"
	tint.color = Color(0.024, 0.044, 0.062, 0.73)
	tint.position = Vector2(24, 22)
	tint.size = Vector2(315, 162)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tint)
	var car_name := _label(layer, "V E L A   G T", Vector2(42, 29), 18, Color(0.78, 0.88, 0.97))
	_speed = _label(layer, "000", Vector2(40, 48), 53, Color.WHITE)
	_gear = _label(layer, "km/h    •    GEAR 1", Vector2(43, 114), 16, Color(0.80, 0.90, 0.96))
	_info = _label(layer, "ROAD    •    CHASE FAR", Vector2(43, 144), 15, Color(0.94, 0.77, 0.33))
	var legend := _label(layer, "W / ↑ gas   S / ↓ brake   A D / ← → steer   SPACE handbrake\nR reset   C camera   ESC pause    •    Xbox RT / LT / LS / B / Y / Menu", Vector2.ZERO, 17, Color.WHITE)
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 24.0
	legend.offset_top = -62.0
	legend.offset_right = 1100.0
	legend.offset_bottom = -14.0
	legend.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	legend.add_theme_constant_override("shadow_offset_x", 2)
	legend.add_theme_constant_override("shadow_offset_y", 2)
	var pause := ColorRect.new()
	pause.name = "PauseOverlay"
	pause.color = Color(0.01, 0.025, 0.042, 0.82)
	pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pause)
	_pause_layer = pause
	var title := _label(pause, "PAUSED", Vector2.ZERO, 55, Color.WHITE)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.43
	title.anchor_bottom = 0.43
	title.offset_left = -190.0
	title.offset_right = 190.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var details := _label(pause, "ESC / MENU  •  Resume driving\nR  •  Reset on road\nC  •  Switch chase / hood camera", Vector2.ZERO, 21, Color(0.80, 0.90, 0.97))
	details.anchor_left = 0.5
	details.anchor_right = 0.5
	details.anchor_top = 0.56
	details.anchor_bottom = 0.56
	details.offset_left = -255.0
	details.offset_right = 255.0
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_layer.visible = false

func _label(parent: Node, value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
