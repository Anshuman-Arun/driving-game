extends RefCounted
## Compatibility & Forza-grade visual rigging for authored AssetRoot / Body_Shell / Wheel_*_Pivot GLBs.

const DIRECTORY := "res://assets/curated/models/vehicles/"
const CORNERS := ["FL", "FR", "RL", "RR"]
const VisualFX = preload("res://scripts/integration/vehicle_visual_fx.gd")


static func load_model(car_id: String) -> Node3D:
	if not PlayerCarFactory.PRESETS.has(car_id):
		return null
	var path := DIRECTORY + car_id + ".glb"
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	var model := instance as Node3D
	if model == null:
		instance.free()
		return null
	var body := model.find_child("Body_Shell") as MeshInstance3D
	if body == null or body.mesh == null or _wheel_pivots(model).is_empty():
		model.free()
		return null
	_polish_materials(model)
	model.name = "CuratedCar"
	return model


static func mount(car: Vehicle, car_id: String) -> bool:
	var fallback := car.get_node_or_null("FallbackBody") as Node3D
	if fallback == null or car.has_node("CuratedCar"):
		return false
	var wheels: Array[Wheel] = [
		car.front_left_wheel, car.front_right_wheel, car.rear_left_wheel, car.rear_right_wheel,
	]
	for wheel in wheels:
		if wheel == null or wheel.wheel_node == null:
			return false
	var model := load_model(car_id)
	if model == null:
		return false
	var pivots := _wheel_pivots(model)
	var asset_track := pivots[1].position.x - pivots[0].position.x
	var asset_wheelbase := pivots[2].position.z - pivots[0].position.z
	if asset_track <= 0.0 or asset_wheelbase <= 0.0:
		model.free()
		return false

	var track := wheels[1].position.x - wheels[0].position.x
	var wheelbase := wheels[2].position.z - wheels[0].position.z
	var sx := track / asset_track
	var sz := wheelbase / asset_wheelbase
	# Keep vertical proportion harmonized with track/wheelbase so there is zero squash/stretch.
	var sy := clampf((sx + sz) * 0.5, 0.94, 1.06)
	model.scale = Vector3(sx, sy, sz)
	# Center the wheel arches cleanly on the loaded resting ride height with full steer & bump clearance.
	model.position.y = wheels[0].position.y - 0.105 - pivots[0].position.y * sy

	var fallback_wheels: Array[Node3D] = []
	var caliper_pairs: Array[Dictionary] = []
	for i in range(wheels.size()):
		var mount_point := wheels[i].wheel_node
		for child in mount_point.get_children():
			if child is Node3D:
				fallback_wheels.append(child)
		var pivot := pivots[i]
		var tire := pivot.get_node("Tire_" + CORNERS[i]) as MeshInstance3D
		var radius := tire.get_aabb().size.y * 0.5
		var wheel_scale := wheels[i].tire_radius / radius
		for child in pivot.find_children("*", "", true, false):
			child.owner = null
		pivot.owner = null
		pivot.get_parent().remove_child(pivot)
		# The imported geometry already uses the GEVP roll axis (+X).
		pivot.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * wheel_scale)
		mount_point.add_child(pivot)

		# Mount static Brake_{CORNER} caliper onto Wheel itself (NEVER inside wheel.wheel_node!)
		# so wheel.wheel_node keeps exact child_count == 3 and calipers steer + track suspension without spinning.
		var caliper := model.find_child("Brake_" + CORNERS[i], true, false) as Node3D
		if caliper != null:
			for child in caliper.find_children("*", "", true, false):
				child.owner = null
			caliper.owner = null
			caliper.get_parent().remove_child(caliper)
			caliper.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * wheel_scale)
			caliper.position = Vector3(0.0, mount_point.position.y, 0.0)
			wheels[i].add_child(caliper)
			caliper_pairs.append({"wheel": wheels[i], "caliper": caliper})

	car.add_child(model)

	var fx := VisualFX.new()
	fx.setup(car, model, caliper_pairs)
	car.add_child(fx)

	fallback.hide()
	for visual in fallback_wheels:
		visual.hide()
	return true


static func _polish_materials(model: Node3D) -> void:
	var local_materials := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var surf_count := mi.mesh.get_surface_count()
		for s in range(surf_count):
			var base_mat := mi.get_active_material(s)
			if not (base_mat is StandardMaterial3D):
				continue
			if local_materials.has(base_mat):
				mi.set_surface_override_material(s, local_materials[base_mat])
				continue
			var mat := base_mat.duplicate() as StandardMaterial3D
			local_materials[base_mat] = mat
			mi.set_surface_override_material(s, mat)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mat.roughness = maxf(mat.roughness, 0.18)
			var mname := mat.resource_name.to_lower()
			if "carpaint" in mname:
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.24
				mat.metallic = maxf(mat.metallic, 0.78)
				mat.roughness = maxf(mat.roughness, 0.25)
			elif "glass" in mname:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = clampf(mat.albedo_color.a, 0.26, 0.38)
				mat.roughness = 0.23
				mat.metallic = 0.12
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.27
				mat.cull_mode = BaseMaterial3D.CULL_BACK
			elif "tire" in mname:
				mat.albedo_color = Color(0.018, 0.019, 0.022, 1.0)
				mat.metallic = 0.0
				mat.roughness = 0.88
				mat.metallic_specular = 0.22
			elif "taillight" in mname:
				mat.albedo_color = Color(0.26, 0.012, 0.015, 1.0)
				mat.roughness = 0.20
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.23
				mat.emission_enabled = true
				mat.emission = Color(0.95, 0.015, 0.012)
				mat.emission_energy_multiplier = 0.45
			elif "caliper" in mname:
				mat.clearcoat_enabled = true
				mat.clearcoat = 0.85
				mat.clearcoat_roughness = 0.06


static func _wheel_pivots(model: Node3D) -> Array[Node3D]:
	var pivots: Array[Node3D] = []
	for corner: String in CORNERS:
		var pivot := model.find_child("Wheel_" + corner + "_Pivot") as Node3D
		if pivot == null:
			return []
		var tire := pivot.get_node_or_null("Tire_" + corner) as MeshInstance3D
		if tire == null or tire.mesh == null or tire.get_aabb().size.y <= 0.0:
			return []
		pivots.append(pivot)
	return pivots
