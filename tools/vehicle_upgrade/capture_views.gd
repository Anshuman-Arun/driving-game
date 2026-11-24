extends SceneTree
## Graphical QA capture. Only run with the full game project rooted at res://.
## Does not synthesize a hero model or pretend screenshots were captured.
##
## Godot 4.7.2 desktop (not --headless):
## godot --path . --script res://tools/vehicle_upgrade/capture_views.gd -- \
##   --out /absolute/path/to/qa_images
const HERO := "res://assets/vehicle_upgrade/vela_gt_hero.glb"
const ORIGINAL := "res://assets/curated/models/vehicles/vela_gt.glb"
const WHEEL_POS := {
	"FL": Vector3(-0.88, -0.08, -1.36),
	"FR": Vector3( 0.88, -0.08, -1.36),
	"RL": Vector3(-0.88, -0.08,  1.35),
	"RR": Vector3( 0.88, -0.08,  1.35),
}
const VIEWPOINTS := {
	"front_three_quarter": [Vector3(3.7, 1.8, -6.3), Vector3(0, 0.33, 0)],
	"rear_three_quarter": [Vector3(-3.7, 1.8, 6.3), Vector3(0, 0.33, 0)],
	"side_profile": [Vector3(6.7, 1.35, 0), Vector3(0, 0.33, 0)],
	"wheel_brake": [Vector3(-2.1, 0.28, -2.35), Vector3(-0.88, -0.05, -1.36)],
	"cockpit": [Vector3(-0.34, 1.06, 0.18), Vector3(-0.34, 0.85, -2.0)],
	"garage": [Vector3(4.8, 2.2, -7.4), Vector3(0, 0.35, 0)],
}
var _stage: Node3D
var _camera: Camera3D
var _out := ""

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var argv := OS.get_cmdline_user_args()
	_out = ProjectSettings.globalize_path("user://vehicle_upgrade_qa")
	for i: int in range(argv.size() - 1):
		if argv[i] == "--out":
			_out = argv[i + 1]
	if not ResourceLoader.exists(HERO) or not ResourceLoader.exists(ORIGINAL):
		push_error("Hero and curated fallback models must both exist; no false captures.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("Could not create image output directory: " + _out)
		quit(2)
		return
	var root_window := get_root()
	root_window.size = Vector2i(1920, 1080)
	_stage = Node3D.new()
	root_window.add_child(_stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.74, 0.83)
	env.ambient_light_energy = 0.8
	environment.environment = env
	_stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.rotation_degrees = Vector3(-50, -36, -15)
	_stage.add_child(sun)
	for position: Vector3 in [Vector3(-5, 6, -2), Vector3(5, 5, 3)]:
		var light := OmniLight3D.new()
		light.position = position
		light.light_energy = 1.8
		light.omni_range = 14.0
		_stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(32, 32)
	ground.mesh = plane
	ground.position.y = -0.43
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.09, 0.095, 0.10)
	asphalt.roughness = 0.89
	ground.material_override = asphalt
	_stage.add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 43.0
	_camera.current = true
	_stage.add_child(_camera)
	for model_path: String in [ORIGINAL, HERO]:
		var model_name := "original" if model_path == ORIGINAL else "hd"
		var packed := load(model_path) as PackedScene
		if packed == null:
			push_error("Cannot instantiate GLB: " + model_path)
			quit(2)
			return
		var car := packed.instantiate() as Node3D
		if car == null:
			push_error("GLB root is not Node3D: " + model_path)
			quit(2)
			return
		_stage.add_child(car)
		if model_name == "hd":
			for wheel_key: String in WHEEL_POS.keys():
				var pivot: Node3D = car.find_child("Wheel_" + wheel_key + "_Pivot", true, false) as Node3D
				var brake: Node3D = car.find_child("Brake_" + wheel_key, true, false) as Node3D
				if pivot == null or brake == null:
					push_error("Prepared wheel or brake hierarchy missing for " + wheel_key)
					quit(2)
					return
				pivot.position = WHEEL_POS[wheel_key]
				brake.position = WHEEL_POS[wheel_key]
		for angle: String in VIEWPOINTS.keys():
			var view: Array = VIEWPOINTS[angle]
			_camera.position = view[0]
			_camera.look_at(view[1])
			await process_frame
			await process_frame
			await process_frame
			var screenshot := root_window.get_texture().get_image()
			var filename := _out.path_join(model_name + "_" + angle + ".png")
			var result := screenshot.save_png(filename)
			if result != OK:
				push_error("Screenshot write failed: " + filename)
				quit(3)
				return
			print("CAPTURED (actual Godot viewport): ", filename)
		car.queue_free()
		await process_frame
	quit(0)
