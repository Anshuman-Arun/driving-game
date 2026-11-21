@tool
extends Node3D
class_name VehicleVisualAdapter

## Presentation-only attachment. Never replaces GEVP Wheel, Vehicle, or colliders.
## Prepared GLBs have Body, Wheel_{FL,FR,RL,RR}_Pivot and Brake_{FL,FR,RL,RR}.
const WHEEL_KEYS := ["FL", "FR", "RL", "RR"]
const WHEEL_PROPERTIES := {
	"FL": "front_left_wheel",
	"FR": "front_right_wheel",
	"RL": "rear_left_wheel",
	"RR": "rear_right_wheel",
}
const DEFAULT_HERO := "res://assets/vehicle_upgrade/vela_gt_hero.glb"
const DEFAULT_MID := "res://assets/vehicle_upgrade/vela_gt_mid.glb"
const DEFAULT_DISTANT := "res://assets/vehicle_upgrade/vela_gt_distant.glb"

@export_file("*.glb", "*.tscn") var hero_path: String = DEFAULT_HERO
@export_file("*.glb", "*.tscn") var mid_path: String = DEFAULT_MID
@export_file("*.glb", "*.tscn") var distant_path: String = DEFAULT_DISTANT
@export var mid_distance_m := 27.0
@export var far_distance_m := 85.0
@export var auto_lod := true
@export var make_camera_mounts := true

var _chassis: Node3D
var _wheel_components: Dictionary = {}
var _original_visibility: Dictionary = {}
var _active_scene: Node3D
var _mounted_nodes: Array[Node3D] = []
var _brake_carriers: Dictionary = {}
var _lod := -1
var _visual_available := false
var _preview_mode := false
var _last_error := ""
var _mounts: Dictionary = {}

static func attach_to(vehicle: Node3D) -> VehicleVisualAdapter:
	var adapter := VehicleVisualAdapter.new()
	adapter.name = "VehicleVisualAdapter"
	vehicle.add_child(adapter)
	adapter.connect_chassis(vehicle)
	return adapter

func _ready() -> void:
	if make_camera_mounts:
		_make_mounts()

## Call after factory has registered four GEVP wheels. Existing wheel visuals stay
## in place unless all four replacement wheel pivots are validated.
func connect_chassis(vehicle: Node3D) -> bool:
	if vehicle == null:
		_last_error = "Missing physics chassis."
		return false
	if _chassis != null and _chassis != vehicle:
		_last_error = "Adapter is already bound to another chassis."
		return false
	_chassis = vehicle
	_preview_mode = false
	_wheel_components.clear()
	for key: String in WHEEL_KEYS:
		var property: String = WHEEL_PROPERTIES[key]
		var found: Variant = vehicle.get(property)
		if not found is Node3D:
			_last_error = "GEVP wheel missing: " + property
			return false
		var wheel: Node3D = found as Node3D
		var visual: Variant = wheel.get("wheel_node")
		if not visual is Node3D:
			_last_error = "GEVP Wheel.wheel_node missing: " + property
			return false
		_wheel_components[key] = {"wheel": wheel, "pivot": visual}
	return request_lod(0)

func setup_garage_preview() -> bool:
	if _chassis != null:
		_last_error = "Garage preview must be detached from physics chassis."
		return false
	_preview_mode = true
	clear_visuals()
	var path := hero_path
	if not ResourceLoader.exists(path):
		_last_error = "No prepared hero model at " + path
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		_last_error = "Model is not a PackedScene: " + path
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_last_error = "Model root must be Node3D."
		return false
	add_child(instance)
	_active_scene = instance
	_lod = 0
	_visual_available = true
	return true

func set_garage_preview_rotation(yaw_radians: float) -> void:
	if _preview_mode:
		rotation.y = yaw_radians

func request_lod(requested_lod: int) -> bool:
	if _preview_mode or _wheel_components.size() != 4:
		return false
	var target := clampi(requested_lod, 0, 2)
	var paths := [hero_path, mid_path, distant_path]
	# A missing LOD is not a reason to make the car invisible. Keep current
	# level (or try hero on first attach).
	if not ResourceLoader.exists(paths[target]):
		if _active_scene != null:
			return true
		target = 0
	if not ResourceLoader.exists(paths[target]):
		_last_error = "Prepared model absent; existing factory visuals retained."
		return false
	if _lod == target and _active_scene != null:
		return true
	var packed := load(paths[target]) as PackedScene
	if packed == null:
		_last_error = "Could not load PackedScene: " + paths[target]
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		_last_error = "Model root must be a Node3D."
		return false
	# Verify everything before changing the active visual or hiding originals.
	if model.get_node_or_null("Body") == null:
		_last_error = "Prepared model is missing Body."
		model.free()
		return false
	for key: String in WHEEL_KEYS:
		if model.get_node_or_null("Wheel_" + key + "_Pivot") == null:
			_last_error = "Prepared model is missing Wheel_" + key + "_Pivot."
			model.free()
			return false
	clear_visuals()
	add_child(model)
	_active_scene = model
	for key: String in WHEEL_KEYS:
		var wheel_data: Dictionary = _wheel_components[key]
		var wheel: Node3D = wheel_data["wheel"]
		var factory_pivot: Node3D = wheel_data["pivot"]
		var replacement: Node3D = model.get_node("Wheel_" + key + "_Pivot") as Node3D
		replacement.reparent(factory_pivot, false)
		replacement.transform = Transform3D.IDENTITY
		_mounted_nodes.append(replacement)
		var brake: Node3D = model.get_node_or_null("Brake_" + key) as Node3D
		if brake != null:
			brake.reparent(wheel, false)
			brake.transform = Transform3D.IDENTITY
			_mounted_nodes.append(brake)
			_brake_carriers[key] = brake
		# Factory uses a wheel_node for suspension travel and spin; its rubber
		# and hub are hidden, but GEVP remains the sole transform authority.
		for old_child: Node in factory_pivot.get_children():
			if old_child == replacement:
				continue
			if old_child is Node3D:
				if not _original_visibility.has(old_child):
					_original_visibility[old_child] = (old_child as Node3D).visible
				(old_child as Node3D).visible = false
	_lod = target
	_visual_available = true
	_last_error = ""
	return true

func clear_visuals() -> void:
	for node: Node3D in _mounted_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_mounted_nodes.clear()
	_brake_carriers.clear()
	if is_instance_valid(_active_scene):
		_active_scene.queue_free()
	_active_scene = null
	_lod = -1
	_visual_available = false
	# Safe if a model fails to load during a later quality switch.
	for old_node: Variant in _original_visibility.keys():
		if is_instance_valid(old_node):
			(old_node as Node3D).visible = _original_visibility[old_node]
	_original_visibility.clear()

func _process(_delta: float) -> void:
	if _chassis == null or not _visual_available:
		return
	# Calipers track travel and steering (from their Wheel parent) but never
	# inherit wheel spin. GEVP alone updates wheel_node's X roll/Y travel.
	for key: String in _brake_carriers.keys():
		var carrier: Node3D = _brake_carriers[key]
		var wheel_data: Dictionary = _wheel_components[key]
		var physics_pivot: Node3D = wheel_data["pivot"]
		carrier.position.y = physics_pivot.position.y
	if not auto_lod or Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var dist_squared := _chassis.global_position.distance_squared_to(camera.global_position)
	var target := 0
	if dist_squared > far_distance_m * far_distance_m:
		target = 2
	elif dist_squared > mid_distance_m * mid_distance_m:
		target = 1
	if target != _lod:
		request_lod(target)

func _make_mounts() -> void:
	if not _mounts.is_empty():
		return
	_add_mount("RearChase", Vector3(0.0, 1.55, 3.75))
	_add_mount("Hood", Vector3(0.0, 0.91, -1.63))
	_add_mount("Cockpit", Vector3(-0.34, 0.94, -0.05))

func _add_mount(key: String, offset: Vector3) -> void:
	var anchor := Marker3D.new()
	anchor.name = key + "Mount"
	anchor.position = offset
	add_child(anchor)
	_mounts[key] = anchor

func get_camera_mount(kind: String) -> Marker3D:
	return _mounts.get(kind) as Marker3D

func is_using_hero_art() -> bool:
	return _visual_available and _lod == 0 and not _preview_mode

func get_visual_status() -> Dictionary:
	return {
		"loaded": _visual_available,
		"lod": _lod,
		"fallback": not _visual_available,
		"last_error": _last_error,
		"physics_untouched": true,
	}

func _exit_tree() -> void:
	# Do not delete/mutate physics wheel objects, only adapter-created children.
	clear_visuals()
