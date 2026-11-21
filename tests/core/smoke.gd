extends SceneTree
## Run after a successful Godot 4.7.2 editor import:
## godot --headless --path . --script res://tests/core/smoke.gd
## Real physics, wheel ray contacts, keyboard action simulation, pause and reset.
## This is NOT proof of visual quality or actual gamepad hardware.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func _step(frames: int) -> void:
	for i in range(frames):
		await physics_frame

func _run() -> void:
	var packed_scene: PackedScene = load("res://scenes/prototypes/driving_test.tscn")
	var scene := packed_scene.instantiate() as Node3D
	_check(scene != null, "test scene instantiates")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	await _step(45)

	var world := scene.get("world") as DrivingTestWorld
	var car := scene.get("vehicle_body") as Vehicle
	var cam := scene.get("camera") as DrivingChaseCamera
	if world == null or car == null or cam == null:
		_check(false, "world / GEVP body / chase camera ready")
		quit(1)
		return
	_check(world.road_points.size() > 100, "long spline sampled for road")
	_check((world.get_node("PavedRoad/CollisionShape3D") as CollisionShape3D).shape != null, "asphalt collision shape exists")
	_check((world.get_node("Grass/CollisionShape3D") as CollisionShape3D).shape != null, "grass collision shape exists")
	_check((world.get_node("GradedShoulder/CollisionShape3D") as CollisionShape3D).shape != null, "dirt shoulder collision shape exists")
	_check(car.wheel_array.size() == 4, "four GEVP raycast wheels initialized")
	_check(car.is_ready, "GEVP vehicle initialized drivetrain")
	_check(cam.current, "chase camera current")
	for action in ["drive_throttle", "drive_brake", "drive_left", "drive_right", "drive_handbrake", "drive_reset", "drive_camera", "drive_pause"]:
		_check(InputMap.has_action(action), "action installed: " + action)

	await _step(150)
	var initial := car.global_position
	Input.action_press("drive_throttle", 1.0)
	await _step(500)
	Input.action_release("drive_throttle")
	var end := car.global_position
	var moved := initial.distance_to(end)
	var reached := car.linear_velocity.length() * 3.6
	print("PHYSICS forward distance %.2f m; speed %.1f km/h; gear %d" % [moved, reached, car.current_gear])
	_check(moved > 1.0, "forward drive covers at least 1m with applied engine torque")
	_check(reached > 2.0 or moved > 10.0, "car accelerates on its suspension")

	var prior_speed := car.linear_velocity.length()
	Input.action_press("drive_brake", 0.65)
	await _step(110)
	Input.action_release("drive_brake")
	var after_brake := car.linear_velocity.length()
	print("PHYSICS braking before %.2f m/s; after %.2f m/s" % [prior_speed, after_brake])
	_check(after_brake < prior_speed + 0.7, "braking does not accelerate forward")

	# Reset, apply steering while moving and verify heading/position changes.
	scene.call("_reset_to_road")
	await _step(75)
	var heading := car.global_basis.z
	Input.action_press("drive_throttle", 1.0)
	Input.action_press("drive_left", 0.8)
	await _step(310)
	Input.action_release("drive_left")
	Input.action_release("drive_throttle")
	print("PHYSICS heading changed %.3f" % heading.distance_to(car.global_basis.z))
	_check(heading.distance_to(car.global_basis.z) > 0.01, "steering rotates car")

	var adapter := scene.get("adapter") as VehicleAdapter
	adapter.set_drive_input(0.0, 0.0, 0.1, true)
	_check(car.handbrake_input > 0.5, "handbrake maps to GEVP")
	adapter.set_drive_input(0.0, 0.0, 0.0, false)

	var grass_x := 0.0
	var grass_z := 120.0
	var grass_pose := Transform3D(Basis.IDENTITY, Vector3(grass_x, world.height_at(grass_x, grass_z) + 0.72, grass_z))
	adapter.reset_to(grass_pose)
	await _step(170)
	var grass_contacts := 0
	for wheel in car.wheel_array:
		if wheel.is_colliding() and wheel.get_collider().is_in_group("Grass"):
			grass_contacts += 1
	print("PHYSICS grass contacts ", grass_contacts)
	_check(grass_contacts >= 1, "at least one wheel contacts traversable grass")

	# Test inverted reset behavior: righting, clearing velocity, returning to road.
	var inverted := Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0.0, 12.0, 120.0))
	adapter.reset_to(inverted)
	scene.call("_reset_to_road")
	_check(car.global_basis.y.dot(Vector3.UP) > 0.85, "reset rights an overturned car")
	_check(car.linear_velocity.length() < 0.02, "reset clears linear velocity")
	_check(world.road_points.size() > 100 and absf(car.global_position.x) < 250.0, "reset relocates to known road")

	scene.call("_toggle_pause")
	_check(paused, "pause suspends simulation")
	scene.call("_toggle_pause")
	_check(not paused, "pause resumes simulation")

	scene.queue_free()
	print("Core driving smoke failures: ", failures)
	quit(0 if failures == 0 else 1)
