class_name BenchmarkRunner
extends Node

## Automated reproducible GPU benchmark and screenshot capture harness.
## Triggered via CLI args: -- --benchmark --preset=Balanced --out=... --screenshots=...

const WARMUP_FRAMES: int = 36
const MEASURE_FRAMES: int = 120
const FLYTHROUGH_FRAMES: int = 180

var active: bool = false
var target_preset_name: String = "Balanced"
var out_json_path: String = ""
var screenshots_dir: String = ""

var _rig: CameraRig
var _presets: GraphicsPresets
var _env: Environment
var _sun: DirectionalLight3D
var _grass_mmi: MultiMeshInstance3D
var _hud: CanvasLayer

var _stage: String = "init"
var _vp_idx: int = 0
var _frame_counter: int = 0

var _frame_ms_samples: Array[float] = []
var _cpu_ms_samples: Array[float] = []
var _gpu_ms_samples: Array[float] = []
var _draw_calls_samples: Array[float] = []
var _primitives_samples: Array[float] = []
var _objects_samples: Array[float] = []

var _results: Dictionary = {}
var _last_usec: int = 0


func parse_cli_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--benchmark":
			active = true
		elif a.begins_with("--preset="):
			target_preset_name = a.substr("--preset=".length())
		elif a.begins_with("--out="):
			out_json_path = a.substr("--out=".length())
		elif a.begins_with("--screenshots="):
			screenshots_dir = a.substr("--screenshots=".length())
	return active


func start(
	rig: CameraRig,
	presets: GraphicsPresets,
	env: Environment,
	sun: DirectionalLight3D,
	grass_mmi: MultiMeshInstance3D,
	hud: CanvasLayer
) -> void:
	_rig = rig
	_presets = presets
	_env = env
	_sun = sun
	_grass_mmi = grass_mmi
	_hud = hud

	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	var tier: int = _presets.parse_tier_name(target_preset_name)
	_presets.apply_tier(tier, _env, _sun, get_viewport(), _grass_mmi)
	_presets.apply_time_of_day(GraphicsPresets.TimeOfDay.GOLDEN_HOUR, _env, _sun)

	if _hud != null:
		_hud.visible = false

	if screenshots_dir != "":
		DirAccess.make_dir_recursive_absolute(screenshots_dir)

	var vp_size: Vector2i = get_viewport().get_visible_rect().size
	_results = {
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"renderer_adapter": RenderingServer.get_video_adapter_name(),
		"renderer_vendor": RenderingServer.get_video_adapter_vendor(),
		"renderer_api": RenderingServer.get_video_adapter_api_version(),
		"preset": GraphicsPresets.TIER_NAMES[tier],
		"preset_state": _presets.state.duplicate(true),
		"resolution": "%dx%d" % [vp_size.x, vp_size.y],
		"warmup_frames": WARMUP_FRAMES,
		"measure_frames": MEASURE_FRAMES,
		"flythrough_frames": FLYTHROUGH_FRAMES,
		"viewpoints": [],
		"flythrough": {},
		"screenshots": [],
	}

	_vp_idx = 0
	_rig.select_viewpoint(0)
	_stage = "vp_warmup"
	_frame_counter = 0
	_last_usec = Time.get_ticks_usec()
	print("[BENCHMARK] Starting tier=%s at %dx%d on %s" % [
		GraphicsPresets.TIER_NAMES[tier], vp_size.x, vp_size.y, RenderingServer.get_video_adapter_name()
	])


func _clear_samples() -> void:
	_frame_ms_samples.clear()
	_cpu_ms_samples.clear()
	_gpu_ms_samples.clear()
	_draw_calls_samples.clear()
	_primitives_samples.clear()
	_objects_samples.clear()


func _record_frame_sample() -> void:
	var now_usec: int = Time.get_ticks_usec()
	var dt_ms: float = float(now_usec - _last_usec) / 1000.0
	_last_usec = now_usec
	if dt_ms <= 0.01:
		return

	var vp_rid: RID = get_viewport().get_viewport_rid()
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)

	_frame_ms_samples.append(dt_ms)
	_cpu_ms_samples.append(cpu_ms)
	_gpu_ms_samples.append(gpu_ms)
	_draw_calls_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_primitives_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_objects_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))


func _summarize_samples() -> Dictionary:
	var n: int = _frame_ms_samples.size()
	if n == 0:
		return {}

	var sorted_dt: Array[float] = _frame_ms_samples.duplicate()
	sorted_dt.sort()

	var sum_dt: float = 0.0
	var sum_cpu: float = 0.0
	var sum_gpu: float = 0.0
	var sum_dc: float = 0.0
	var sum_prim: float = 0.0
	var sum_obj: float = 0.0

	for i in range(n):
		sum_dt += _frame_ms_samples[i]
		sum_cpu += _cpu_ms_samples[i]
		sum_gpu += _gpu_ms_samples[i]
		sum_dc += _draw_calls_samples[i]
		sum_prim += _primitives_samples[i]
		sum_obj += _objects_samples[i]

	var avg_dt: float = sum_dt / float(n)
	var avg_fps: float = 1000.0 / maxf(avg_dt, 0.001)
	var p99_idx: int = clampi(int(floor(float(n) * 0.99)), 0, n - 1)
	var p99_dt: float = sorted_dt[p99_idx]
	var low1_fps: float = 1000.0 / maxf(p99_dt, 0.001)
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)

	return {
		"frames": n,
		"avg_fps": snappedf(avg_fps, 0.1),
		"low_1pct_fps": snappedf(low1_fps, 0.1),
		"avg_frame_ms": snappedf(avg_dt, 0.01),
		"p99_frame_ms": snappedf(p99_dt, 0.01),
		"avg_render_cpu_ms": snappedf(sum_cpu / float(n), 0.01),
		"avg_render_gpu_ms": snappedf(sum_gpu / float(n), 0.01),
		"avg_draw_calls": int(round(sum_dc / float(n))),
		"avg_primitives": int(round(sum_prim / float(n))),
		"avg_objects": int(round(sum_obj / float(n))),
		"video_mem_mb": snappedf(vram_mb, 0.1),
	}


func _capture_screenshot(filename: String) -> void:
	if screenshots_dir == "":
		return
	var img: Image = get_viewport().get_texture().get_image()
	var full_path: String = screenshots_dir.path_join(filename)
	var err: Error = img.save_png(full_path)
	if err == OK:
		_results["screenshots"].append(filename)
		print("[BENCHMARK] Saved screenshot: %s" % full_path)
	else:
		push_error("[BENCHMARK] Failed to save screenshot %s (err=%d)" % [full_path, err])


func _process(_delta: float) -> void:
	if not active:
		return

	match _stage:
		"vp_warmup":
			_frame_counter += 1
			if _frame_counter >= WARMUP_FRAMES:
				_clear_samples()
				_frame_counter = 0
				_last_usec = Time.get_ticks_usec()
				_stage = "vp_measure"

		"vp_measure":
			_record_frame_sample()
			_frame_counter += 1
			if _frame_counter >= MEASURE_FRAMES:
				var vp_info: Dictionary = _rig.viewpoints[_vp_idx]
				var stats: Dictionary = _summarize_samples()
				stats["id"] = vp_info["id"]
				stats["label"] = vp_info["label"]
				var pos: Vector3 = vp_info["position"]
				var tgt: Vector3 = vp_info["target"]
				stats["camera_pos"] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]
				stats["camera_target"] = [snappedf(tgt.x, 0.01), snappedf(tgt.y, 0.01), snappedf(tgt.z, 0.01)]
				_results["viewpoints"].append(stats)

				var tier_slug: String = _results["preset"].to_lower()
				_capture_screenshot("%s_%s.png" % [tier_slug, vp_info["id"].to_lower()])
				print("[BENCHMARK] %s -> %.1f FPS (1%% low %.1f, GPU %.2f ms, CPU %.2f ms, DC %d)" % [
					vp_info["id"], stats["avg_fps"], stats["low_1pct_fps"],
					stats["avg_render_gpu_ms"], stats["avg_render_cpu_ms"], stats["avg_draw_calls"]
				])

				_vp_idx += 1
				if _vp_idx < _rig.viewpoints.size():
					_rig.select_viewpoint(_vp_idx)
					_frame_counter = 0
					_stage = "vp_warmup"
				else:
					_rig.start_flythrough()
					_frame_counter = 0
					_stage = "fly_warmup"

		"fly_warmup":
			_rig.set_flythrough_progress(0.0)
			_frame_counter += 1
			if _frame_counter >= 20:
				_clear_samples()
				_frame_counter = 0
				_last_usec = Time.get_ticks_usec()
				_stage = "fly_measure"

		"fly_measure":
			var prog: float = float(_frame_counter) / float(FLYTHROUGH_FRAMES)
			_rig.set_flythrough_progress(prog)
			_record_frame_sample()

			_frame_counter += 1
			if _frame_counter >= FLYTHROUGH_FRAMES:
				var fly_stats: Dictionary = _summarize_samples()
				fly_stats["id"] = "FLYTHROUGH"
				fly_stats["label"] = "Repeatable Road-to-Lake Flythrough"
				_results["flythrough"] = fly_stats
				print("[BENCHMARK] FLYTHROUGH -> %.1f FPS (1%% low %.1f, GPU %.2f ms, CPU %.2f ms)" % [
					fly_stats["avg_fps"], fly_stats["low_1pct_fps"],
					fly_stats["avg_render_gpu_ms"], fly_stats["avg_render_cpu_ms"]
				])
				# Seek cleanly to mid-flythrough for screenshot AFTER measurement finishes
				_rig.set_flythrough_progress(0.45)
				_frame_counter = 0
				_stage = "fly_capture"

		"fly_capture":
			_frame_counter += 1
			if _frame_counter >= 4:
				var tier_slug: String = _results["preset"].to_lower()
				_capture_screenshot("%s_flythrough_mid.png" % tier_slug)
				_finish_and_quit()


func _finish_and_quit() -> void:
	if out_json_path != "":
		var parent_dir: String = out_json_path.get_base_dir()
		if parent_dir != "":
			DirAccess.make_dir_recursive_absolute(parent_dir)
		var f := FileAccess.open(out_json_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_results, "  "))
			f.close()
			print("[BENCHMARK] Wrote JSON report: %s" % out_json_path)
		else:
			push_error("[BENCHMARK] Could not open JSON output path: %s" % out_json_path)
	active = false
	get_tree().quit(0)
