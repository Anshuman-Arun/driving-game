extends SceneTree
## Verifies Xbox Series controller bindings, Forza look-around camera, real drift physics,
## and Free Roam A-button UI safety.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame

func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false

func _xz_slip_deg(car: Vehicle) -> float:
	var vel := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	if vel.length() < 0.5:
		return 0.0
	var fwd := Vector3(-car.global_basis.z.x, 0.0, -car.global_basis.z.z).normalized()
	return rad_to_deg(fwd.angle_to(vel.normalized()))

func _run() -> void:
	# 1. Boot driving_test.tscn
	var packed: PackedScene = load("res://scenes/prototypes/driving_test.tscn")
	var scene := packed.instantiate() as Node3D
	_check(scene != null, "driving_test.tscn instantiates")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	await _step(45)

	var car := scene.get("vehicle_body") as Vehicle
	var cam := scene.get("camera") as DrivingChaseCamera
	_check(car != null and cam != null, "vehicle and chase camera ready")
	if car == null or cam == null:
		quit(1)
		return

	# 2. Xbox Series InputMap bindings
	_check(_has_joy_button(&"drive_handbrake", JOY_BUTTON_A), "JOY_BUTTON_A bound to drive_handbrake (drift)")
	_check(_has_joy_button(&"drive_camera", JOY_BUTTON_LEFT_SHOULDER), "JOY_BUTTON_LEFT_SHOULDER bound to drive_camera")
	_check(_has_joy_button(&"drive_reset", JOY_BUTTON_Y), "JOY_BUTTON_Y bound to drive_reset")
	_check(_has_joy_button(&"drive_pause", JOY_BUTTON_START), "JOY_BUTTON_START bound to drive_pause")

	# 3. DriveInput.sample_look() deadzone & stick response
	var drive_input := DriveInput.new()
	_check(drive_input.has_method("sample_look"), "DriveInput exposes sample_look()")
	if drive_input.has_method("sample_look"):
		var look_zero: Vector2 = drive_input.call("sample_look")
		_check(look_zero.is_zero_approx(), "sample_look() is zero when no joypad connected")

	# 4. Forza look-around camera orbit & recenter (Chase + Hood)
	_check(cam.has_method("set_look_input"), "DrivingChaseCamera exposes set_look_input()")
	if cam.has_method("set_look_input"):
		var car_fwd := Vector3(-car.global_basis.z.x, 0.0, -car.global_basis.z.z).normalized()
		cam.call("set_look_input", Vector2(1.0, 0.0))
		await _step(40)
		var cam_fwd := Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
		var orbit_deg := rad_to_deg(car_fwd.angle_to(cam_fwd))
		print("CAMERA chase look-right orbit = %.1f deg" % orbit_deg)
		_check(orbit_deg > 20.0, "Chase camera orbits cleanly on right-stick look")
		cam.call("set_look_input", Vector2.ZERO)
		await _step(110)
		var recentered_deg := rad_to_deg(car_fwd.angle_to(Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()))
		print("CAMERA chase recentered = %.1f deg" % recentered_deg)
		_check(recentered_deg < 8.0, "Chase camera recenters smoothly when look released")

		cam.cycle()
		cam.cycle()
		_check(cam.mode == 2, "Cycled to hood mode")
		cam.call("set_look_input", Vector2(-1.0, 0.0))
		await _step(40)
		var hood_pan_deg := rad_to_deg(car_fwd.angle_to(Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()))
		print("CAMERA hood look-left pan = %.1f deg" % hood_pan_deg)
		_check(hood_pan_deg > 15.0, "Hood camera pans cleanly on right-stick look")
		cam.call("set_look_input", Vector2.ZERO)
		await _step(110)
		var hood_recentered := rad_to_deg(car_fwd.angle_to(Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()))
		_check(hood_recentered < 8.0, "Hood camera recenters smoothly when look released")
		cam.cycle()
		_check(cam.mode == 0, "Cycled back to chase far")

	# 5. Real Drift Physics: accelerate to ~18 m/s, steer + handbrake + throttle
	Input.action_press("drive_throttle", 1.0)
	for i in 300:
		await physics_frame
		if car.linear_velocity.length() >= 18.0:
			break
	var entry_speed := car.linear_velocity.length()
	print("DRIFT entry speed = %.2f m/s" % entry_speed)
	_check(entry_speed >= 15.0, "Vela accelerates to drift entry speed")

	Input.action_press("drive_left", 1.0)
	Input.action_press("drive_handbrake", 1.0)
	var peak_slip := 0.0
	var min_drift_speed := INF
	var drift_active_seen := false
	var dc: Variant = car.get_node_or_null("DriftController")
	for i in 90:
		await physics_frame
		peak_slip = maxf(peak_slip, _xz_slip_deg(car))
		min_drift_speed = minf(min_drift_speed, car.linear_velocity.length())
		if dc != null and bool(dc.get("is_drifting")):
			drift_active_seen = true
	Input.action_release("drive_handbrake")
	Input.action_release("drive_left")
	print("DRIFT peak_slip=%.1f deg min_speed=%.2f m/s drift_active=%s" % [peak_slip, min_drift_speed, drift_active_seen])
	_check(peak_slip >= 14.0, "Handbrake initiates real drift slip angle (>= 14 deg)")
	_check(min_drift_speed > 8.0, "Handbrake drift maintains forward momentum (> 8 m/s)")
	if dc != null:
		_check(drift_active_seen, "DriftController reports active drift state")

	# Straighten & recover
	await _step(110)
	Input.action_release("drive_throttle")
	var recovered_slip := _xz_slip_deg(car)
	print("DRIFT recovered_slip=%.1f deg" % recovered_slip)
	_check(recovered_slip < 6.0, "Vehicle recovers cleanly to < 6 deg slip after drift")

	scene.queue_free()
	await process_frame

	# 6. Shell Free-Roam A-button safety
	var main_packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var main_inst := main_packed.instantiate()
	var shell := main_inst.get_node("GameShell")
	shell.save_path = "user://drift_ctrl_qa_%d.json" % Time.get_ticks_usec()
	root.add_child(main_inst)
	await _step(15)
	var enter_ev := InputEventKey.new()
	enter_ev.keycode = KEY_ENTER
	enter_ev.physical_keycode = KEY_ENTER
	enter_ev.pressed = true
	root.push_input(enter_ev)
	await _step(4)
	enter_ev = enter_ev.duplicate()
	enter_ev.pressed = false
	root.push_input(enter_ev)
	await _step(130)
	_check(shell.get("screen") == "FREE_ROAM", "Shell enters FREE_ROAM")
	if shell.get("screen") == "FREE_ROAM":
		var btn_a := InputEventJoypadButton.new()
		btn_a.button_index = JOY_BUTTON_A
		btn_a.pressed = true
		root.push_input(btn_a)
		await _step(10)
		btn_a = btn_a.duplicate()
		btn_a.pressed = false
		root.push_input(btn_a)
		await _step(5)
		_check(shell.get("screen") == "FREE_ROAM", "Pressing JOY_BUTTON_A in FREE_ROAM does not open menu")
	main_inst.queue_free()
	await process_frame

	print("Drift & controller failures: ", failures)
	quit(0 if failures == 0 else 1)
