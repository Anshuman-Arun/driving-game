extends RefCounted
## Compatibility for the authored AssetRoot / Body_Shell / Wheel_*_Pivot GLBs.

const DIRECTORY := "res://assets/curated/models/vehicles/"
const CORNERS := ["FL", "FR", "RL", "RR"]


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
	model.scale = Vector3(track / asset_track, 1.0, wheelbase / asset_wheelbase)
	# Center the arches on the loaded ride height, with room for suspension travel.
	model.position.y = wheels[0].position.y - 0.15 - pivots[0].position.y
	var fallback_wheels: Array[Node3D] = []
	for i in range(wheels.size()):
		var mount_point := wheels[i].wheel_node
		for child in mount_point.get_children():
			if child is Node3D:
				fallback_wheels.append(child)
		var pivot := pivots[i]
		var tire := pivot.get_node("Tire_" + CORNERS[i]) as MeshInstance3D
		var radius := tire.get_aabb().size.y * 0.5
		for child in pivot.find_children("*", "", true, false):
			child.owner = null
		pivot.owner = null
		pivot.get_parent().remove_child(pivot)
		# The imported geometry already uses the GEVP roll axis (+X).
		pivot.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * (wheels[i].tire_radius / radius))
		mount_point.add_child(pivot)
	car.add_child(model)
	fallback.hide()
	for visual in fallback_wheels:
		visual.hide()
	return true


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
