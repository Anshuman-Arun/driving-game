class_name VehicleVisualFX
extends Node3D
## Runtime visual polish & animation controller for curated hero vehicles:
## - Static brake calipers synced to wheel suspension without spinning
## - Emissive headlights + subtle forward SpotLight3D beams
## - Dynamic brake/tail light emission + red OmniLight3D glow
## - Reverse light emission when in reverse gear
## - SteeringWheel rotation synced to vehicle.steering_amount
## - GPUParticles3D tire smoke (Road) and dust (Dirt/Grass) on slip/speed
## - Subtle exhaust shift flash on high-RPM upshifts

var _vehicle: Vehicle
var _caliper_pairs: Array[Dictionary] = []
var _headlight_mats: Array[StandardMaterial3D] = []
var _taillight_mats: Array[StandardMaterial3D] = []
var _reverselight_mats: Array[StandardMaterial3D] = []
var _brake_light: OmniLight3D
var _exhaust_light: OmniLight3D
var _steering_wheel: Node3D
var _steering_base_basis: Basis = Basis.IDENTITY
var _wheel_fx: Array[Dictionary] = []

var _brake_blend: float = 0.0
var _prev_gear: int = 0
var _exhaust_flash_t: float = 0.0


func setup(vehicle: Vehicle, model: Node3D, caliper_pairs: Array[Dictionary]) -> void:
	name = "VehicleVisualFX"
	_vehicle = vehicle
	_caliper_pairs = caliper_pairs

	_bind_lights(model)
	_bind_steering_wheel(model)
	_create_headlight_beams()
	_create_brake_and_exhaust_lights()
	_create_tire_particles()


func _bind_lights(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var lname := mi.name.to_lower()
		if lname.begins_with("headlight"):
			_collect_unique_materials(mi, _headlight_mats, Color(0.92, 0.96, 1.0), 2.4)
		elif lname.begins_with("taillight"):
			_collect_unique_materials(mi, _taillight_mats, Color(0.95, 0.015, 0.012), 0.45)
		elif lname.begins_with("reverselight"):
			_collect_unique_materials(mi, _reverselight_mats, Color(0.95, 0.97, 1.0), 0.05)


func _collect_unique_materials(mi: MeshInstance3D, out: Array[StandardMaterial3D], emission_col: Color, energy: float) -> void:
	var surf_count := mi.mesh.get_surface_count()
	for s in range(surf_count):
		var src := mi.get_active_material(s)
		var mat: StandardMaterial3D
		if src is StandardMaterial3D:
			mat = src.duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
			mat.albedo_color = emission_col
		mat.emission_enabled = true
		mat.emission = emission_col
		mat.emission_energy_multiplier = energy
		mi.set_surface_override_material(s, mat)
		out.append(mat)


func _bind_steering_wheel(model: Node3D) -> void:
	var sw := model.find_child("SteeringWheel", true, false) as Node3D
	if sw != null:
		_steering_wheel = sw
		_steering_base_basis = sw.basis


func _create_headlight_beams() -> void:
	for side in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.name = "HeadlightBeamL" if side < 0.0 else "HeadlightBeamR"
		spot.position = Vector3(side * 0.66, 0.34, -2.08)
		spot.rotation_degrees = Vector3(-6.0, side * -3.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.86)
		spot.light_energy = 2.4
		spot.spot_range = 34.0
		spot.spot_angle = 36.0
		spot.spot_attenuation = 1.4
		spot.shadow_enabled = false
		add_child(spot)


func _create_brake_and_exhaust_lights() -> void:
	_brake_light = OmniLight3D.new()
	_brake_light.name = "BrakeGlow"
	_brake_light.position = Vector3(0.0, 0.42, 2.38)
	_brake_light.light_color = Color(1.0, 0.04, 0.02)
	_brake_light.light_energy = 0.08
	_brake_light.omni_range = 1.85
	_brake_light.omni_attenuation = 2.2
	_brake_light.shadow_enabled = false
	add_child(_brake_light)

	_exhaust_light = OmniLight3D.new()
	_exhaust_light.name = "ExhaustFlash"
	_exhaust_light.position = Vector3(0.0, 0.16, 2.22)
	_exhaust_light.light_color = Color(1.0, 0.52, 0.14)
	_exhaust_light.light_energy = 0.0
	_exhaust_light.omni_range = 3.2
	_exhaust_light.omni_attenuation = 1.8
	_exhaust_light.shadow_enabled = false
	add_child(_exhaust_light)


func _create_tire_particles() -> void:
	if _vehicle == null:
		return
	var wheels: Array[Wheel] = [
		_vehicle.front_left_wheel,
		_vehicle.front_right_wheel,
		_vehicle.rear_left_wheel,
		_vehicle.rear_right_wheel,
	]
	var smoke_quad := _make_particle_quad(Color(0.86, 0.88, 0.90, 0.34), 0.52)
	var dust_quad := _make_particle_quad(Color(0.58, 0.48, 0.36, 0.42), 0.58)

	for i in range(wheels.size()):
		var wheel := wheels[i]
		if wheel == null:
			continue
		var smoke := _make_emitter("TireSmoke_%d" % i, smoke_quad, 18, 0.75, 1.3)
		var dust := _make_emitter("TireDust_%d" % i, dust_quad, 18, 0.65, 1.8)
		add_child(smoke)
		add_child(dust)
		_wheel_fx.append({
			"wheel": wheel,
			"smoke": smoke,
			"dust": dust,
		})


func _make_particle_quad(tint: Color, quad_size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	return quad


func _make_emitter(node_name: String, mesh: Mesh, amount: int, lifetime: float, spread_vel: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.draw_pass_1 = mesh
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.65, 0.4)
	proc.spread = 38.0
	proc.initial_velocity_min = spread_vel * 0.4
	proc.initial_velocity_max = spread_vel
	proc.gravity = Vector3(0.0, 0.45, 0.0)
	proc.scale_min = 0.65
	proc.scale_max = 1.65
	proc.damping_min = 1.2
	proc.damping_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.75))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex
	p.process_material = proc
	return p


func _process(delta: float) -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return

	# 1. Sync static brake calipers to suspension travel (steer comes from parent Wheel!)
	for entry in _caliper_pairs:
		var wheel := entry["wheel"] as Wheel
		var caliper := entry["caliper"] as Node3D
		if wheel != null and wheel.wheel_node != null and is_instance_valid(caliper):
			caliper.position.y = wheel.wheel_node.position.y

	# 2. Dynamic brake & tail lights
	var braking := _vehicle.brake_input > 0.05 or _vehicle.handbrake_input > 0.1
	_brake_blend = move_toward(_brake_blend, 1.0 if braking else 0.0, delta * 14.0)
	var tail_energy := lerpf(0.45, 2.8, _brake_blend)
	for mat in _taillight_mats:
		mat.emission_energy_multiplier = tail_energy
	if _brake_light != null:
		_brake_light.light_energy = lerpf(0.08, 0.85, _brake_blend)

	# 3. Reverse lights
	var reversing := _vehicle.current_gear == -1
	var rev_energy := 4.4 if reversing else 0.05
	for mat in _reverselight_mats:
		mat.emission_energy_multiplier = rev_energy

	# 4. Steering wheel rotation
	if _steering_wheel != null and is_instance_valid(_steering_wheel):
		var steer_angle := _vehicle.steering_amount * 2.1
		_steering_wheel.basis = _steering_base_basis * Basis(Vector3(0.0, -0.34, 1.0).normalized(), steer_angle)

	# 5. Exhaust shift flash on high-RPM upshift
	var gear := _vehicle.current_gear
	if gear > _prev_gear and _prev_gear >= 1 and _vehicle.motor_rpm > _vehicle.max_rpm * 0.62:
		_exhaust_flash_t = 0.14
	_prev_gear = gear
	if _exhaust_light != null:
		if _exhaust_flash_t > 0.0:
			_exhaust_flash_t = maxf(0.0, _exhaust_flash_t - delta)
			_exhaust_light.light_energy = (_exhaust_flash_t / 0.14) * 3.8
		else:
			_exhaust_light.light_energy = 0.0

	# 6. Tire smoke (Road) and dust (Dirt/Grass)
	var speed := _vehicle.speed
	var handbrake := _vehicle.handbrake_input > 0.1
	for item in _wheel_fx:
		var wheel := item["wheel"] as Wheel
		var smoke := item["smoke"] as GPUParticles3D
		var dust := item["dust"] as GPUParticles3D
		if wheel == null or wheel.wheel_node == null:
			continue
		var contact_local := wheel.position + Vector3(0.0, wheel.wheel_node.position.y - wheel.tire_radius * 0.82, 0.0)
		smoke.position = contact_local
		dust.position = contact_local
		if not wheel.is_colliding():
			smoke.emitting = false
			dust.emitting = false
			continue
		var slip := wheel.slip_vector.length()
		var surface := wheel.surface_type
		if surface == "Dirt" or surface == "Grass":
			smoke.emitting = false
			dust.emitting = speed > 3.5 or slip > 0.30
		else:
			dust.emitting = false
			smoke.emitting = (slip > 0.42 and speed > 2.5) or (handbrake and speed > 4.5)
