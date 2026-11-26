extends Node3D
## Synthetic, non-production 100m patch with real triangle clearance and material bindings.
const Clearance := preload("res://modules/world_runtime/src/road_clearance.gd")
const MATERIAL := preload("res://assets/forza_env/materials/terrain_triplanar_pbr.tres")
var generated_root: Node3D
var road_clearance: Clearance
var metadata_override: Variant = null
# Mock build report for this isolated fixture, not a real full-map claim.
var report := {"source_directory": "res://data/world", "full_world": true}
var roadworks := {"waters": [{"height": 30.0, "cells": [[253, 253]]}]}
var ground: MeshInstance3D
var road: MeshInstance3D
var collision: CollisionShape3D

func get_world_metadata() -> Variant:
	if metadata_override != null:
		return metadata_override
	return {"coordinate_system": "godot_y_up", "bounds": {"min_x": -1000, "max_x": 1000, "min_z": -1000, "max_z": 1000}}

func get_surface_height_at(x: float, z: float) -> float:
	return 30.0 if absf(x) <= 50.0 and absf(z) <= 50.0 else NAN

func build_fixture() -> void:
	if is_instance_valid(generated_root):
		generated_root.free()
	generated_root = Node3D.new()
	add_child(generated_root)
	var terrain := Node3D.new()
	terrain.name = "TerrainChunks"
	generated_root.add_child(terrain)
	ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100.0, 100.0)
	plane.material = MATERIAL
	ground.mesh = plane
	ground.position.y = 30.0
	terrain.add_child(ground)
	var body := StaticBody3D.new()
	terrain.add_child(body)
	collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	collision.shape = shape
	collision.position.y = 29.5
	body.add_child(collision)
	road = MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.12, 0.13, 0.14)
	var shoulder := StandardMaterial3D.new()
	shoulder.albedo_color = Color(0.28, 0.24, 0.18)
	_add_surface(mesh, _quad(-40.0, 40.0, -4.0, 4.0), asphalt)
	var shoulders := _quad(-40.0, 40.0, -6.0, -4.0)
	shoulders.append_array(_quad(-40.0, 40.0, 4.0, 6.0))
	_add_surface(mesh, shoulders, shoulder)
	road.mesh = mesh
	road.position.y = 30.08
	generated_root.add_child(road)
	road_clearance = Clearance.new()
	for surface in range(mesh.get_surface_count()):
		road_clearance.add_surface(mesh, surface, road.global_transform)
	# Elevated extra deck for verifying the column exclusion.
	var bridge := MeshInstance3D.new()
	var bridge_mesh := ArrayMesh.new()
	_add_surface(bridge_mesh, _quad(-3.0, 3.0, 15.0, 25.0), asphalt)
	bridge.mesh = bridge_mesh
	bridge.position.y = 38.0
	generated_root.add_child(bridge)
	road_clearance.add_surface(bridge_mesh, 0, bridge.global_transform)
	# A steep synthetic bank makes the isolated shader A/B meaningful for rock too.
	# This is fixture-only art, not a modification to the actual world.
	var bank := MeshInstance3D.new()
	var bank_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([Vector3(12, 30, -14), Vector3(12, 46, -28), Vector3(32, 30, -14),
		Vector3(32, 30, -14), Vector3(12, 46, -28), Vector3(32, 46, -28)])
	_add_surface(bank_mesh, vertices, MATERIAL, Vector3(0, 14, 16).normalized())
	bank.mesh = bank_mesh
	terrain.add_child(bank)

func _quad(x0: float, x1: float, z0: float, z1: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1),
		Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)])

func _add_surface(mesh: ArrayMesh, vertices: PackedVector3Array, material: Material, normal: Vector3 = Vector3.UP) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(normal)
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
