extends SceneTree

func _init() -> void:
	print("--- Running Road PBR & Guardrail Verification ---")

	# 1. Verify Shader Loading
	print("1. Checking asphalt_road.gdshader...")
	var shader := ResourceLoader.load("res://shaders/asphalt_road.gdshader") as Shader
	if shader == null:
		push_error("FAILED to load res://shaders/asphalt_road.gdshader")
		quit(1)
		return
	print("  SUCCESS: asphalt_road.gdshader loaded cleanly.")

	# 2. Verify Material Loading & Parameters
	print("2. Checking road_asphalt_pbr.tres...")
	var mat := ResourceLoader.load("res://assets/forza_env/materials/road_asphalt_pbr.tres") as ShaderMaterial
	if mat == null:
		push_error("FAILED to load res://assets/forza_env/materials/road_asphalt_pbr.tres")
		quit(1)
		return
	print("  SUCCESS: road_asphalt_pbr.tres loaded cleanly.")
	print("  Shader parameter road_uv_width: ", mat.get_shader_parameter("road_uv_width"))
	print("  Shader parameter asphalt_tint: ", mat.get_shader_parameter("asphalt_tint"))
	print("  Shader parameter center_stripe_color: ", mat.get_shader_parameter("center_stripe_color"))
	print("  Shader parameter edge_stripe_color: ", mat.get_shader_parameter("edge_stripe_color"))
	print("  Shader parameter verge_dirt_color: ", mat.get_shader_parameter("verge_dirt_color"))
	print("  Shader parameter roughness bounds: [", mat.get_shader_parameter("roughness_min"), ", ", mat.get_shader_parameter("roughness_max"), "]")

	# 3. Verify GuardrailSplineGenerator Loading & Functionality
	print("3. Checking guardrail_spline_generator.gd...")
	var GuardrailGen = load("res://modules/world_runtime/src/guardrail_spline_generator.gd")
	if GuardrailGen == null:
		push_error("FAILED to load res://modules/world_runtime/src/guardrail_spline_generator.gd")
		quit(1)
		return
	print("  SUCCESS: guardrail_spline_generator.gd script loaded.")

	# Test spline generation on dummy road corridor
	var root := Node3D.new()
	var test_centerline := PackedVector3Array([
		Vector3(0, 10, 0),
		Vector3(0, 10, -20),
		Vector3(5, 10, -40),
		Vector3(15, 10, -60),
		Vector3(30, 10, -80)
	])

	var gen: Node3D = GuardrailGen.generate_guardrails(root, test_centerline, 3.4, 1.35, null, {
		"placement_mode": "continuous",
		"side": "both",
		"colliders": true
	})

	if gen == null:
		push_error("FAILED to generate guardrails with GuardrailSplineGenerator")
		quit(1)
		return

	var child_count: int = gen.get_child_count()
	print("  SUCCESS: GuardrailSplineGenerator generated ", child_count, " children nodes.")
	for i in range(child_count):
		var child: Node = gen.get_child(i)
		print("    - Child: ", child.name, " (", child.get_class(), ")")

	# Verify parallel orientation math
	var stations: Array = gen.resample_corridor_spline(test_centerline, 2.0)
	print("  Generated ", stations.size(), " spline stations.")
	for i in range(mini(3, stations.size())):
		var st: Variant = stations[i]
		var dot_fwd_lat: float = st.forward.dot(st.lateral)
		print("    Station %d: pos=%s, fwd=%s, lat=%s, dot(fwd,lat)=%.4f" % [i, st.position, st.forward, st.lateral, dot_fwd_lat])
		if absf(dot_fwd_lat) > 0.001:
			push_error("Tangent and lateral are not orthogonal!")
			quit(1)
			return

	print("--- All Road PBR & Guardrail Verifications PASSED! ---")
	root.queue_free()
	quit(0)
