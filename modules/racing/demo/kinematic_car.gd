extends Node3D
## DEMO ONLY: simple kinematic bicycle approximation for testing AI outputs.
## Production rivals must use the Core Agent's actual physics + VehicleAdapter.
var speed_mps: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var acceleration_mps2: float = 8.5
var brake_mps2: float = 12.0
var wheelbase_m: float = 2.6
var max_steer_rad: float = 0.55
var paint: Color = Color(0.85, 0.25, 0.2)

func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 0.9, 4.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = paint
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = 0.7
	add_child(visual)

func set_drive_input(new_steer: float, new_throttle: float, new_brake: float, _handbrake: bool) -> void:
	steer = clampf(new_steer, -1.0, 1.0)
	throttle = clampf(new_throttle, 0.0, 1.0)
	brake = clampf(new_brake, 0.0, 1.0)

func teleport_to(location: Vector3, forward: Vector3) -> void:
	global_position = location
	rotation.y = atan2(forward.x, -forward.z)
	speed_mps = 0.0
	steer = 0.0
	throttle = 0.0
	brake = 0.0

func advance(delta: float) -> void:
	var net: float = throttle * acceleration_mps2 - brake * brake_mps2 - 0.35 - speed_mps * speed_mps * 0.008
	speed_mps = maxf(0.0, speed_mps + net * delta)
	rotation.y += tan(steer * max_steer_rad) * speed_mps / wheelbase_m * delta
	global_position += -global_transform.basis.z * speed_mps * delta

func get_drive_velocity() -> Vector3:
	return -global_transform.basis.z * speed_mps
