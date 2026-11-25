extends SceneTree
## Real graphical capture, never a headless benchmark. See handoff for CLI.
const GAME := preload("res://scenes/bootstrap/game.tscn")
const VIEWS := {
	"alder": [Vector3(-575,0,545), Vector3.RIGHT],
	"cedar": [Vector3(-870,0,-154), Vector3(1,0,-1)],
	"ridge": [Vector3(549,0,-779), Vector3(1,0,1)],
	"valley": [Vector3(72,0,170), Vector3.RIGHT],
	"eastwater": [Vector3(630,0,495), Vector3(1,0,-1)]
}
const COVER := "res://modules/ground_cover/ground_cover.gd"
const MASK := "res://content/scenery/environment_overhaul/masks"
var opts := {}
var out := ""
var profile := ""
var game: Node
var drive: Node
var cover: Node3D
var previews: Array[Object] = []
var rid: RID
var route := Curve3D.new()
var route_done := false
var route_departed := false
var feature_options := {}
var target_speed := 22.35
var route_progress := 0.0
var meta := {}
var rows: Array[PackedStringArray] = []

func _initialize() -> void:
	run.call_deferred()

func release_controls() -> void:
	for action in ["drive_left", "drive_right", "drive_throttle", "drive_brake", "drive_handbrake"]:
		if InputMap.has_action(action):
			Input.action_release(action)

func finish(code: int, reason: String) -> void:
	release_controls()
	if is_instance_valid(cover):
		cover.call("shutdown")
		cover.queue_free()
	for i in range(previews.size()-1, -1, -1):
		var preview: Object = previews[i]
		preview.call("restore")
		if preview is Node:
			preview.queue_free()
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for suffix in ["", ".tmp", ".bak", ".backup"]:
		if not profile.is_empty() and FileAccess.file_exists(profile + suffix):
			DirAccess.remove_absolute(profile + suffix)
	if code != 0:
		push_error(reason)
	else:
		print(reason)
	quit(code)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func string_vec(p: Vector3) -> Array:
	return [p.x,p.y,p.z]

func apply_preview(path: String, target: Node, render: bool, quality: String, options: Dictionary) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var script := load(path) as Script
	if script == null:
		return false
	var obj: Object = script.new()
	if obj is Node:
		root.add_child(obj)
	previews.append(obj)
	if render:
		return bool(obj.call("apply_candidate", target, quality, options))
	return bool(obj.call("apply_candidate", target, options))

func grass_count() -> String:
	if not is_instance_valid(cover):
		return ""
	var count := 0
	for node: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
		if node.multimesh != null:
			count += node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
	return str(count)

func make_route(site: Vector3, heading: Vector3) -> Variant:
	var best := INF
	var selected := PackedVector3Array()
	for lane: Dictionary in drive.world.get_road_graph()["lanes"]:
		var points: Array = lane["points"]
		for i in range(points.size()-2):
			var p := Vector3(points[i][0], points[i][1], points[i][2])
			var next := Vector3(points[i+1][0], points[i+1][1], points[i+1][2])
			var direction := next - p
			direction.y = 0
			if direction.normalized().dot(heading.normalized()) < 0.3:
				continue
			var distance := Vector2(p.x-site.x,p.z-site.z).length()
			if distance >= best:
				continue
			var tail := PackedVector3Array()
			var length := 0.0
			for j in range(i, points.size()):
				var q := Vector3(points[j][0],0,points[j][2])
				if not tail.is_empty():
					length += tail[-1].distance_to(q)
				tail.append(q)
			if length < 100.0:
				continue
			best = distance
			selected = tail
	if selected.size() < 2 or best > 200.0:
		return null
	for p in selected:
		route.add_point(p)
	return drive.find_road_pose(selected[0], selected[1]-selected[0])

func route_controls() -> void:
	var body: Node3D = drive.vehicle_body
	var p := body.global_position
	p.y = 0
	route_progress = route.get_closest_offset(p)
	var speed: float = maxf(drive.adapter.get_forward_speed_mps(), 0.0)
	var end := route.get_baked_length()
	if route_progress >= end-3.0:
		route_done = true
	if p.distance_to(route.sample_baked(route_progress)) > 5.0:
		route_departed = true
	if route_done or route_departed:
		route_done = true
		release_controls()
		Input.action_press("drive_brake", 1.0)
		return
	var target := route.sample_baked(minf(route_progress+3.2+speed*0.34,end))
	var forward := -body.global_basis.z
	forward.y = 0
	var aim := target-p
	var yaw := forward.signed_angle_to(aim, Vector3.UP)
	var angle := atan2(2.71*2.0*sin(yaw),maxf(aim.length(),1.0))
	var steer := clampf(signf(angle)*pow(absf(angle)/float(body.get("max_steering_angle")),1.0/float(body.get("steering_exponent")))*1.16,-1.0,1.0)
	Input.action_release("drive_left")
	Input.action_release("drive_right")
	if absf(steer)>0.005:
		Input.action_press("drive_left" if steer>0 else "drive_right",absf(steer))
	var error := minf(target_speed,sqrt(maxf(0.0,2.0*3.0*(end-route_progress))))-speed
	Input.action_press("drive_throttle",clampf(0.20+error*0.24,0.0,1.0))
	Input.action_press("drive_brake",clampf((-error-1.2)*0.24,0.0,0.72))

func metric(value: float) -> String:
	return str(value) if is_finite(value) and value > 0.0 else ""

func run() -> void:
	if DisplayServer.get_name() == "headless":
		await finish(1,"Graphical renderer required; no capture written")
		return
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=",false,1)
		if parts.size()==2:
			opts[parts[0]]=parts[1]
	out = str(opts.get("--out",""))
	var site := str(opts.get("--site","cedar"))
	var mode := str(opts.get("--mode","baseline"))
	var scenario := str(opts.get("--scenario","stationary"))
	var quality := str(opts.get("--preset","medium"))
	var features := str(opts.get("--features",""))
	var warmup := float(opts.get("--warmup","15"))
	var expected_scale := float(opts.get("--scale","0.85" if quality=="low" else "1.0"))
	var duration := float(opts.get("--seconds","60"))
	target_speed = float(opts.get("--speed-mps","22.35"))
	if out.is_empty() or not out.is_absolute_path() or not VIEWS.has(site) or not mode in ["baseline","candidate"] or not scenario in ["stationary","offroad","manual","route"] or not quality in ["low","medium","high"] or warmup<5 or duration<60 or duration>600 or target_speed<=0 or target_speed>60.8 or str(opts.get("--commit","")).is_empty():
		await finish(1,"Invalid capture options; see handoff")
		return
	if FileAccess.file_exists(out.path_join("meta.json")) or FileAccess.file_exists(out.path_join("frames.csv")):
		await finish(1,"Refusing to overwrite capture")
		return
	if DirAccess.make_dir_recursive_absolute(out)!=OK:
		await finish(1,"Cannot create capture directory")
		return
	if opts.has("--options"):
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(str(opts["--options"])))
		if not parsed is Dictionary:
			await finish(1,"Feature options must be a JSON object")
			return
		feature_options=parsed
		for key: Variant in feature_options:
			if not key in ["a","d","e"] or not feature_options[key] is Dictionary:
				await finish(1,"Invalid feature options key")
				return
	profile = out.path_join("qa-profile-%d.json" % Time.get_ticks_usec())
	game = GAME.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = profile
	root.add_child(game)
	await frames(20)
	if not PlayerCarFactory.PRESETS.has("mclaren_senna"):
		await finish(1,"Senna preset missing")
		return
	shell.open_garage()
	shell._inspect("mclaren_senna")
	await frames(30)
	shell.enter_free_roam()
	for i in 900:
		await process_frame
		drive = shell.drive
		if drive != null and drive.vehicle_body != null:
			break
	if not is_instance_valid(drive) or drive.vehicle_body == null:
		await finish(1,"Live drive failed")
		return
	shell._save_option("resolution","1920x1080")
	shell._save_option("window_mode","windowed")
	if not shell._save_option("graphics_quality",quality):
		await finish(1,"Preset refused")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var spec: Array = VIEWS[site]
	var pose: Variant = drive.find_road_pose(spec[0],spec[1])
	if scenario=="route":
		pose = make_route(spec[0],spec[1])
	if pose==null:
		await finish(1,"No validated road pose")
		return
	if scenario=="offroad":
		var found := false
		for distance in [12.0,18.0,24.0,32.0,45.0]:
			for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				var p: Vector3 = pose.origin+direction*distance
				p.y = drive.world.get_surface_height_at(p.x,p.z)+0.58
				if p.is_finite() and absf(p.x)<990 and absf(p.z)<990 and not drive.world.road_clearance.overlaps(AABB(p-Vector3(2,1,2),Vector3(4,4,4)),1.0,true):
					pose.origin=p
					found=true
					break
			if found:
				break
		if not found:
			await finish(1,"No offroad clearance")
			return
	drive._spawn_vehicle("mclaren_senna",pose)
	await frames(90)
	if drive.active_vehicle_id!="mclaren_senna" or not drive.vehicle_body.has_node("CuratedCar"):
		await finish(1,"Actual curated Senna failed to mount")
		return
	drive.camera.snap_to_vehicle()
	drive.vehicle_body.freeze=true
	if mode=="baseline" and not features.is_empty():
		await finish(1,"Baseline must not enable experimental features")
		return
	if mode=="candidate":
		if features.is_empty():
			await finish(1,"Explicit --features=a,d,e selection required")
			return
		var enabled := {}
		for feature in features.split(",",false):
			if enabled.has(feature):
				await finish(1,"Duplicate feature: "+feature)
				return
			enabled[feature]=true
			var options: Dictionary=feature_options.get(feature,{}).duplicate(true)
			var ok := false
			match feature:
				"a":
					if ResourceLoader.exists(COVER):
						var script := load(COVER) as Script
						if script!=null:
							cover=script.new() as Node3D
							if cover!=null:
								drive.add_child(cover)
								if not options.has("seed"):
									options["seed"]=1234
								if options.has("pilot_bounds"):
									var bounds: Variant=options["pilot_bounds"]
									if not bounds is Array or bounds.size()!=4:
										await finish(1,"pilot_bounds requires [x,z,width,height]")
										return
									options["pilot_bounds"]=Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3]))
								ok=bool(cover.call("build",drive.world,quality,MASK,options))
				"d":
					ok=apply_preview("res://modules/environment_terrain/terrain_preview.gd",drive.world,false,quality,options)
				"e":
					ok=apply_preview("res://modules/environment_rendering/render_profile.gd",drive,true,quality,options)
			if not ok:
				await finish(1,"Candidate feature refused: "+feature)
				return
	rid=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var start_pose: Transform3D=drive.vehicle_body.global_transform
	var warm_start:=Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-warm_start)/1e6<warmup:
		await process_frame
		if is_instance_valid(cover):
			cover.call("update_focus",drive.camera.global_position,drive.vehicle_body.linear_velocity)
	release_controls()
	if root.size!=Vector2i(1920,1080) or not is_equal_approx(root.scaling_3d_scale,expected_scale):
		await finish(1,"1920x1080 output and requested scale required")
		return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if image.get_size()!=Vector2i(1920,1080) or image.save_png(out.path_join("start.png"))!=OK:
		await finish(1,"Real screenshot failed")
		return
	var driver_info: Variant = "unavailable"
	if RenderingServer.has_method("get_video_adapter_driver_info"):
		driver_info=RenderingServer.call("get_video_adapter_driver_info")
	meta={"mode":mode,"site":site,"scenario":scenario,"preset":quality,"width":root.size.x,"height":root.size.y,
		"scale":root.scaling_3d_scale,"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"driver":driver_info,
		"commit":opts["--commit"],"car":"mclaren_senna","fov":drive.camera.fov,
		"pose":str(pose),"actual_start_pose":str(start_pose),"camera_pose":str(drive.camera.global_transform),
		"traffic":str(drive.get_meta("environment_qa_traffic_state","unverified")),
		"audio":"enabled" if drive.vehicle_body.has_node("VehicleAudio") and not AudioServer.is_bus_mute(0) and AudioServer.get_bus_volume_db(0)>-80.0 else "unverified_or_muted",
		"warmup_s":warmup,"sample_s":duration,"controls":str(scenario)+":"+str(target_speed),"lighting":"scene default; candidate flags recorded",
		"vsync":"disabled","max_fps":Engine.max_fps,"features":features,"feature_options":feature_options,"legacy_vegetation_visible":drive.vegetation!=null and drive.vegetation.visible,
		"scene":"res://scenes/bootstrap/game.tscn","route_length_m":route.get_baked_length(),"complete":false}
	if scenario in ["manual","route"]:
		drive.vehicle_body.freeze=false
	print("CAPTURE START ", JSON.stringify(meta), " — manual: drive now")
	var start:=Time.get_ticks_usec()
	var prev:=start
	var count_cache:=""
	var next_count:=start
	while float(prev-start)/1e6<duration:
		await process_frame
		var now:=Time.get_ticks_usec()
		if scenario=="route":
			route_controls()
		if is_instance_valid(cover):
			cover.call("update_focus",drive.camera.global_position,drive.vehicle_body.linear_velocity)
			cover.call("set_vehicle_interaction",drive.vehicle_body.global_position,drive.vehicle_body.linear_velocity,true)
		if now>=next_count:
			count_cache=grass_count()
			next_count=now+1000000
		var p: Vector3=drive.vehicle_body.global_position
		rows.append(PackedStringArray([str((now-start)/1e6),str((now-prev)/1000.0),
			metric(RenderingServer.viewport_get_measured_render_time_gpu(rid)),
			metric(RenderingServer.viewport_get_measured_render_time_cpu(rid)),
			metric(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0),
			str(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			str(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
			str(drive.adapter.get_speed_mps()),str(drive.adapter.get_gear_display()),str(p.x),str(p.y),str(p.z),
			str(drive.camera.fov),count_cache,str(route_progress),str(route_done)]))
		prev=now
	release_controls()
	await RenderingServer.frame_post_draw
	image=root.get_texture().get_image()
	var photo_ok:=image.get_size()==Vector2i(1920,1080) and image.save_png(out.path_join("end.png"))==OK
	var file:=FileAccess.open(out.path_join("frames.csv"),FileAccess.WRITE)
	if file==null:
		await finish(1,"CSV output failed")
		return
	file.store_csv_line(PackedStringArray(["elapsed_s","frame_ms","gpu_ms","cpu_ms","vram_mib","draws","triangles","speed_mps","gear","x","y","z","fov","grass_instances","route_progress_m","route_done"]))
	for row in rows:
		file.store_csv_line(row)
	file.close()
	meta["complete"]=photo_ok
	meta["route_done"]=route_done
	meta["route_departed"]=route_departed
	meta["grass_stats"]=cover.call("get_stats") if is_instance_valid(cover) else {}
	file=FileAccess.open(out.path_join("meta.json"),FileAccess.WRITE)
	if file==null:
		await finish(1,"Metadata output failed")
		return
	file.store_string(JSON.stringify(meta,"\t"))
	file.close()
	await finish(0 if photo_ok else 1,"Capture complete; no graphical acceptance implied" if photo_ok else "End screenshot failed")
