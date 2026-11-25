class_name PlayerCarFactory
extends RefCounted
## Core vehicle presets share a temporary visual and collision envelope.
## Physics are provided by DAShoe1 Easy Vehicle Physics Vehicle/Wheel.
const VehicleScript = preload("res://addons/gevp/scripts/vehicle.gd")
const WheelScript = preload("res://addons/gevp/scripts/wheel.gd")
const DriftControllerScript = preload("res://scripts/vehicle/drift_controller.gd")
const AudioControllerScript = preload("res://modules/audio/audio_controller.gd")

const DEFAULT_CAR := "aventador_svj"
const PRESETS := {
	"vela_gt": {"name": "VelaGT", "mass": 1390.0, "torque": 480.0, "final_drive": 3.6, "front_split": 0.0, "paint": Color(0.075, 0.21, 0.41), "idle_rpm": 950.0, "max_rpm": 7100.0},
	"orion_rs": {"name": "OrionRS", "mass": 1190.0, "torque": 380.0, "final_drive": 3.9, "front_split": 0.0, "paint": Color(0.08, 0.45, 0.34), "idle_rpm": 1000.0, "max_rpm": 8500.0},
	"kestrel_xr": {"name": "KestrelXR", "mass": 1540.0, "torque": 575.0, "final_drive": 3.3, "front_split": 0.35, "paint": Color(0.33, 0.22, 0.52), "idle_rpm": 800.0, "max_rpm": 6900.0},
	"solace_gt": {"name": "SolaceGT", "mass": 1620.0, "torque": 510.0, "final_drive": 3.45, "front_split": 0.20, "paint": Color("#447b82"), "idle_rpm": 950.0, "max_rpm": 7100.0},
	"aventador_svj": {"name": "AventadorSVJ", "mass": 1670.0, "torque": 720.0, "final_drive": 3.52, "front_split": 0.28, "paint": Color("#ed9f35"), "idle_rpm": 900.0, "max_rpm": 8700.0, "half_track": Vector2(0.8864, 0.9052), "half_wheelbase": 1.3408, "radii": Vector2(0.3074, 0.3668), "widths": Vector2(255, 355), "body_length": 4.75},
	"mclaren_senna": {"name": "McLarenSenna", "mass": 1380.0, "torque": 800.0, "final_drive": 3.31, "front_split": 0.0, "paint": Color("#2b82ba"), "idle_rpm": 980.0, "max_rpm": 8000.0, "half_track": Vector2(0.8432, 0.8432), "half_wheelbase": 1.2678, "radii": Vector2(0.3458, 0.3458), "widths": Vector2(245, 315), "body_length": 4.58, "audio_profile": "kestrel_xr"},
}

static func create(car_id: String = DEFAULT_CAR) -> Vehicle:
	if not PRESETS.has(car_id):
		car_id = DEFAULT_CAR
	var preset: Dictionary = PRESETS[car_id]
	var car: Vehicle = VehicleScript.new()
	car.name = preset["name"]
	car.set_meta("vehicle_id", car_id)
	car.collision_layer = 2
	car.collision_mask = 1
	car.contact_monitor = true
	car.max_contacts_reported = 8
	car.can_sleep = false
	car.linear_damp = 0.05
	car.angular_damp = 0.10

	# Simcade starting tune derived from GEVP's simcade example, re-authored for Vela GT.
	car.vehicle_mass = preset["mass"]
	car.max_torque = preset["torque"]
	car.max_rpm = float(preset.get("max_rpm", 7100.0))
	car.idle_rpm = float(preset.get("idle_rpm", 950.0))
	car.final_drive = preset["final_drive"]
	car.front_torque_split = preset["front_split"]
	car.automatic_transmission = true
	car.front_weight_distribution = 0.52
	car.center_of_gravity_height_offset = -0.22
	car.inertia_multiplier = 1.35
	car.max_steering_angle = deg_to_rad(34.0)
	car.steering_exponent = 1.75
	car.steering_speed = 5.0
	car.countersteer_speed = 10.0
	car.steering_speed_decay = 0.13
	car.steering_slip_assist = 0.25
	car.countersteer_assist = 0.75
	car.stability_yaw_strength = 5.2
	car.stability_yaw_ground_multiplier = 1.6
	car.traction_control_max_slip = 6.0
	car.front_spring_length = 0.22
	car.rear_spring_length = 0.24
	car.front_resting_ratio = 0.55
	car.rear_resting_ratio = 0.55
	car.front_damping_ratio = 0.63
	car.rear_damping_ratio = 0.62
	car.front_arb_ratio = 0.28
	car.rear_arb_ratio = 0.25
	var radii: Vector2 = preset.get("radii", Vector2(0.35, 0.35))
	var widths: Vector2 = preset.get("widths", Vector2(245, 265))
	car.front_tire_radius = radii.x
	car.rear_tire_radius = radii.y
	car.front_tire_width = widths.x
	car.rear_tire_width = widths.y
	car.front_brake_bias = 0.63
	car.coefficient_of_friction = {"Road": 2.9, "Dirt": 1.8, "Grass": 1.45}
	car.tire_stiffnesses = {"Road": 9.0, "Dirt": 2.0, "Grass": 1.3}
	car.rolling_resistance = {"Road": 1.0, "Dirt": 2.0, "Grass": 3.5}
	car.lateral_grip_assist = {"Road": 0.045, "Dirt": 0.02, "Grass": 0.0}
	car.longitudinal_grip_ratio = {"Road": 0.7, "Dirt": 0.65, "Grass": 0.6}
	var curve := Curve.new()
	for point in [Vector2(0.0, 0.55), Vector2(0.17, 0.8), Vector2(0.4, 1.0), Vector2(0.70, 0.93), Vector2(1.0, 0.63)]:
		curve.add_point(point)
	car.torque_curve = curve

	var collider := CollisionShape3D.new()
	collider.name = "BodyCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.86, 0.56, float(preset.get("body_length", 4.23)))
	collider.shape = shape
	collider.position = Vector3(0, 0.17, 0)
	car.add_child(collider)

	var fallback := Node3D.new()
	fallback.name = "FallbackBody"
	car.add_child(fallback)
	var paint := _material(preset["paint"], 0.34, 0.42)
	var dark := _material(Color(0.015, 0.025, 0.040), 0.65, 0.0)
	var glass := _material(Color(0.042, 0.10, 0.15), 0.15, 0.2)
	var rim := _material(Color(0.52, 0.58, 0.63), 0.31, 0.65)
	var light := _material(Color(0.96, 0.93, 0.73), 0.2, 0.0)
	var red := _material(Color(0.72, 0.06, 0.035), 0.24, 0.0)
	_box(fallback, "SculptedBody", Vector3(1.91, 0.36, 4.25), Vector3(0, 0.23, 0.0), paint)
	_box(fallback, "Nose", Vector3(1.77, 0.16, 1.15), Vector3(0, 0.29, -1.49), paint)
	_box(fallback, "Cabin", Vector3(1.55, 0.40, 2.00), Vector3(0, 0.64, 0.16), glass)
	_box(fallback, "Roof", Vector3(1.43, 0.09, 1.18), Vector3(0, 0.88, 0.23), paint)
	_box(fallback, "FrontGrille", Vector3(1.36, 0.16, 0.06), Vector3(0, 0.19, -2.13), dark)
	_box(fallback, "RearDiffuser", Vector3(1.46, 0.18, 0.08), Vector3(0, 0.18, 2.11), dark)
	for side in [-1.0, 1.0]:
		_box(fallback, "Headlamp", Vector3(0.32, 0.11, 0.12), Vector3(side * 0.72, 0.36, -2.08), light)
		_box(fallback, "TailLamp", Vector3(0.36, 0.12, 0.09), Vector3(side * 0.70, 0.36, 2.10), red)
		_box(fallback, "SideSkirt", Vector3(0.12, 0.14, 2.15), Vector3(side * 0.94, 0.06, 0.02), dark)
		_box(fallback, "Mirror", Vector3(0.24, 0.10, 0.31), Vector3(side * 0.83, 0.66, -0.49), paint)
	_box(fallback, "SpoilerBlade", Vector3(1.70, 0.075, 0.32), Vector3(0, 0.63, 1.98), dark)
	var track: Vector2 = preset.get("half_track", Vector2(0.88, 0.88))
	var half_wheelbase: float = preset.get("half_wheelbase", 0.0)
	for front in [true, false]:
		for left in [true, false]:
			var wheel = WheelScript.new()
			wheel.name = ("Front" if front else "Rear") + ("Left" if left else "Right")
			var lateral := track.x if front else track.y
			var longitudinal := (-half_wheelbase if front else half_wheelbase) if half_wheelbase > 0.0 else (-1.36 if front else 1.35)
			var radius := radii.x if front else radii.y
			wheel.position = Vector3(-lateral if left else lateral, 0.03 + radius - radii.x, longitudinal)
			wheel.target_position = Vector3(0, -0.95, 0)
			wheel.enabled = false
			wheel.exclude_parent = true
			wheel.collision_mask = 1
			wheel.vehicle = car
			wheel.surface_grip_blend_time = 0.08
			var pivot := Node3D.new()
			pivot.name = "WheelVisual"
			# GEVP animates suspension travel and wheel spin on render frames.
			pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			wheel.add_child(pivot)
			wheel.wheel_node = pivot
			var rubber := MeshInstance3D.new()
			rubber.name = "Rubber"
			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = radius
			tire_mesh.bottom_radius = radius
			tire_mesh.height = 0.27
			rubber.mesh = tire_mesh
			rubber.rotation.z = PI * 0.5
			rubber.material_override = dark
			pivot.add_child(rubber)
			var hub := MeshInstance3D.new()
			hub.name = "Hub"
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.21
			hub_mesh.bottom_radius = 0.21
			hub_mesh.height = 0.283
			hub.mesh = hub_mesh
			hub.rotation.z = PI * 0.5
			hub.material_override = rim
			pivot.add_child(hub)
			if front and left:
				car.front_left_wheel = wheel
			elif front:
				car.front_right_wheel = wheel
			elif left:
				car.rear_left_wheel = wheel
			else:
				car.rear_right_wheel = wheel
			car.add_child(wheel)
	var mounts := Node3D.new()
	mounts.name = "CameraMounts"
	car.add_child(mounts)
	_marker(mounts, "Hood", Vector3(0.0, 0.86, -0.92))
	_marker(mounts, "Cockpit", Vector3(-0.34, 0.94, -0.05))
	var drift := DriftControllerScript.new()
	car.add_child(drift)
	var audio := AudioControllerScript.new()
	audio.name = "VehicleAudio"
	audio.car_profile = preset.get("audio_profile", car_id if AudioControllerScript.PROFILES.has(car_id) else "vela_gt")
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	car.add_child(audio)
	audio.bind_gevp_vehicle(car)
	return car

static func _marker(parent: Node3D, label: String, offset: Vector3) -> void:
	var mount := Marker3D.new()
	mount.name = label
	mount.position = offset
	parent.add_child(mount)

static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

static func _box(parent: Node3D, label: String, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
