class_name PlayerCarFactory
extends RefCounted
## The Vela GT is an original, geometry-only fictional RWD coupe.
## Physics are provided by DAShoe1 Easy Vehicle Physics Vehicle/Wheel.
const VehicleScript = preload("res://addons/gevp/scripts/vehicle.gd")
const WheelScript = preload("res://addons/gevp/scripts/wheel.gd")

static func create() -> Vehicle:
	var car: Vehicle = VehicleScript.new()
	car.name = "VelaGT"
	car.collision_layer = 2
	car.collision_mask = 1
	car.contact_monitor = true
	car.max_contacts_reported = 8
	car.can_sleep = false
	car.linear_damp = 0.05
	car.angular_damp = 0.10

	# Simcade starting tune derived from GEVP's simcade example, re-authored for Vela GT.
	car.vehicle_mass = 1390.0
	car.max_torque = 480.0
	car.max_rpm = 7100.0
	car.idle_rpm = 950.0
	car.final_drive = 3.6
	car.front_torque_split = 0.0  # rear wheel drive
	car.automatic_transmission = true
	car.front_weight_distribution = 0.52
	car.center_of_gravity_height_offset = -0.22
	car.inertia_multiplier = 1.35
	car.max_steering_angle = deg_to_rad(34.0)
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
	car.front_tire_radius = 0.35
	car.rear_tire_radius = 0.35
	car.front_tire_width = 245.0
	car.rear_tire_width = 265.0
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
	shape.size = Vector3(1.86, 0.56, 4.23)
	collider.shape = shape
	collider.position = Vector3(0, 0.17, 0)
	car.add_child(collider)

	var blue := _material(Color(0.075, 0.21, 0.41), 0.34, 0.42)
	var dark := _material(Color(0.015, 0.025, 0.040), 0.65, 0.0)
	var glass := _material(Color(0.042, 0.10, 0.15), 0.15, 0.2)
	var rim := _material(Color(0.52, 0.58, 0.63), 0.31, 0.65)
	var light := _material(Color(0.96, 0.93, 0.73), 0.2, 0.0)
	var red := _material(Color(0.72, 0.06, 0.035), 0.24, 0.0)
	_box(car, "SculptedBody", Vector3(1.91, 0.36, 4.25), Vector3(0, 0.23, 0.0), blue)
	_box(car, "Nose", Vector3(1.77, 0.16, 1.15), Vector3(0, 0.29, -1.49), blue)
	_box(car, "Cabin", Vector3(1.55, 0.40, 2.00), Vector3(0, 0.64, 0.16), glass)
	_box(car, "Roof", Vector3(1.43, 0.09, 1.18), Vector3(0, 0.88, 0.23), blue)
	_box(car, "FrontGrille", Vector3(1.36, 0.16, 0.06), Vector3(0, 0.19, -2.13), dark)
	_box(car, "RearDiffuser", Vector3(1.46, 0.18, 0.08), Vector3(0, 0.18, 2.11), dark)
	for side in [-1.0, 1.0]:
		_box(car, "Headlamp", Vector3(0.32, 0.11, 0.12), Vector3(side * 0.72, 0.36, -2.08), light)
		_box(car, "TailLamp", Vector3(0.36, 0.12, 0.09), Vector3(side * 0.70, 0.36, 2.10), red)
		_box(car, "SideSkirt", Vector3(0.12, 0.14, 2.15), Vector3(side * 0.94, 0.06, 0.02), dark)
		_box(car, "Mirror", Vector3(0.24, 0.10, 0.31), Vector3(side * 0.83, 0.66, -0.49), blue)
	_box(car, "SpoilerBlade", Vector3(1.70, 0.075, 0.32), Vector3(0, 0.63, 1.98), dark)
	for front in [true, false]:
		for left in [true, false]:
			var wheel = WheelScript.new()
			wheel.name = ("Front" if front else "Rear") + ("Left" if left else "Right")
			wheel.position = Vector3(-0.88 if left else 0.88, 0.03, -1.36 if front else 1.35)
			wheel.target_position = Vector3(0, -0.95, 0)
			wheel.enabled = true
			wheel.exclude_parent = true
			wheel.collision_mask = 1
			wheel.vehicle = car
			var pivot := Node3D.new()
			pivot.name = "WheelVisual"
			# GEVP animates suspension travel and wheel spin on render frames.
			pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			wheel.add_child(pivot)
			wheel.wheel_node = pivot
			var rubber := MeshInstance3D.new()
			rubber.name = "Rubber"
			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = 0.35
			tire_mesh.bottom_radius = 0.35
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
	return car

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
