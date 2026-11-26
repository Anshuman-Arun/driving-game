extends Node3D
# Actual production triangle index, with a cross-junction, shoulders and elevated deck.
const Clearance = preload("res://modules/world_runtime/src/road_clearance.gd")
var road_clearance: Clearance = Clearance.new()
var bad_height := false
var steep := false

func _init() -> void:
	add_strip(Rect2(-3,-60,6,120),0.0,false)
	add_strip(Rect2(-5,-60,2,120),0.0,true)
	add_strip(Rect2(3,-60,2,120),0.0,true)
	add_strip(Rect2(-60,-3,120,6),0.0,false)
	add_strip(Rect2(15,-60,6,120),8.0,false)

func add_strip(rect: Rect2, y: float, shoulder: bool) -> void:
	var a := Vector3(rect.position.x,y,rect.position.y)
	var b := Vector3(rect.end.x,y,rect.position.y)
	var c := Vector3(rect.end.x,y,rect.end.y)
	var d := Vector3(rect.position.x,y,rect.end.y)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a,b,c,a,c,d])
	var mesh := ArrayMesh.new()
	if shoulder:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	road_clearance.add_surface(mesh,1 if shoulder else 0,Transform3D.IDENTITY)

func get_surface_height_at(x: float, z: float) -> float:
	if bad_height:
		return NAN
	return x * 1.2 if steep else 0.04*sin(x*0.13)*sin(z*0.13)

func sample_mask(x: float, z: float) -> Vector4:
	return Vector4(1.0, 0.7 if x < -15 else 0.1, 0.75 if z > 10 else 0.4, 1.0 if x > 30 and z > 30 else 0.0)
