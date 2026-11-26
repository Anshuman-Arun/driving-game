extends RefCounted
## Clearance gate for an optional future visual-only embedded rock bank.
## No instantiation, terrain deformation, or collision creation is performed.
const Contract := preload("world_contract.gd")
const BOULDER := "res://assets/curated/models/environment/boulder.glb"
const LAKE := "res://content/scenery/lake/water_cells_v1.json"
const GRID := 4.0
const ORIGIN := -1000.0
const MARGIN := 0.5
const CONTACT_TOLERANCE_M := 0.05
var _water: Dictionary = {}
var _world: WeakRef
var _built_root: WeakRef
var _clearance: WeakRef
var _waters_snapshot: Array = []
var _triangle_count := 0
var status := "unprepared"
var _source_directory := ""

func _canonical_source_ok(world: Node) -> bool:
	return Contract.uses_canonical_graded_sources(world)

func prepare(world: Node) -> bool:
	_world = null
	_built_root = null
	_clearance = null
	_waters_snapshot.clear()
	_triangle_count = 0
	_source_directory = ""
	_water.clear()
	status = "water or road clearance unavailable"
	var built := Contract.generated_root(world)
	var clearance := Contract.clearance_for(world)
	if built == null or clearance == null or not Contract.has_property(world, "roadworks"):
		return false
	if not Contract.has_complete_clearance(world) or not _canonical_source_ok(world):
		status = "complete canonical graded clearance required"
		return false
	if not world.has_method("get_surface_height_at"):
		return false
	var roadworks: Variant = world.get("roadworks")
	if not roadworks is Dictionary or not roadworks.get("waters") is Array:
		return false
	if not FileAccess.file_exists(LAKE):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(LAKE)) != OK:
		return false
	var lake: Variant = parser.data
	if not lake is Dictionary or lake.get("schema_version") != 1 or lake.get("origin_x") != ORIGIN or lake.get("origin_z") != ORIGIN or lake.get("spacing_m") != GRID or not (lake.get("water_height_m") is float or lake.get("water_height_m") is int) or not is_finite(float(lake.water_height_m)):
		return false
	if not _add_cells(lake.get("cells")):
		return false
	for pool in roadworks.waters:
		if not pool is Dictionary or not (pool.get("height") is float or pool.get("height") is int) or not is_finite(float(pool.height)) or not _add_cells(pool.get("cells")):
			_water.clear()
			return false
	_world = weakref(world)
	_built_root = weakref(built)
	_clearance = weakref(clearance)
	_triangle_count = clearance.triangle_count
	_source_directory = str(world.get("report").get("source_directory", ""))
	_waters_snapshot = roadworks.waters.duplicate(true)
	status = "ready"
	return true

func _add_cells(cells: Variant) -> bool:
	if not cells is Array or cells.is_empty():
		return false
	for cell in cells:
		if not cell is Array or cell.size() != 2:
			return false
		for value in cell:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or value < 0 or value >= 500:
				return false
		_water[Vector2i(int(cell[0]), int(cell[1]))] = true
	return true

func accepts(frame: Transform3D, local_bounds: AABB) -> bool:
	if status != "ready" or _world == null or not is_instance_valid(_world.get_ref()):
		return false
	if not frame.is_finite() or absf(frame.basis.determinant()) < 0.000001 or not local_bounds.position.is_finite() or not local_bounds.size.is_finite():
		return false
	if local_bounds.size.x <= 0.0 or local_bounds.size.y <= 0.0 or local_bounds.size.z <= 0.0:
		return false
	var bounds := frame * local_bounds
	if not bounds.position.is_finite() or not bounds.size.is_finite():
		return false
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0 or bounds.size.x > 20.0 or bounds.size.y > 20.0 or bounds.size.z > 20.0:
		return false
	if bounds.position.x - MARGIN < -1000.0 or bounds.position.z - MARGIN < -1000.0 or bounds.end.x + MARGIN >= 1000.0 or bounds.end.z + MARGIN >= 1000.0:
		return false
	var world: Node = _world.get_ref()
	var clearance := Contract.clearance_for(world)
	if clearance == null or _clearance == null or clearance != _clearance.get_ref() or clearance.triangle_count != _triangle_count or _built_root == null or Contract.generated_root(world) != _built_root.get_ref() or not Contract.has_complete_clearance(world):
		status = "stale world; prepare again"
		return false
	if str(world.get("report").get("source_directory", "")) != _source_directory or not Contract.has_property(world, "roadworks"):
		status = "stale source; prepare again"
		return false
	var works: Variant = world.get("roadworks")
	if not works is Dictionary or works.get("waters") != _waters_snapshot:
		status = "stale water; prepare again"
		return false
	# Require finite terrain samples at all corners and center of the expanded footprint.
	var low := Vector2(bounds.position.x - MARGIN, bounds.position.z - MARGIN)
	var high := Vector2(bounds.end.x + MARGIN, bounds.end.z + MARGIN)
	for point in [low, Vector2(low.x, high.y), Vector2(high.x, low.y), high, (low + high) * 0.5]:
		var height: Variant = world.call("get_surface_height_at", point.x, point.y)
		if not (height is float or height is int) or not is_finite(float(height)):
			return false
	# Reject all deck columns rather than only the vehicle-height clearance slab.
	var column := AABB(Vector3(bounds.position.x, -10000.0, bounds.position.z), Vector3(bounds.size.x, 20000.0, bounds.size.z))
	if clearance.call("overlaps", column, MARGIN, true):
		return false
	# Water geometry is the union of 4m cells in the actual rendered data.
	var x0 := floori((bounds.position.x - MARGIN - ORIGIN) / GRID - 0.000001)
	var z0 := floori((bounds.position.z - MARGIN - ORIGIN) / GRID - 0.000001)
	var x1 := floori((bounds.end.x + MARGIN - ORIGIN) / GRID)
	var z1 := floori((bounds.end.z + MARGIN - ORIGIN) / GRID)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if _water.has(Vector2i(x, z)):
				return false
	# A finite sample alone does not imply contact. Require the transformed
	# AABB to straddle the terrain at its horizontal center (with small tolerance).
	# This is an eligibility check, not a mesh/surface intersection proof.
	var center := bounds.get_center()
	var ground: Variant = world.call("get_surface_height_at", center.x, center.z)
	if not (ground is float or ground is int) or not is_finite(float(ground)):
		return false
	return bounds.position.y <= float(ground) + CONTACT_TOLERANCE_M and bounds.end.y >= float(ground) - CONTACT_TOLERANCE_M
