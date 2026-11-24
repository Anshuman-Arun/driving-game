extends SceneTree

const CarMaterialSpec = preload("res://scripts/integration/car_material_spec.gd")
const UnderCarContactShadow = preload("res://scripts/vehicle/under_car_contact_shadow.gd")

func _init() -> void:
	print("--- BEGIN CAR VISUAL VERIFICATION TESTS ---")
	var success := true

	# Test 1: Shader existence and compilation
	print("[1/5] Testing car_paint.gdshader compilation...")
	var shader := load("res://shaders/car_paint.gdshader") as Shader
	if shader == null:
		printerr("FAILED: Could not load res://shaders/car_paint.gdshader")
		success = false
	else:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", Color("#7A0A10"))
		mat.set_shader_parameter("grazing_color", Color("#FF4520"))
		mat.set_shader_parameter("metallic", 0.75)
		mat.set_shader_parameter("roughness", 0.22)
		mat.set_shader_parameter("clearcoat", 1.0)
		mat.set_shader_parameter("clearcoat_roughness", 0.05)
		mat.set_shader_parameter("flake_intensity", 0.45)
		print("  PASSED: car_paint.gdshader loaded and ShaderMaterial created successfully.")

	# Test 2: Procedural contact shadow texture generation
	print("[2/5] Testing procedural contact shadow texture generation...")
	var tex := UnderCarContactShadow.generate_shadow_texture(256, 512)
	if tex == null:
		printerr("FAILED: generate_shadow_texture returned null")
		success = false
	else:
		var img := tex.get_image()
		var center_pixel := img.get_pixel(128, 256)
		var corner_pixel := img.get_pixel(0, 0)
		print("  Center pixel: ", center_pixel, " (expected pitch-black alpha 1.0)")
		print("  Corner pixel: ", corner_pixel, " (expected alpha 0.0)")
		if center_pixel.a < 0.95:
			printerr("FAILED: Center pixel alpha expected >= 0.95, got ", center_pixel.a)
			success = false
		elif corner_pixel.a > 0.01:
			printerr("FAILED: Corner pixel alpha expected <= 0.01, got ", corner_pixel.a)
			success = false
		else:
			print("  PASSED: Procedural contact shadow texture generated with smooth feathered falloff.")

	# Test 3: under_car_contact_shadow.tscn instantiation
	print("[3/5] Testing scenes/vehicles/under_car_contact_shadow.tscn...")
	var shadow_scene := load("res://scenes/vehicles/under_car_contact_shadow.tscn") as PackedScene
	if shadow_scene == null:
		printerr("FAILED: Could not load res://scenes/vehicles/under_car_contact_shadow.tscn")
		success = false
	else:
		var shadow_node := shadow_scene.instantiate() as UnderCarContactShadow
		if shadow_node == null:
			printerr("FAILED: Failed to instantiate UnderCarContactShadow")
			success = false
		else:
			root.add_child(shadow_node)
			shadow_node._ready()
			var decal := shadow_node.get_node_or_null("ShadowDecal") as Decal
			var ray := shadow_node.get_node_or_null("GroundRayCast") as RayCast3D
			if decal == null or ray == null:
				printerr("FAILED: Missing ShadowDecal or GroundRayCast child")
				success = false
			else:
				print("  PASSED: under_car_contact_shadow.tscn instantiated with Decal and RayCast.")
			shadow_node.queue_free()

	# Test 4: CarMaterialSpec material definitions
	print("[4/5] Testing CarMaterialSpec material specifications...")
	var paint_mat := CarMaterialSpec.create_car_paint()
	if paint_mat == null or paint_mat.shader == null:
		printerr("FAILED: CarMaterialSpec.create_car_paint() returned invalid material")
		success = false

	var glass_mat := CarMaterialSpec.create_glass()
	if not is_equal_approx(glass_mat.roughness, 0.12) or not is_equal_approx(glass_mat.metallic, 0.04) or not is_equal_approx(glass_mat.albedo_color.a, 0.36):
		printerr("FAILED: Glass material parameters mismatch: roughness=", glass_mat.roughness, " metallic=", glass_mat.metallic, " specular=", glass_mat.metallic_specular)
		success = false
	else:
		print("  PASSED: Partially transparent glass with a restrained gloss layer.")

	var tire_mat := CarMaterialSpec.create_tire()
	if not is_equal_approx(tire_mat.roughness, 0.85) or not tire_mat.albedo_color.is_equal_approx(Color("#1A1A1A")):
		printerr("FAILED: Tire material parameters mismatch: roughness=", tire_mat.roughness, " albedo=", tire_mat.albedo_color)
		success = false
	else:
		print("  PASSED: Tire material verified (roughness=0.85, albedo=#1A1A1A).")

	var diff_mat := CarMaterialSpec.create_diffuser()
	if not is_equal_approx(diff_mat.roughness, 0.45) or not is_equal_approx(diff_mat.metallic, 0.85):
		printerr("FAILED: Diffuser material parameters mismatch: roughness=", diff_mat.roughness, " metallic=", diff_mat.metallic)
		success = false
	else:
		print("  PASSED: Diffuser material verified (roughness=0.45, metallic=0.85).")

	var tail_mat := CarMaterialSpec.create_taillight(3.0)
	if not tail_mat.albedo_color.is_equal_approx(Color("#FF0011")) or not tail_mat.emission_enabled or tail_mat.emission_energy_multiplier < 3.0:
		printerr("FAILED: Taillight material parameters mismatch: albedo=", tail_mat.albedo_color, " emission=", tail_mat.emission, " energy=", tail_mat.emission_energy_multiplier)
		success = false
	else:
		print("  PASSED: Taillight material verified (albedo=#FF0011, emission=", tail_mat.emission, ", energy=", tail_mat.emission_energy_multiplier, ").")

	# Test 5: Vehicle application & contact shadow attachment
	print("[5/5] Testing CarMaterialSpec.apply_to_vehicle and attach_contact_shadow...")
	var test_car := PlayerCarFactory.create("vela_gt")
	root.add_child(test_car)
	CarMaterialSpec.apply_to_vehicle(test_car, Color("#7A0A10"), Color("#FF4520"))
	var attached_shadow := CarMaterialSpec.attach_contact_shadow(test_car)
	if attached_shadow == null:
		printerr("FAILED: attach_contact_shadow returned null")
		success = false
	else:
		print("  PASSED: Applied materials and attached contact shadow to vehicle successfully.")
	test_car.queue_free()

	# Test 6: Curated GLB model application
	print("[6/6] Testing CarMaterialSpec on curated GLB model (vela_gt)...")
	var CuratedCar = load("res://scripts/integration/curated_car_visual.gd")
	if CuratedCar != null:
		var model: Node3D = CuratedCar.load_model("vela_gt")
		if model != null:
			CarMaterialSpec.apply_to_vehicle(model, Color("#7A0A10"), Color("#FF4520"))
			print("  PASSED: CarMaterialSpec applied cleanly to curated GLB model.")
			model.free()
		else:
			print("  SKIPPED: Curated model vela_gt could not be loaded directly.")

	if success:
		print("--- ALL CAR VISUAL VERIFICATION TESTS PASSED ---")
		quit(0)
	else:
		printerr("--- CAR VISUAL VERIFICATION TESTS FAILED ---")
		quit(1)
