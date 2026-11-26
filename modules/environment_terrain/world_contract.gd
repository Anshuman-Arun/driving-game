extends RefCounted
## Fixed centered-coordinate contract shared by clearance-only helpers.
const ExactClearance := preload("res://modules/world_runtime/src/road_clearance.gd")
static func has_property(object: Object, key: String) -> bool:
	if not is_instance_valid(object):
		return false
	for property in object.get_property_list():
		if str(property.name) == key:
			return true
	return false

static func generated_root(world: Node) -> Node3D:
	if not is_instance_valid(world) or not world is Node3D or not world.is_inside_tree() or world.is_queued_for_deletion():
		return null
	if not world.has_method("get_world_metadata") or not has_property(world, "generated_root"):
		return null
	if not (world as Node3D).global_transform.is_equal_approx(Transform3D.IDENTITY):
		return null
	var metadata: Variant = world.call("get_world_metadata")
	if not metadata is Dictionary or metadata.get("coordinate_system") != "godot_y_up" or not metadata.get("bounds") is Dictionary:
		return null
	var bounds: Dictionary = metadata.bounds
	if bounds.get("min_x") != -1000 or bounds.get("max_x") != 1000 or bounds.get("min_z") != -1000 or bounds.get("max_z") != 1000:
		return null
	var generated: Variant = world.get("generated_root")
	if typeof(generated) != TYPE_OBJECT or not is_instance_valid(generated) or not generated is Node3D or not generated.is_inside_tree() or generated.is_queued_for_deletion() or not world.is_ancestor_of(generated):
		return null
	if not generated.global_transform.is_equal_approx(Transform3D.IDENTITY):
		return null
	return generated as Node3D

static func clearance_for(world: Node) -> ExactClearance:
	if generated_root(world) == null or not has_property(world, "road_clearance"):
		return null
	var clearance: Variant = world.get("road_clearance")
	if typeof(clearance) != TYPE_OBJECT or not is_instance_valid(clearance) or not clearance is ExactClearance:
		return null
	var count: Variant = clearance.get("triangle_count")
	if not count is int or count <= 0:
		return null
	return clearance as ExactClearance

## Masks and water cells are tied to the repository's actual graded world.
## WorldRuntime may also load external or ungraded maps using the same bounds.
static func uses_canonical_graded_sources(world: Node) -> bool:
	if generated_root(world) == null or not has_property(world, "report") or not has_property(world, "roadworks"):
		return false
	var report: Variant = world.get("report")
	if not report is Dictionary or not report.get("source_directory") is String:
		return false
	var directory: String = ProjectSettings.globalize_path(report.source_directory).simplify_path()
	var canonical: String = ProjectSettings.globalize_path("res://data/world").simplify_path()
	if directory.trim_suffix("/") != canonical.trim_suffix("/"):
		return false
	if not FileAccess.file_exists("res://data/world/roadworks.json"):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://data/world/roadworks.json")) != OK:
		return false
	var works: Variant = world.get("roadworks")
	return works is Dictionary and not works.is_empty() and works == parser.data

static func has_complete_clearance(world: Node) -> bool:
	if clearance_for(world) == null or not has_property(world, "report"):
		return false
	var report: Variant = world.get("report")
	return report is Dictionary and report.get("full_world") == true
