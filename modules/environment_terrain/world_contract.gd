extends RefCounted
## Fixed centered-coordinate contract shared by clearance-only helpers.
static func has_property(object: Object, key: String) -> bool:
	if not is_instance_valid(object):
		return false
	for property in object.get_property_list():
		if str(property.name) == key:
			return true
	return false

static func generated_root(world: Node) -> Node3D:
	if not is_instance_valid(world) or not world is Node3D or not world.is_inside_tree():
		return null
	if not world.has_method("get_world_metadata") or not has_property(world, "generated_root"):
		return null
	if not (world as Node3D).global_transform.is_equal_approx(Transform3D.IDENTITY):
		return null
	var metadata: Variant = world.call("get_world_metadata")
	if not metadata is Dictionary or not metadata.get("bounds") is Dictionary:
		return null
	var bounds: Dictionary = metadata.bounds
	if bounds.get("min_x") != -1000 or bounds.get("max_x") != 1000 or bounds.get("min_z") != -1000 or bounds.get("max_z") != 1000:
		return null
	var generated: Variant = world.get("generated_root")
	if not generated is Node3D or not is_instance_valid(generated) or not generated.is_inside_tree() or not world.is_ancestor_of(generated):
		return null
	if not generated.global_transform.is_equal_approx(Transform3D.IDENTITY):
		return null
	return generated as Node3D

static func clearance_for(world: Node) -> RefCounted:
	if generated_root(world) == null or not has_property(world, "road_clearance"):
		return null
	var clearance: Variant = world.get("road_clearance")
	if not clearance is RefCounted or not clearance.has_method("overlaps") or not has_property(clearance, "triangle_count"):
		return null
	var count: Variant = clearance.get("triangle_count")
	if not count is int or count <= 0:
		return null
	return clearance as RefCounted
