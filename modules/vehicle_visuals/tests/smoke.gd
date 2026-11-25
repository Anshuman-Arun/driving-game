extends SceneTree
## Non-graphical regression checks. Requires a Godot 4.7.2 project at repo root.
## Run: godot --headless --path . --script res://modules/vehicle_visuals/tests/smoke.gd
const ADAPTER = preload("res://modules/vehicle_visuals/vehicle_visual_adapter.gd")

class MockWheel:
	extends Node3D
	var wheel_node: Node3D
	func _init() -> void:
		wheel_node = Node3D.new()
		wheel_node.name = "WheelVisual"
		add_child(wheel_node)

class MockVehicle:
	extends Node3D
	var front_left_wheel: MockWheel
	var front_right_wheel: MockWheel
	var rear_left_wheel: MockWheel
	var rear_right_wheel: MockWheel
	func _init() -> void:
		front_left_wheel = MockWheel.new()
		front_right_wheel = MockWheel.new()
		rear_left_wheel = MockWheel.new()
		rear_right_wheel = MockWheel.new()
		for wheel: MockWheel in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
			add_child(wheel)

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(result: bool, message: String) -> void:
	assertions += 1
	if not result:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var vehicle := MockVehicle.new()
	get_root().add_child(vehicle)
	vehicle.name = "MockGEVPChassis"
	var old_visual := MeshInstance3D.new()
	old_visual.name = "OriginalFactoryWheelRubber"
	vehicle.front_left_wheel.wheel_node.add_child(old_visual)
	var adapter: Node3D = ADAPTER.new()
	adapter.name = "VisualQA"
	adapter.set("hero_path", "res://assets/vehicle_upgrade/definitely_missing_hero.glb")
	adapter.set("mid_path", "res://assets/vehicle_upgrade/definitely_missing_mid.glb")
	adapter.set("distant_path", "res://assets/vehicle_upgrade/definitely_missing_distant.glb")
	vehicle.add_child(adapter)
	var attached: bool = adapter.connect_chassis(vehicle)
	check(not attached, "Missing HD model must not be reported attached")
	check(old_visual.visible, "Missing HD model must not hide original factory wheel")
	var status: Dictionary = adapter.get_visual_status()
	check(status["fallback"], "Fallback status must be true")
	check(not status["loaded"], "Unavailable source must not be called loaded")
	check(adapter.get_camera_mount("RearChase") != null, "Rear chase mount")
	check(adapter.get_camera_mount("Hood") != null, "Hood mount")
	check(adapter.get_camera_mount("Cockpit") != null, "Cockpit mount")
	check(not adapter.request_lod(2), "Missing distant/hero models cannot load")
	check(vehicle.front_left_wheel.wheel_node == old_visual.get_parent(),
		"Visual adapter cannot change GEVP's wheel parent")
	check(adapter.get_parent() == vehicle, "Adapter remains attached as visual child")
	print("Vehicle visuals smoke: ", assertions - failures, "/", assertions,
		" checks, ", failures, " failures")
	quit(1 if failures else 0)
