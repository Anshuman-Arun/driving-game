extends SceneTree
## godot --headless --path . --script res://tests/integration/map_width_check.gd
const World = preload("res://modules/world_runtime/src/world_runtime.gd")
const Builder = preload("res://modules/world_runtime/src/mesh_builder.gd")
var failures := 0
var samples := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := World.new()
	world.build_on_ready = false
	world.build_full_world = true
	world.roadworks = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/roadworks.json"))
	root.add_child(world)
	if not world.build_world():
		quit(1)
		return
	await physics_frame
	await process_frame
	var builder := Builder.new()
	builder.network = world.roadworks["network_upgrade"]
	var space := root.get_world_3d().direct_space_state
	var roads := world.get_physical_road_centerlines()
	check(roads.size() == 16 and world.get_road_graph()["lanes"].size() == 104, "unchanged network topology")
	for road in roads:
		var points: PackedVector3Array = road["points"]
		var profile: Dictionary = world.roadworks["roads"].get(road["id"], {})
		var distances := PackedFloat32Array([0.0])
		for i in range(1, points.size()):
			var d := points[i] - points[i - 1]
			distances.append(distances[-1] + Vector2(d.x, d.z).length())
		var length := distances[-1]
		var target := float(road["target_pavement_width_m"])
		check(target >= (10.0 if road["surface"] == "asphalt" else 8.4), str(road["id"]) + " target width")
		for i in range(2, points.size() - 2, 5):
			var station := distances[i]
			if builder._network_factor(profile, station, length) < 0.99:
				continue
			var p := points[i]
			var d := points[i + 1] - points[i - 1]
			var lateral := Vector3(-d.z, 0, d.x).normalized()
			for sign_value in [-1.0, 1.0]:
				var point := p + lateral * float(sign_value) * (target * 0.5 - 0.35)
				var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 40.0, point - Vector3.UP * 40.0)
				var hit := space.intersect_ray(query)
				samples += 1
				check(not hit.is_empty() and hit.collider.get_meta("world_surface", "") in ["asphalt", "gravel"], str(road["id"]) + " expanded pavement at " + str(i))
				check(world.get_roadside_clearance(point.x, point.z) < 0.0, "clearance covers pavement")
	check(samples > 200, "network-wide edge coverage")
	print("Map width: %d edge rays, %d failures" % [samples, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
