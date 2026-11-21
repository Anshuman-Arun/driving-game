extends SceneTree
## Run after import with --fixed-fps 60 (also 30, 83, or 144).
## Pass -- --baseline on the base revision to record results without assertions.

const DT := 1.0 / 120.0
const HOOD_MOUNT := Vector3(0.0, 0.86, -0.92)

var failures := 0
var baseline := false
var _hood_mount_error := 0.0

class FrameProbe extends Node:
	var sample: Callable

	func _process(_delta: float) -> void:
		sample.call()

func _initialize() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if not baseline and not condition:
		failures += 1
		push_error("FAIL " + description)

func _step(ticks: int) -> void:
	for tick in ticks:
		await physics_frame

func _steer(direction: int) -> void:
	Input.action_release("drive_left")
	Input.action_release("drive_right")
	if direction != 0:
		Input.action_press("drive_left" if direction > 0 else "drive_right")

func _run() -> void:
	print("Steering/camera test")
	_check(Engine.physics_ticks_per_second == 120, "physics runs at 120 Hz")
	var game: Node3D = load("res://scenes/prototypes/driving_test.tscn").instantiate()
	root.add_child(game)
	await _step(90)
	await _stationary_camera(game)
	game.free()
	await physics_frame
	await _moving_steering()
	await _frame_pacing()
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture-dir")
	if capture >= 0 and capture + 1 < args.size():
		await _visual_drive(args[capture + 1])
	print("Steering/camera failures: ", failures)
	quit(0 if failures == 0 else 1)

func _stationary_camera(game: Node3D) -> void:
	var car: Vehicle = game.get("vehicle_body")
	var camera: DrivingChaseCamera = game.get("camera")
	car.freeze = true
	car.reset_physics_interpolation()
	# The second camera follows the same pose and never receives a steering hint.
	var control := DrivingChaseCamera.new()
	game.add_child(control)
	control.setup(car)
	camera.make_current()
	await _step(180)
	var original := -camera.global_basis.z
	var control_original := -control.global_basis.z
	var yaw := -car.global_basis.z
	var peak := 0.0
	var control_peak := 0.0
	for direction in [1, -1, 1, -1, 0]:
		_steer(direction)
		for tick in 48:
			await physics_frame
			peak = maxf(peak, original.angle_to(-camera.global_basis.z))
			control_peak = maxf(control_peak, control_original.angle_to(-control.global_basis.z))
	print("STATIONARY chassis=%.3f deg camera=%.3f deg no_hint=%.3f deg" % [
		rad_to_deg(yaw.angle_to(-car.global_basis.z)), rad_to_deg(peak), rad_to_deg(control_peak)])
	_check(peak < deg_to_rad(0.15), "A/D cannot pull the view on a stationary chassis")
	control.queue_free()

func _moving_steering() -> void:
	var track := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var deck := BoxShape3D.new()
	deck.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = deck
	shape.position.y = -0.5
	track.add_to_group("Road")
	track.add_child(shape)
	root.add_child(track)
	var car := PlayerCarFactory.create()
	root.add_child(car)
	var adapter := VehicleAdapter.new(car)
	var controls := DriveInput.new()
	car.speed = 0.001
	car.steering_input = 0.60
	car.process_steering(DT)
	print("LOW SPEED direct axis 0.60, first steer step=%.4f" % car.steering_amount)
	_check(car.steering_amount > 0.0 and car.steering_amount <= 0.038, "low-speed analog input has a finite rate")
	if not baseline:
		Input.action_press("drive_right", 0.37)
		var input: Dictionary = controls.call("sample")
		_check(is_equal_approx(float(input["steer"]), -0.37), "fractional right input preserves magnitude and sign")
		Input.action_release("drive_right")
	for kmh in [0, 20, 60, 120]:
		adapter.reset_to(Transform3D(Basis.IDENTITY, Vector3.UP * 0.58))
		await _step(72)
		# Isolate steering rate at each entry speed without depending on the test world's turns.
		car.linear_velocity = Vector3.FORWARD * (kmh / 3.6)
		await _step(8)
		var entry_speed := car.linear_velocity.length() * 3.6
		var old_steer := car.steering_amount
		var old_heading := -car.global_basis.z
		var peak_step := 0.0
		var peak_yaw_step := 0.0
		var extrema := Vector2.ZERO
		for direction in [1, -1, 1, -1, 0]:
			_steer(direction)
			for tick in (90 if direction == 0 else 24):
				var input: Dictionary = controls.call("sample", DT) if baseline else controls.call("sample")
				adapter.set_drive_input(input["steer"], 0.0, 0.0, false)
				await physics_frame
				peak_step = maxf(peak_step, absf(car.steering_amount - old_steer))
				old_steer = car.steering_amount
				var heading := -car.global_basis.z
				peak_yaw_step = maxf(peak_yaw_step, absf(old_heading.signed_angle_to(heading, Vector3.UP)))
				old_heading = heading
				extrema.x = minf(extrema.x, car.steering_amount)
				extrema.y = maxf(extrema.y, car.steering_amount)
		print("PULSES %3d km/h entry=%.1f peak steer/tick=%.4f peak yaw/tick=%.3f deg range=[%.3f, %.3f] release=%.4f" % [
			kmh, entry_speed, peak_step, rad_to_deg(peak_yaw_step), extrema.x, extrema.y, car.steering_amount])
		_check(absf(entry_speed - kmh) < 5.0, "reaches requested entry speed")
		_check(peak_step <= 0.059, "normalized steering step is bounded")
		_check(extrema.x < -0.04 and extrema.y > 0.06, "steering crosses center in both directions")
		_check(absf(car.steering_amount) < 0.02, "released steering returns to center")
	await _acceleration_and_collision(car, adapter)
	car.queue_free()
	track.queue_free()
	await process_frame

# A separate straight-line fixture isolates physics/render timing from steering and suspension.
func _frame_pacing() -> void:
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.can_sleep = false
	var collider := CollisionShape3D.new()
	collider.shape = SphereShape3D.new()
	body.collision_layer = 2
	body.add_child(collider)
	root.add_child(body)
	var camera := DrivingChaseCamera.new()
	root.add_child(camera)
	camera.setup(body)
	body.linear_velocity = Vector3.FORWARD * 18.0
	for mode in 3:
		await _step(180)
		var peak_step_error := 0.0
		var peak_mount_error := 0.0
		await process_frame
		var previous_z := camera.global_position.z
		for sample in 90:
			await process_frame
			var position_3d := camera.global_position
			var expected_step := 18.0 * camera.get_process_delta_time()
			peak_step_error = maxf(peak_step_error, absf(previous_z - position_3d.z - expected_step))
			previous_z = position_3d.z
			if mode == 2:
				# The process_frame signal precedes the next update. The camera pose measured here
				# was recorded after the prior render callback by the frame probe.
				peak_mount_error = maxf(peak_mount_error, _hood_mount_error)
		print("PACING mode=%s peak step error=%.4f m peak hood error=%.4f m" % [
			camera.get_mode_name(), peak_step_error, peak_mount_error])
		_check(peak_step_error < 0.035, "camera moves evenly between rendered frames")
		_check(peak_mount_error < 0.005, "hood matches the rendered chassis")
		camera.cycle()
		if camera.mode == 2:
			var frame_probe := FrameProbe.new()
			frame_probe.process_priority = 10
			frame_probe.sample = func() -> void:
				_hood_mount_error = camera.global_position.distance_to(
					body.get_global_transform_interpolated() * HOOD_MOUNT)
			camera.add_child(frame_probe)
	camera.queue_free()
	body.queue_free()
	await process_frame

func _acceleration_and_collision(car: Vehicle, adapter: VehicleAdapter) -> void:
	adapter.reset_to(Transform3D(Basis.IDENTITY, Vector3.UP * 0.58))
	await _step(60)
	var camera := DrivingChaseCamera.new()
	root.add_child(camera)
	camera.setup(car)
	var initial_fov := camera.fov
	var prior_fov := initial_fov
	var peak_fov_rate := 0.0
	var speed := 0.0
	for frame in 180:
		await physics_frame
		adapter.set_drive_input(0.0, 1.0, 0.0, false)
		speed = adapter.get_speed_mps()
		peak_fov_rate = maxf(peak_fov_rate, absf(camera.fov - prior_fov))
		prior_fov = camera.fov
	var moving_fov := camera.fov
	for frame in 130:
		await physics_frame
		adapter.set_drive_input(0.0, 0.0, 1.0, false)
		peak_fov_rate = maxf(peak_fov_rate, absf(camera.fov - prior_fov))
		prior_fov = camera.fov
	print("SPEED FOV launch=%.2f accel=%.2f brake=%.2f peak frame change=%.3f deg" % [
		initial_fov, moving_fov, camera.fov, peak_fov_rate])
	_check(moving_fov > initial_fov + 0.5 and camera.fov < moving_fov, "FOV tracks filtered acceleration and braking")
	_check(speed > 4.0 and peak_fov_rate < 0.5, "FOV remains continuous as pedals change")

	adapter.reset_to(Transform3D(Basis.IDENTITY, Vector3.UP * 0.58))
	await _step(60)
	car.linear_velocity = Vector3.FORWARD * 10.0
	await _step(8)
	var entry_speed := adapter.get_speed_mps()
	adapter.set_drive_input(0.25, 0.0, 0.0, true)
	await _step(30)
	_check(car.handbrake_force > 0.0 and adapter.get_speed_mps() < entry_speed,
		"handbrake applies force while turning")
	_check(car.global_basis.y.dot(Vector3.UP) > 0.95, "car remains upright in the handbrake turn")
	print("HANDBRAKE speed %.2f -> %.2f m/s" % [entry_speed, adapter.get_speed_mps()])

	adapter.reset_to(Transform3D(Basis.IDENTITY, Vector3.UP * 0.58))
	camera.snap_to_vehicle()
	_check(camera.global_position.distance_to(car.global_position + Vector3(0.0, 2.50, 6.30)) < 0.01,
		"respawn clears follow state")
	if not baseline:
		_check(absf(camera.fov - 70.0) < 0.01, "respawn clears inherited speed FOV")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 2.0, 3.0)
	root.add_child(wall)
	await _step(160)
	var blocked_z := camera.global_position.z
	_check(blocked_z < 2.8, "chase camera sits in front of a wall behind the car")
	wall.position.z = -10.0
	await _step(160)
	var clear_z := camera.global_position.z
	_check(clear_z > 6.0, "chase camera recovers after the obstruction moves")
	adapter.set_drive_input(0.0, 1.0, 0.0, false)
	var hit := false
	for tick in 360:
		await physics_frame
		hit = hit or wall in car.get_colliding_bodies()
	_check(hit and car.global_position.z > -10.0, "body collision stops the car at the wall")
	print("COLLISION blocked camera z=%.2f clear z=%.2f body hit=%s" % [blocked_z, clear_z, hit])
	wall.queue_free()
	camera.queue_free()

# Run without --headless and pass -- --capture-dir <folder> to drive the main scene
# through each camera mode and save screenshots for inspection.
func _visual_drive(folder: String) -> void:
	var game: Node3D = load("res://scenes/bootstrap/main.tscn").instantiate()
	root.add_child(game)
	await _step(90)
	var driving := game.get_child(0)
	var car: Vehicle = driving.get("vehicle_body")
	var camera: DrivingChaseCamera = driving.get("camera")
	for mode in 3:
		await _tap_action("drive_reset")
		await _step(90)
		Input.action_press("drive_throttle")
		await _step(180)
		for direction in [1, -1, 0]:
			_steer(direction)
			await _step(18)
			await RenderingServer.frame_post_draw
			var path := folder.path_join("steering-%d-%d.png" % [mode, direction])
			var image := root.get_texture().get_image()
			_check(image.save_png(path) == OK, "visual capture saved")
		Input.action_release("drive_throttle")
		Input.action_press("drive_brake")
		await _step(60)
		Input.action_release("drive_brake")
		print("VISUAL mode=%s braking speed=%.1f km/h fov=%.2f" % [
			camera.get_mode_name(), car.linear_velocity.length() * 3.6, camera.fov])
		await _tap_action("drive_camera")
		_check(camera.mode == (mode + 1) % 3, "camera action cycles the view")
	game.queue_free()
	await process_frame

func _tap_action(action: StringName) -> void:
	await process_frame
	Input.action_press(action)
	await _step(8)
	Input.action_release(action)
