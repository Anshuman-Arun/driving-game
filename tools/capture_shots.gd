extends SceneTree
## Deterministic Godot CLI screenshot capture harness for Aster Valley.
## Renders 3 high-fidelity bookmarks (1920x1080 Forward+) with SSAO, SSR, and SDFGI convergence.
##
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path driving-game --script res://tools/capture_shots.gd

const SCENE_PATH := "res://scenes/free_roam/aster_valley.tscn"
const FORZA_CAM_SCRIPT := "res://scripts/vehicle/forza_chase_camera.gd"
const ENV_CONFIG_SCRIPT := "res://scripts/integration/environment_config.gd"
const CAR_SPEC_SCRIPT := "res://scripts/integration/car_material_spec.gd"
const RENDERS_DIR := "res://renders"

var _valley: Node3D
var _chase_cam: Camera3D
var _bookmark_cam: Camera3D
var _out_dir: String

func _initialize() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	print("==================================================")
	print("Starting Aster Valley Deterministic Screenshot Capture")
	print("==================================================")

	_out_dir = ProjectSettings.globalize_path(RENDERS_DIR)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		push_error("Failed to create output directory: " + _out_dir)
		quit(1)
		return

	var root_window := get_root()
	root_window.size = Vector2i(1920, 1080)
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

	if not ResourceLoader.exists(SCENE_PATH):
		push_error("Aster Valley scene not found at: " + SCENE_PATH)
		quit(1)
		return

	var packed := ResourceLoader.load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load PackedScene: " + SCENE_PATH)
		quit(1)
		return

	_valley = packed.instantiate() as Node3D
	if _valley == null:
		push_error("Failed to instantiate Aster Valley scene")
		quit(1)
		return

	# Enable rich scenery and high graphics preset before adding to tree
	if "scenery_enabled" in _valley:
		_valley.scenery_enabled = true
	if "graphics_preset" in _valley:
		_valley.graphics_preset = "high"

	root_window.add_child(_valley)

	# Await initialization of WorldRuntime, RoadWorks, and Vehicle spawn
	print("Waiting for world generation, collision registration, and vehicle spawning...")
	for frame in range(25):
		await process_frame

	var vehicle_body: RigidBody3D = null
	if "vehicle_body" in _valley and is_instance_valid(_valley.vehicle_body):
		vehicle_body = _valley.vehicle_body
	else:
		# Fallback node search
		vehicle_body = _valley.find_child("Vehicle", true, false) as RigidBody3D

	if vehicle_body == null:
		push_error("Vehicle was not spawned in Aster Valley")
		quit(1)
		return

	print("Vehicle confirmed at world position: ", vehicle_body.global_position)

	# Apply Ultra Environment Config if available from Worker 1
	if ResourceLoader.exists(ENV_CONFIG_SCRIPT):
		var env_script = ResourceLoader.load(ENV_CONFIG_SCRIPT)
		if env_script != null and env_script.has_method("apply_to_scene"):
			var world_env := _valley.get_node_or_null("WorldEnvironment") as WorldEnvironment
			var sun := _valley.get_node_or_null("Sun") as DirectionalLight3D
			env_script.apply_to_scene(world_env, sun, "ultra")
			print("Applied Ultra Environment Config from Worker 1")

	# Apply Car Material Spec if available from Worker 2
	if ResourceLoader.exists(CAR_SPEC_SCRIPT):
		var car_spec = ResourceLoader.load(CAR_SPEC_SCRIPT)
		if car_spec != null and car_spec.has_method("apply_to_vehicle"):
			car_spec.apply_to_vehicle(vehicle_body)
			print("Applied Car Material Spec from Worker 2")

	# Ensure scenery is enabled
	if _valley.has_method("set_scenery_enabled"):
		_valley.set_scenery_enabled(true)
		for frame in range(10):
			await process_frame

	# Setup Forza Chase Camera
	var forza_cam_class = ResourceLoader.load(FORZA_CAM_SCRIPT)
	if forza_cam_class != null:
		_chase_cam = forza_cam_class.new() as Camera3D
	else:
		_chase_cam = Camera3D.new()

	_chase_cam.name = "CaptureForzaChaseCamera"
	_valley.add_child(_chase_cam)
	if _chase_cam.has_method("setup"):
		_chase_cam.setup(vehicle_body)
	_chase_cam.current = true

	# Setup Beauty Bookmark Camera for custom angles
	_bookmark_cam = Camera3D.new()
	_bookmark_cam.name = "CaptureBookmarkCamera"
	_valley.add_child(_bookmark_cam)

	# ----------------------------------------------------
	# Bookmark 1: Behind car in third-person chase camera
	# ----------------------------------------------------
	print("\n[Bookmark 1/3] Capturing shot_1_chase.png...")
	_chase_cam.current = true
	if "mode" in _chase_cam:
		_chase_cam.mode = 0 # Forza Close Chase: 1.35m height, 4.2m distance
	if _chase_cam.has_method("snap_to_vehicle"):
		_chase_cam.snap_to_vehicle()

	await _converge_and_capture("shot_1_chase.png", 14)

	# ----------------------------------------------------
	# Bookmark 2: Low dramatic rear three-quarter angle
	# ----------------------------------------------------
	print("\n[Bookmark 2/3] Capturing shot_2_low_rear_angle.png...")
	_bookmark_cam.current = true
	var car_xform: Transform3D = vehicle_body.global_transform
	# Low rear 3/4 position: -2.4m left, 0.44m height, 3.5m back
	var local_cam_pos_2 := Vector3(-2.4, 0.44, 3.5)
	_bookmark_cam.global_position = car_xform * local_cam_pos_2
	var look_target_2 := car_xform * Vector3(0.0, 0.40, 1.2) # Focus on exhaust & diffuser
	_bookmark_cam.look_at(look_target_2, Vector3.UP)
	_bookmark_cam.fov = 40.0

	await _converge_and_capture("shot_2_low_rear_angle.png", 14)

	# ----------------------------------------------------
	# Bookmark 3: Elevated wide angle showing road & hills
	# ----------------------------------------------------
	print("\n[Bookmark 3/3] Capturing shot_3_wide_road_hills.png...")
	_bookmark_cam.current = true
	# Elevated position: -14m left, 9.2m height, 21m back
	var local_cam_pos_3 := Vector3(-14.0, 9.2, 21.0)
	_bookmark_cam.global_position = car_xform * local_cam_pos_3
	var look_target_3 := car_xform * Vector3(0.0, 0.8, -32.0) # Look forward down road ribbon
	_bookmark_cam.look_at(look_target_3, Vector3.UP)
	_bookmark_cam.fov = 64.0

	await _converge_and_capture("shot_3_wide_road_hills.png", 14)

	print("\n==================================================")
	print("All 3 screenshot bookmarks captured successfully!")
	print("Output directory: ", _out_dir)
	print("==================================================")
	quit(0)

func _converge_and_capture(filename: String, convergence_frames: int) -> void:
	# Wait multiple rendered frames for SSAO, SSR, TAA, and SDFGI to converge
	for frame in range(convergence_frames):
		await process_frame

	var root_window := get_root()
	var texture := root_window.get_texture()
	if texture == null:
		push_error("Failed to obtain root viewport texture")
		return

	var image := texture.get_image()
	if image == null:
		push_error("Failed to get image from viewport texture")
		return

	var file_path := _out_dir.path_join(filename)
	var err := image.save_png(file_path)
	if err != OK:
		push_error("Failed to save image to " + file_path + " (Error code: " + str(err) + ")")
	else:
		print("Successfully wrote: " + file_path + " (" + str(image.get_width()) + "x" + str(image.get_height()) + ")")
