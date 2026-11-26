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
var removed_grass := {}
var legacy_grass := "unknown"
var route_hash := ""
var route_limits: Array[Vector2] = []
var route_lane_ids := PackedStringArray()
var interaction := false
var capture_conditions_changed := false

func _initialize() -> void:
	run.call_deferred()

func release_controls() -> void:
	for action in ["drive_left", "drive_right", "drive_throttle", "drive_brake", "drive_handbrake"]:
		if InputMap.has_action(action):
			Input.action_release(action)

func finish(code: int, reason: String) -> void:
	release_controls()
	if physics_frame.is_connected(route_controls):
		physics_frame.disconnect(route_controls)
	restore_grass()
	if is_instance_valid(cover):
		cover.call("shutdown")
		cover.queue_free()
	for i in range(previews.size()-1, -1, -1):
		var preview: Object = previews[i]
		preview.call("restore")
		if preview is Node:
			preview.queue_free()
		elif not preview is RefCounted:
			preview.free()
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

func suppress_grass() -> bool:
	# Test-session-only adapter for the pinned live ValleyVegetation. Never
	# disable trees, flowers, rocks, leaf effects, or authored scenery.
	var plant: Node=drive.get("vegetation")
	if not is_instance_valid(plant):
		return false
	var ground: Variant=plant.get("_ground")
	var visible_ground: Variant=plant.get("_visible_ground")
	if not ground is Dictionary or not visible_ground is Dictionary:
		return false
	for key: Variant in ground.keys():
		if not key is Vector3i:
			return false
	for key: Vector3i in ground.keys():
		if key.z==2:
			removed_grass[key]=ground[key]
			ground.erase(key)
			if visible_ground.has(key):
				var batch: Node3D=visible_ground[key]
				batch.hide()
				batch.queue_free()
				visible_ground.erase(key)
	if removed_grass.is_empty():
		return false
	plant.set("_ground_center",Vector2i(99999,99999))
	legacy_grass="disabled"
	return true

func restore_grass() -> void:
	if removed_grass.is_empty() or not is_instance_valid(drive):
		return
	var plant: Node=drive.get("vegetation")
	if is_instance_valid(plant):
		var ground: Dictionary=plant.get("_ground")
		for key: Variant in removed_grass:
			ground[key]=removed_grass[key]
		plant.set("_ground_center",Vector2i(99999,99999))
	removed_grass.clear()

func grass_state() -> String:
	var plant: Node=drive.get("vegetation")
	if not is_instance_valid(plant):
		return "unknown"
	var ground: Variant=plant.get("_ground")
	if not ground is Dictionary:
		return "unknown"
	for key: Variant in ground:
		if key is Vector3i and key.z==2:
			return "enabled"
	return "disabled" if not removed_grass.is_empty() else "unknown"

func number_option(key: String, default_value: float) -> float:
	var value:=str(opts.get(key,str(default_value)))
	return float(value) if value.is_valid_float() else NAN

func convert_rectangles(options: Dictionary) -> bool:
	for key: String in ["pilot_bounds","roadside_bounds"]:
		if not options.has(key):
			continue
		var value: Variant=options[key]
		if not value is Array or value.size()!=4:
			return false
		for n: Variant in value:
			if not (n is int or n is float) or not is_finite(float(n)):
				return false
		var rect:=Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
		if not rect.has_area() or not Rect2(-1000,-1000,2000,2000).encloses(rect):
			return false
		options[key]=rect
	return true

func select_paint() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for node: MeshInstance3D in drive.vehicle_body.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or node.material_override!=null:
			continue
		for surface in node.mesh.get_surface_count():
			var material:=node.get_active_material(surface) as ShaderMaterial
			if material!=null and material.shader!=null and material.shader.resource_path=="res://shaders/car_paint.gdshader":
				result.append({"mesh":node,"surface":surface})
	return result

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

func audio_state() -> String:
	if not is_instance_valid(drive) or not is_instance_valid(drive.vehicle_body):
		return "unverified_or_muted"
	return "enabled" if drive.vehicle_body.has_node("VehicleAudio") and not AudioServer.is_bus_mute(0) and AudioServer.get_bus_volume_db(0)>-80.0 else "unverified_or_muted"

func grass_count() -> String:
	if not is_instance_valid(cover):
		return ""
	var count := 0
	for node: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
		if node.multimesh != null:
			count += node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
	return str(count)

func make_route(site: Vector3, heading: Vector3, duration: float) -> Variant:
	var best:=INF
	var chosen: Dictionary={}
	var chosen_i:=0
	var lanes: Dictionary={}
	for lane: Dictionary in drive.world.get_road_graph()["lanes"]:
		lanes[str(lane["id"])]=lane
		if not str(lane["id"]).begins_with("lane_"):
			continue
		var points: Array=lane["points"]
		for i in range(1,points.size()-2):
			var p:=Vector3(points[i][0],points[i][1],points[i][2])
			var q:=Vector3(points[i+1][0],points[i+1][1],points[i+1][2])
			var direction:=q-p
			direction.y=0
			if direction.normalized().dot(heading.normalized())<0.3:
				continue
			var distance:=Vector2(p.x-site.x,p.z-site.z).length()
			if distance<best:
				var pose: Variant=drive.call("_road_pose",p,direction)
				if pose!=null:
					best=distance
					chosen=lane
					chosen_i=i
	if chosen.is_empty() or best>200:
		return null
	var start: Array=chosen["points"][chosen_i]
	var next: Array=chosen["points"][chosen_i+1]
	var pose: Variant=drive.call("_road_pose",Vector3(start[0],start[1],start[2]),Vector3(next[0]-start[0],0,next[2]-start[2]))
	if pose==null:
		return null
	var length:=0.0
	var last:=Vector3.INF
	# Deterministic successor chain, no teleport. Extend beyond requested sample
	# at nominal speed where possible; enforce connected endpoints and avoid loops.
	for step in 32:
		var id:=str(chosen["id"])
		route_lane_ids.append(id)
		var points: Array=chosen["points"]
		for i in range(chosen_i,points.size()):
			var raw: Array=points[i]
			var p:=Vector3(raw[0],0,raw[2])
			if not p.is_finite():
				return null
			if last.is_finite():
				var distance:=last.distance_to(p)
				if distance<0.02:
					continue
				if distance>20:
					return null
				length+=distance
			route.add_point(p)
			last=p
			route_limits.append(Vector2(length,float(chosen.get("speed_limit_kph",30))/3.6))
		if length>=duration*target_speed+100:
			break
		var successors: Array=chosen.get("next_lane_ids",[]).duplicate()
		successors.sort()
		var successor: Dictionary={}
		for raw_id: Variant in successors:
			var next_id:=str(raw_id)
			if not lanes.has(next_id) or next_id in route_lane_ids:
				continue
			var candidate: Dictionary=lanes[next_id]
			var pts: Array=candidate["points"]
			if pts.size()<2:
				continue
			var first:=Vector3(pts[0][0],0,pts[0][2])
			if last.distance_to(first)<=12:
				successor=candidate
				break
		if successor.is_empty():
			break
		chosen=successor
		chosen_i=0
	if route.point_count<2 or length<100:
		return null
	var encoded:=PackedStringArray()
	for i in route.point_count:
		encoded.append(str(route.get_point_position(i)))
	route_hash=("\n".join(encoded)+"|"+";".join(route_lane_ids)).sha256_text()
	return pose

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
	var desired:=target_speed
	# Respect route geometry and upcoming speed limits. Scripted high-speed
	# targets are never a license to blast through a hairpin or junction.
	for sample: Vector2 in route_limits:
		if sample.x>=route_progress and sample.x<=route_progress+maxf(25.0,speed*2.0):
			desired=minf(desired,sample.y)
	var ahead:=minf(end,route_progress+maxf(12.0,speed*1.2))
	var a:=route.sample_baked(route_progress)
	var b:=route.sample_baked((route_progress+ahead)*0.5)
	var c:=route.sample_baked(ahead)
	var turn:=absf((b-a).signed_angle_to(c-b,Vector3.UP))
	if turn>0.02:
		desired=minf(desired,sqrt(3.5*maxf(a.distance_to(c),1.0)/turn))
	var error := minf(desired,sqrt(maxf(0.0,2.0*3.0*(end-route_progress))))-speed
	Input.action_press("drive_throttle",clampf(0.20+error*0.24,0.0,1.0))
	Input.action_press("drive_brake",clampf((-error-1.2)*0.24,0.0,0.72))

func metric(value: float) -> String:
	return str(value) if is_finite(value) and value > 0.0 else ""

func run() -> void:
	if OS.get_cmdline_user_args()==PackedStringArray(["--self-test"]):
		await self_test()
		return
	if DisplayServer.get_name() == "headless":
		await finish(1,"Graphical renderer required; no capture written")
		return
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=",true,1)
		if parts.size()!=2 or opts.has(parts[0]) or not parts[0] in ["--out","--site","--mode","--scenario","--preset","--features","--warmup","--scale","--seconds","--speed-mps","--commit","--options","--interaction"]:
			await finish(1,"Unknown, repeated, or malformed capture argument: "+arg)
			return
		opts[parts[0]]=parts[1]
	out = str(opts.get("--out",""))
	var site := str(opts.get("--site","cedar"))
	var mode := str(opts.get("--mode","baseline"))
	var scenario := str(opts.get("--scenario","stationary"))
	var quality := str(opts.get("--preset","medium"))
	var features := str(opts.get("--features",""))
	var warmup := number_option("--warmup",15.0)
	var expected_scale := number_option("--scale",0.85 if quality=="low" else 1.0)
	var duration := number_option("--seconds",60.0)
	target_speed = number_option("--speed-mps",22.35)
	interaction=str(opts.get("--interaction","off"))=="on"
	for n in [warmup,expected_scale,duration,target_speed]:
		if not is_finite(n):
			await finish(1,"Nonfinite or malformed numeric option")
			return
	if out.is_empty() or not out.is_absolute_path() or not VIEWS.has(site) or not mode in ["baseline","candidate"] or not scenario in ["stationary","offroad","manual","route"] or not quality in ["low","medium","high"] or warmup<5 or warmup>120 or expected_scale<=0 or expected_scale>1.0 or duration<60 or duration>600 or target_speed<=0 or target_speed>60.8 or str(opts.get("--commit","")).length()!=40 or not str(opts.get("--interaction","off")) in ["on","off"]:
		await finish(1,"Invalid capture options; see handoff")
		return
	if FileAccess.file_exists(out.path_join("meta.json")) or FileAccess.file_exists(out.path_join("frames.csv")) or FileAccess.file_exists(out.path_join("start.png")) or FileAccess.file_exists(out.path_join("end.png")):
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
		pose = make_route(spec[0],spec[1],duration)
	if pose==null:
		await finish(1,"No validated road pose")
		return
	if scenario=="offroad":
		var found := false
		for distance in [12.0,18.0,24.0,32.0,45.0,60.0]:
			for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				var p: Vector3 = pose.origin+direction*distance
				p.y = drive.world.get_surface_height_at(p.x,p.z)+0.58
				if p.is_finite() and absf(p.x)<990 and absf(p.z)<990 and not drive.world.road_clearance.overlaps(AABB(p-Vector3(2,1,2),Vector3(4,4,4)),1.0,true):
					var hit: Dictionary=drive.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*5,p-Vector3.UP*5,1))
					if hit.is_empty() or not hit.collider.is_in_group("Grass") or hit.normal.dot(Vector3.UP)<0.92:
						continue
					var heading: Vector3=-pose.basis.z
					pose=Transform3D(Basis.looking_at(heading.slide(hit.normal),hit.normal),hit.position+hit.normal*0.58)
					found=true
					break
			if found:
				break
		if not found:
			await finish(1,"No offroad clearance")
			return
	drive._spawn_vehicle("mclaren_senna",pose)
	for tick in 90:
		await physics_frame
	if drive.active_vehicle_id!="mclaren_senna" or not drive.vehicle_body.has_node("CuratedCar"):
		await finish(1,"Actual curated Senna failed to mount")
		return
	var contacts:=0
	for wheel in drive.vehicle_body.wheel_array:
		if wheel.is_colliding() and (scenario!="offroad" or wheel.get_collider().is_in_group("Grass")):
			contacts+=1
	if contacts!=4 or not drive.vehicle_body.global_transform.is_finite() or drive.vehicle_body.global_basis.y.dot(Vector3.UP)<0.9:
		await finish(1,"Senna failed settled four-wheel contact")
		return
	drive.camera.snap_to_vehicle()
	drive.vehicle_body.freeze=true
	legacy_grass=grass_state()
	if mode=="baseline" and (not features.is_empty() or not feature_options.is_empty()):
		await finish(1,"Baseline must not enable experimental features")
		return
	if mode=="candidate":
		if features.is_empty():
			await finish(1,"Explicit --features=a,d,e selection required")
			return
		var enabled := {}
		for key: Variant in feature_options:
			if not key in features.split(",",true):
				await finish(1,"Options supplied for disabled feature: "+str(key))
				return
		for feature in features.split(",",true):
			if enabled.has(feature):
				await finish(1,"Duplicate feature: "+feature)
				return
			enabled[feature]=true
			var options: Dictionary=feature_options.get(feature,{}).duplicate(true)
			if not convert_rectangles(options):
				await finish(1,"Invalid world-space bounds for "+feature)
				return
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
								ok=bool(cover.call("build",drive.world,quality,MASK,options))
								if ok:
									ok=suppress_grass()
				"d":
					if not options.has("pilot_bounds"):
						var center: Vector2=Vector2(pose.origin.x,pose.origin.z)
						options["pilot_bounds"]=Rect2(center-Vector2.ONE*100,Vector2.ONE*200).intersection(Rect2(-1000,-1000,2000,2000))
					if not options.has("roadside_bounds"):
						options["roadside_bounds"]=options["pilot_bounds"]
					if not options.has("mask_dir"):
						options["mask_dir"]=MASK
					ok=apply_preview("res://modules/environment_terrain/terrain_preview.gd",drive.world,false,quality,options)
				"e":
					var paint:=select_paint()
					if paint.is_empty():
						await finish(1,"Verified Senna paint surfaces unavailable")
						return
					options["paint_surfaces"]=paint
					ok=apply_preview("res://modules/environment_rendering/render_profile.gd",drive,true,quality,options)
			if not ok:
				await finish(1,"Candidate feature refused: "+feature)
				return
	rid=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var warm_start:=Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-warm_start)/1e6<warmup:
		await process_frame
		if is_instance_valid(cover):
			cover.call("update_focus",drive.camera.global_position,drive.vehicle_body.linear_velocity)
	release_controls()
	var start_pose: Transform3D=drive.vehicle_body.global_transform
	if root.size!=Vector2i(1920,1080) or not is_equal_approx(root.scaling_3d_scale,expected_scale) or RenderingServer.get_current_rendering_method()!="forward_plus":
		await finish(1,"1920x1080 output and requested scale required")
		return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if image.get_size()!=Vector2i(1920,1080) or image.save_png(out.path_join("start.png"))!=OK:
		await finish(1,"Real screenshot failed")
		return
	var driver_info: Variant = "unavailable"
	if RenderingServer.has_method("get_video_adapter_driver_info"):
		var info: Variant=RenderingServer.call("get_video_adapter_driver_info")
		if info is PackedStringArray or info is Array:
			if info.size()>0:
				driver_info=Array(info)
	meta={"mode":mode,"site":site,"scenario":scenario,"preset":quality,"width":root.size.x,"height":root.size.y,
		"scale":root.scaling_3d_scale,"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"driver":driver_info,
		"commit":opts["--commit"],"car":"mclaren_senna","fov":drive.camera.fov,
		"pose":str(pose),"actual_start_pose":str(start_pose),"camera_pose":str(drive.camera.global_transform),
		"camera_start_position":[drive.camera.global_position.x,drive.camera.global_position.y,drive.camera.global_position.z],
		"camera_start_forward":[-drive.camera.global_basis.z.x,-drive.camera.global_basis.z.y,-drive.camera.global_basis.z.z],
		"traffic":str(drive.get_meta("environment_qa_traffic_state","unverified")),
		"audio":audio_state(),
		"warmup_s":warmup,"sample_s":duration,"controls":str(scenario)+":"+str(target_speed),"lighting":"scene default; candidate flags recorded",
		"vsync":"disabled","max_fps":Engine.max_fps,"features":features,"feature_options":feature_options,"legacy_vegetation_visible":drive.vegetation!=null and drive.vegetation.visible,
		"scene":"res://scenes/bootstrap/game.tscn","route_length_m":route.get_baked_length(),"route_hash":route_hash,"route_lanes":Array(route_lane_ids),"interaction":interaction,"legacy_grass":grass_state(),"complete":false}
	if scenario in ["manual","route"]:
		drive.vehicle_body.freeze=false
	if scenario=="route":
		physics_frame.connect(route_controls)
	print("CAPTURE START ", JSON.stringify(meta), " — manual: drive now")
	var start:=Time.get_ticks_usec()
	var prev:=start
	var count_cache:=grass_count()
	var next_count:=start+1000000
	var expected_car: Node=drive.vehicle_body
	var initial_traffic:=str(meta["traffic"])
	var initial_audio:=str(meta["audio"])
	while float(prev-start)/1e6<duration:
		await process_frame
		var now:=Time.get_ticks_usec()
		if is_instance_valid(cover):
			cover.call("update_focus",drive.camera.global_position,drive.vehicle_body.linear_velocity)
			cover.call("set_vehicle_interaction",drive.vehicle_body.global_position,drive.vehicle_body.linear_velocity,interaction)
		if now>=next_count:
			count_cache=grass_count()
			if grass_state()!=legacy_grass or str(drive.get_meta("environment_qa_traffic_state","unverified"))!=initial_traffic or audio_state()!=initial_audio:
				capture_conditions_changed=true
			next_count=now+1000000
		if root.size!=Vector2i(1920,1080) or not is_equal_approx(root.scaling_3d_scale,expected_scale) or drive.active_vehicle_id!="mclaren_senna" or paused or drive.vehicle_body!=expected_car or drive.graphics_preset!=quality or Engine.max_fps!=0 or DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED:
			capture_conditions_changed=true
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
	if physics_frame.is_connected(route_controls):
		physics_frame.disconnect(route_controls)
	if grass_state()!=legacy_grass or str(drive.get_meta("environment_qa_traffic_state","unverified"))!=initial_traffic or audio_state()!=initial_audio:
		capture_conditions_changed=true
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
	meta["complete"]=photo_ok and not capture_conditions_changed
	meta["capture_conditions_changed"]=capture_conditions_changed
	meta["route_done"]=route_done
	meta["route_departed"]=route_departed
	meta["grass_stats"]=cover.call("get_stats") if is_instance_valid(cover) else {}
	file=FileAccess.open(out.path_join("meta.json"),FileAccess.WRITE)
	if file==null:
		await finish(1,"Metadata output failed")
		return
	file.store_string(JSON.stringify(meta,"\t"))
	file.close()
	await finish(0 if meta["complete"] else 1,"Capture complete; no graphical acceptance implied" if meta["complete"] else "Screenshot or capture conditions failed")


func self_test() -> void:
	# Headless test of actual capture prerequisites, NOT a benchmark or image.
	if DisplayServer.get_name()!="headless":
		await finish(1,"Self-test must be headless")
		return
	var errors:=0
	var bounds: Dictionary={"pilot_bounds":[-10,-10,20,20]}
	if not convert_rectangles(bounds) or not bounds["pilot_bounds"] is Rect2:
		errors+=1
	for bad in [{"pilot_bounds":[0,0,0,5]},{"roadside_bounds":[999,999,2,2]},{"pilot_bounds":[0,0,"x",1]}]:
		if convert_rectangles(bad):
			errors+=1
	profile="user://capture-self-test-%d.json" % Time.get_ticks_usec()
	game=GAME.instantiate()
	var shell=game.get_node("GameShell")
	shell.save_path=profile
	root.add_child(game)
	shell.enter_free_roam()
	for tick in 900:
		await physics_frame
		drive=shell.drive
		if is_instance_valid(drive) and drive.vehicle_body!=null:
			break
	if not is_instance_valid(drive) or drive.vehicle_body==null:
		await finish(1,"Self-test world failed")
		return
	var plant: Node=drive.vegetation
	var before: Dictionary=plant.get("_ground").duplicate()
	if grass_state()!="enabled" or not suppress_grass() or grass_state()!="disabled":
		errors+=1
	else:
		var current: Dictionary=plant.get("_ground")
		for key: Variant in before:
			if (key.z==2 and current.has(key)) or (key.z!=2 and current.get(key)!=before[key]):
				errors+=1
		restore_grass()
		if plant.get("_ground")!=before or grass_state()!="enabled":
			errors+=1
	# Exercise all actual production spawn positions and the linked road route.
	for site: String in VIEWS:
		var spec: Array=VIEWS[site]
		var pose: Variant=drive.find_road_pose(spec[0],spec[1])
		if pose==null:
			print("FAIL capture pose ",site)
			errors+=1
			continue
		drive._spawn_vehicle("mclaren_senna",pose)
		for tick in 90:
			await physics_frame
		var contacts:=0
		for wheel in drive.vehicle_body.wheel_array:
			contacts+=int(wheel.is_colliding())
		if contacts!=4 or drive.active_vehicle_id!="mclaren_senna" or not drive.vehicle_body.has_node("CuratedCar"):
			print("FAIL Senna capture prerequisites ",site," contacts=",contacts)
			errors+=1
		else:
			print("PASS Senna capture prerequisites ",site)
		route.clear_points()
		route_lane_ids.clear()
		route_limits.clear()
		route_hash=""
		var route_pose: Variant=make_route(spec[0],spec[1],60.0)
		if route_pose==null or route.point_count<2 or route_hash.length()!=64 or route.get_baked_length()<100:
			print("FAIL connected route ",site)
			errors+=1
		else:
			print("PASS connected route ",site," length=",route.get_baked_length()," lanes=",route_lane_ids.size())
	print("CAPTURE SELF TEST failures=",errors)
	await finish(1 if errors else 0,"Capture fixture failed" if errors else "Capture fixture passed; no graphical output")
