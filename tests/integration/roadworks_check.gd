extends SceneTree

const Game := preload("res://scenes/bootstrap/game.tscn")

var failures := 0
var capture_dir := ""

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().is_empty():
		capture_dir = OS.get_cmdline_user_args()[0]
	var game := Game.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = "user://roadworks-check-%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	shell.enter_free_roam()
	var drive = shell.drive
	for frame in 400:
		await physics_frame
		if drive.vehicle_body != null:
			break
	if drive.vehicle_body == null:
		quit(1)
		return
	var world = drive.world
	var profiles: Dictionary = world.roadworks["roads"]
	var checked := 0
	var crossings := 0
	var supported_spans := 0
	for road: Dictionary in world.get_physical_road_centerlines():
		var id: String = road["id"]
		if not profiles.has(id):
			continue
		checked += 1
		var profile: Dictionary = profiles[id]
		var points: PackedVector3Array = road["points"]
		var station := float(profile["center"])
		var center := at_station(points, station)
		var side := center.basis.x * (float(profile["width_m"]) * 0.5 - 0.34)
		var context: PhysicsDirectSpaceState3D = drive.get_world_3d().direct_space_state
		check(is_pavement(cast_down(context, center.origin + side)) and is_pavement(cast_down(context, center.origin - side)), id + " widened edges are drivable")
		if profile.has("support_start"):
			supported_spans += 1
			var support_start := float(profile["support_start"])
			var support_end := float(profile["support_end"])
			var supported_deck := true
			var supported_rails := true
			for sample in range(1, 13):
				var pose := at_station(points, lerpf(support_start, support_end, sample / 13.0))
				var hit := cast_down(context, pose.origin)
				if not is_pavement(hit):
					supported_deck = false
					continue
				for direction in [-1.0, 1.0]:
					var from: Vector3 = hit.position + Vector3.UP * 0.62
					var rail := context.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + pose.basis.x * float(direction) * 10.0))
					supported_rails = supported_rails and not rail.is_empty() and rail.collider.get_meta("world_surface", "") == "barrier"
			check(supported_deck and supported_rails, id + " new elevated span has continuous deck and rails on both sides")
			check(await drive_crossing(drive, points, support_start, support_end), id + " new elevated span crossed with live chassis")
		if not profile.has("bridge_start"):
			continue
		crossings += 1
		var before := float(profile["bridge_start"])
		var after := float(profile["bridge_end"])
		var wet := 0
		var deck := true
		var rails := false
		for sample in 13:
			var t := lerpf(before - 6.0, after + 6.0, sample / 12.0)
			var pose := at_station(points, t)
			var hit := cast_down(context, pose.origin)
			if not is_pavement(hit):
				deck = false
				continue
			var floor_y: float = world.get_surface_height_at(pose.origin.x, pose.origin.z)
			if floor_y < float(profile["water_level"]) and hit.position.y > float(profile["water_level"]):
				wet += 1
			if sample == 6:
				var from: Vector3 = hit.position + Vector3.UP * 0.62
				var edge := context.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + pose.basis.x * 8.0))
				rails = not edge.is_empty() and edge.collider.get_meta("world_surface", "") == "barrier"
		check(deck and wet >= 3 and rails, "%s has continuous road collision, water below %d sampled stations and solid rails" % [id, wet])
		if not capture_dir.is_empty():
			await capture(drive, id, at_station(points, lerpf(before, after, 0.32)))
		var crossed := await drive_crossing(drive, points, before, after)
		check(crossed, id + " crossed on the live car chassis under throttle and steering")
	check(checked == 5 and crossings == 3 and supported_spans == 1, "Verified five widened approaches, three water crossings and one new elevated span")
	if not capture_dir.is_empty():
		await capture_alder(drive)
	quit(failures)

func at_station(points: PackedVector3Array, station: float) -> Transform3D:
	var current := 0.0
	for index in range(1, points.size()):
		var delta := points[index] - points[index - 1]
		var distance := Vector2(delta.x, delta.z).length()
		if current + distance >= station:
			var heading := Vector3(delta.x, 0, delta.z).normalized()
			return Transform3D(Basis.looking_at(heading), points[index - 1].lerp(points[index], (station - current) / distance))
		current += distance
	return Transform3D.IDENTITY

func cast_down(context: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	return context.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 5.0))

func is_pavement(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit.collider.get_meta("world_surface", "") in ["asphalt", "gravel"]

func drive_crossing(drive: Node, points: PackedVector3Array, first: float, last: float) -> bool:
	var approach := at_station(points, first - 12.0)
	var pose = drive._road_pose(approach.origin, -approach.basis.z)
	if pose == null:
		return false
	drive.adapter.reset_to(pose)
	drive.camera.snap_to_vehicle()
	Input.action_press("drive_throttle", 0.65)
	var grounded_ticks := 0
	var crossing_ticks := 0
	var finished := false
	for tick in 1250:
		await physics_frame
		var body = drive.vehicle_body
		var position: Vector3 = body.global_position
		var station := nearest_station(points, position, first - 20.0, last + 15.0)
		var target := at_station(points, station + 7.0).origin
		var aim := Vector2(target.x - position.x, target.z - position.z).normalized()
		var forward := Vector2(-body.global_basis.z.x, -body.global_basis.z.z).normalized()
		var correction := clampf(forward.angle_to(aim) * 1.6, -0.95, 0.95)
		Input.action_release("drive_left")
		Input.action_release("drive_right")
		if absf(correction) > 0.01:
			Input.action_press("drive_right" if correction > 0.0 else "drive_left", absf(correction))
		var speed: float = drive.adapter.get_forward_speed_mps()
		if speed > 14.0:
			Input.action_release("drive_throttle")
		else:
			Input.action_press("drive_throttle", 0.71)
		if station >= first and station <= last:
			crossing_ticks += 1
			if body.wheel_array.all(func(wheel: Wheel) -> bool: return wheel.is_colliding()):
				grounded_ticks += 1
		if station > last + 4.0:
			finished = true
			break
		if position.y < at_station(points, station).origin.y - 1.8:
			break
	Input.action_release("drive_left")
	Input.action_release("drive_right")
	Input.action_release("drive_throttle")
	return finished and crossing_ticks > 0 and grounded_ticks > crossing_ticks * 0.84

func nearest_station(points: PackedVector3Array, position: Vector3, start: float, end: float) -> float:
	var traveled := 0.0
	var best := INF
	var station := start
	for index in range(1, points.size()):
		var origin := Vector2(points[index - 1].x, points[index - 1].z)
		var next := Vector2(points[index].x, points[index].z)
		var delta := next - origin
		var segment := delta.length()
		if traveled > end:
			break
		if traveled + segment >= start:
			var offset := Vector2(position.x, position.z) - origin
			var fraction := clampf(offset.dot(delta) / delta.length_squared(), 0.0, 1.0)
			var distance := (offset - delta * fraction).length_squared()
			if distance < best:
				best = distance
				station = traveled + fraction * segment
		traveled += segment
	return station

func capture(drive: Node, id: String, pose: Transform3D) -> void:
	root.size = Vector2i(1600, 900)
	var road_pose = drive._road_pose(pose.origin, -pose.basis.z)
	if road_pose != null:
		drive.adapter.reset_to(road_pose)
		drive.camera.snap_to_vehicle()
		await photo(id + "-drive")
	var scope := Camera3D.new()
	drive.add_child(scope)
	scope.far = 2500.0
	scope.fov = 55.0
	scope.position = pose.origin + pose.basis.x * 33.0 + pose.basis.z * 13.0 + Vector3.UP * 9.0
	scope.look_at(pose.origin - Vector3.UP * 2.8)
	scope.make_current()
	var hud := root.find_child("DrivingHUD", true, false)
	if hud != null:
		hud.hide()
	await photo(id + "-bridge")
	if hud != null:
		hud.show()
	scope.free()
	drive.camera.make_current()

func capture_alder(drive: Node) -> void:
	var scope := Camera3D.new()
	drive.add_child(scope)
	scope.fov = 54.0
	scope.position = Vector3(-707.5, 45.4, 532.0)
	scope.look_at(Vector3(-694.0, 44.2, 536.0))
	scope.make_current()
	var hud := root.find_child("DrivingHUD", true, false)
	if hud != null:
		hud.hide()
	await photo("alder-facade")
	if hud != null:
		hud.show()
	scope.free()

func photo(name: String) -> void:
	for frame in 45:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured " + name)

func check(passed: bool, label: String) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed:
		failures += 1
