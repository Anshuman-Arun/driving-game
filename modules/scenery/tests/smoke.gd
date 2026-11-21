extends SceneTree
## Run after staging PR #3 / #7 art and headless import:
## godot --headless --path modules/scenery --script res://tests/smoke.gd
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	var scenery: Node3D = load("res://src/scenery_runtime.gd").new()
	host.add_child(scenery)
	scenery.set("build_on_ready", false)
	scenery.set("quality", 2)
	var content: String = ProjectSettings.globalize_path("res://").path_join("../../content/scenery").simplify_path()
	var world: String = ProjectSettings.globalize_path("res://.world_source")
	if not bool(scenery.call("build_scenery", null, content, world)):
		push_error("[ScenerySmoke] Build failed: " + str(scenery.get("error_message")))
		quit(1)
		return
	var report: Dictionary = scenery.get("report")
	var errors: Array[String] = []
	if int(report.get("regions", 0)) != 5:
		errors.append("Expected five region packs")
	if int(report.get("placements", 0)) != 2791:
		errors.append("Expected 2791 high-quality placements")
	if int(report.get("water_triangles", 0)) != 10286:
		errors.append("Expected 10286 heightfield-clipped lake triangles")
	if int(report.get("height_mismatches", -1)) != 0:
		errors.append("Placements differ from the canonical triangulated height")
	if not report.get("missing_assets", []).is_empty():
		errors.append("GLB or local landmark glTF assets failed to import")
	if int(report.get("mesh_component_batches", 0)) < 100:
		errors.append("No real MultiMesh batches built")
	if int(report.get("selective_colliders", 0)) < 100:
		errors.append("Selective landmark/roadside collision shapes missing")
	if errors.is_empty():
		print("[ScenerySmoke] PASS: ", JSON.stringify(report))
		quit(0)
	else:
		for problem in errors:
			push_error("[ScenerySmoke] " + problem)
		quit(1)
