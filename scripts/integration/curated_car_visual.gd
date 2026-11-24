extends RefCounted
## Compatibility & Forza-grade visual rigging for authored AssetRoot / Body_Shell / Wheel_*_Pivot GLBs.

const DIRECTORY := "res://assets/curated/models/vehicles/"
const CORNERS := ["FL", "FR", "RL", "RR"]
const VisualFX = preload("res://scripts/integration/vehicle_visual_fx.gd")
const TOURER := "res://assets/premium_runtime/solace_gt.glb"
const EXACT_MODELS := {
	"aventador_svj": "res://assets/premium_runtime/aventador_svj.glb",
	"mclaren_senna": "res://assets/premium_runtime/mclaren_senna.glb",
}


static func load_model(car_id: String) -> Node3D:
	if not PlayerCarFactory.PRESETS.has(car_id):
		return null
	var path: String = EXACT_MODELS.get(car_id, TOURER if car_id == "solace_gt" else DIRECTORY + car_id + ".glb")
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
	if car_id == "solace_gt":
		model = _touring_rig(model)
		if model == null:
			return null
	var body := model.find_child("Body_Shell", true, false) as MeshInstance3D
	if body == null or body.mesh == null or _wheel_pivots(model).is_empty():
		model.free()
		return null
	var paint: Color = PlayerCarFactory.PRESETS[car_id]["paint"]
	if EXACT_MODELS.has(car_id):
		_finish_source_materials(model, paint, car_id == "mclaren_senna")
	else:
		_polish_materials(model)
		CarMaterialSpec.apply_to_vehicle(model, paint, paint.lightened(0.21))
	model.name = "CuratedCar"
	return model


static func _finish_source_materials(model: Node3D, paint: Color, has_cabin: bool) -> void:
	var body_paint := CarMaterialSpec.create_car_paint(paint, paint.lightened(0.12), 0.021, 0.41, 0.32, 0.60, 0.20)
	var cache := {}
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if source.resource_name == "CarPaint":
				node.set_surface_override_material(surface, body_paint)
				continue
			if not cache.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var label := source.resource_name.to_lower()
				if label.begins_with("cabinglass"):
					material.albedo_color = Color(0.053, 0.077, 0.090, 0.58 if has_cabin else 1.0)
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if has_cabin else BaseMaterial3D.TRANSPARENCY_DISABLED
					material.metallic = 0.12 if has_cabin else 0.29
					material.roughness = 0.23
				elif label == "carbon" or label == "a_carbon":
					material.albedo_color *= Color(0.63, 0.67, 0.72)
					material.metallic = minf(material.metallic, 0.23)
					material.roughness = maxf(material.roughness, 0.44)
				else:
					material.roughness = maxf(material.roughness, 0.21)
				cache[source] = material
			node.set_surface_override_material(surface, cache[source])


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
		var radius := (tire.transform * tire.get_aabb()).size.y * 0.5
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

	CarMaterialSpec.attach_contact_shadow(car)

	fallback.hide()
	for visual in fallback_wheels:
		visual.hide()
	return true


static func _touring_rig(source: Node3D) -> Node3D:
	var body := source.find_child("body", true, false) as MeshInstance3D
	var originals: Array[MeshInstance3D] = []
	for corner: String in CORNERS:
		var wheel := source.find_child("wheel_" + corner + "_mesh", true, false) as MeshInstance3D
		if body == null or wheel == null:
			source.free()
			return null
		originals.append(wheel)
	var model := Node3D.new()
	model.add_child(source)
	source.rotate_y(PI)
	body.name = "Body_Shell"
	for i in CORNERS.size():
		var corner: String = CORNERS[i]
		var wheel := originals[i]
		var frame := _model_transform(wheel, model)
		var pivot := Node3D.new()
		pivot.name = "Wheel_" + corner + "_Pivot"
		pivot.position = _model_transform(wheel.get_parent() as Node3D, model).origin
		model.add_child(pivot)
		wheel.owner = null
		wheel.get_parent().remove_child(wheel)
		pivot.add_child(wheel)
		wheel.name = "Tire_" + corner
		wheel.transform = pivot.transform.affine_inverse() * frame
		var caliper := source.find_child("caliper_" + corner, true, false) as MeshInstance3D
		if caliper == null:
			continue
		var caliper_frame := _model_transform(caliper, model)
		var static_mount := Node3D.new()
		static_mount.name = "Brake_" + corner
		static_mount.position = pivot.position
		model.add_child(static_mount)
		caliper.owner = null
		caliper.get_parent().remove_child(caliper)
		static_mount.add_child(caliper)
		caliper.transform = static_mount.transform.affine_inverse() * caliper_frame
	for lamp in [["light_front", "HeadlightTourer"], ["light_rear", "TaillightTourer"]]:
		var node := source.find_child(lamp[0], true, false)
		if node != null:
			node.name = lamp[1]
	var steering := source.find_child("steering_wheel_mesh", true, false)
	if steering != null:
		steering.get_parent().name = "SteeringWheel"
	return model


static func _model_transform(node: Node3D, model: Node3D) -> Transform3D:
	var frame := Transform3D.IDENTITY
	while node != model:
		frame = node.transform * frame
		node = node.get_parent() as Node3D
	return frame


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
			elif "chrome_trim" in mname:
				mat.albedo_color = Color("#393e43")
				mat.metallic = 0.63
				mat.roughness = 0.32
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
		var pivot := model.find_child("Wheel_" + corner + "_Pivot", true, false) as Node3D
		if pivot == null:
			return []
		var tire := pivot.get_node_or_null("Tire_" + corner) as MeshInstance3D
		if tire == null or tire.mesh == null or tire.get_aabb().size.y <= 0.0:
			return []
		pivots.append(pivot)
	return pivots
