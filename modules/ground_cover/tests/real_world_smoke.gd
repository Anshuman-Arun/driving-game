extends SceneTree
const Runtime = preload("res://modules/world_runtime/src/world_runtime.gd")
const Cover = preload("../ground_cover.gd")
const Grass = preload("../grass_mesh.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Runtime.new()
	world.build_on_ready = false
	world.generate_colliders = false
	world.preview_center_xz = Vector2(-620,560)
	root.add_child(world)
	if not world.build_world():
		printerr("FAIL real world build: ",world.error_message)
		quit(1)
		return
	var cover := Cover.new()
	root.add_child(cover)
	var p := world.preview_center_xz
	var options := {"test_fixture":true,"fixture_sampler":func(_x: float,_z: float) -> Vector4: return Vector4(1,0.2,0.5,0),"pilot_bounds":Rect2(p-Vector2.ONE*48,Vector2.ONE*96),"tuning":{"radii":[16,28,42],"density":[0.12,0.06,0.025],"cap":8000,"checks":800}}
	if not cover.build(world,"medium","",options):
		printerr("FAIL cover build: ",cover.get_stats())
		quit(1)
		return
	cover.set_process(false)
	cover.update_focus(Vector3(p.x,world.get_surface_height_at(p.x,p.y)+2,p.y))
	for i in range(300):
		cover._process(0.016)
		if cover.get_stats().queued_chunks == 0:
			break
	var stats: Dictionary = cover.get_stats()
	var failed: bool = stats.active_instances <= 0 or stats.queued_chunks != 0 or stats.active_instances > stats.cap
	for key: Vector2i in cover._active:
		for node: MultiMeshInstance3D in cover._active[key].nodes:
			var mm := node.multimesh
			for i in range(mm.instance_count):
				var frame := Transform3D(Basis.IDENTITY,node.position)*mm.get_instance_transform(i)
				if world.road_clearance.overlaps(Grass.swept_bounds(mm.mesh,frame),0.12,true):
					failed = true
	print("[GroundCoverRealWorld] ",JSON.stringify(stats))
	cover.shutdown()
	cover.free()
	world.free()
	if failed:
		printerr("FAIL real-world streaming or clearance")
	quit(1 if failed else 0)
