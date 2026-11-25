extends SceneTree
const Engine := preload("res://modules/audio/recorded_runtime/engine/recorded_engine_controller.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func _run() -> void:
	var id := OS.get_environment("ASTER_AUDIO_TEST_PROFILE")
	var engine := Engine.new()
	engine.setup(id)
	var renderer: PhaseGrainEngine = engine._grain_engine
	if renderer == null or not engine._native_tuning:
		check(false,"native stable renderer required")
		engine.free()
		quit(1)
		return
	check(is_equal_approx(engine.torque_cut_depth,0.82),"gentle shift envelope")
	for row in renderer.rows:
		check(int(row.get("stable_take",-1)) >= 0 and float(row["calibrated_rms"]) > 0.001,"native anchor %d calibrated" % int(row["rpm"]))
	# Feed small alternating RPM error at fixed pedal, then a real gear drop.
	engine.update_telemetry({"rpm":3500.0,"throttle":0.35,"gear":3})
	for i in range(120):
		engine._process(1.0/120.0)
	var lo := INF
	var hi := -INF
	for i in range(120):
		engine.update_telemetry({"rpm":3500.0+(70.0 if i%2==0 else -70.0),"throttle":0.35,"gear":3})
		engine._process(1.0/120.0)
		lo = minf(lo,engine._smoothed_rpm)
		hi = maxf(hi,engine._smoothed_rpm)
	check(hi-lo < 25.0,"steady RPM flutter rejected")
	engine.update_telemetry({"rpm":3500.0,"throttle":0.0,"gear":3,"shift_active":true,"requested_gear":4})
	for i in range(20):
		engine._process(1.0/120.0)
	check(engine._shift_envelope >= 0.81 and engine._smoothed_throttle > 0.20,"shift retains exhaust instead of double-cut")
	engine.update_telemetry({"rpm":2400.0,"throttle":0.35,"gear":4})
	for i in range(24):
		engine._process(1.0/120.0)
	check(engine._smoothed_rpm < 2600.0,"real RPM drop remains responsive")
	# Actual native waveforms at constant RPM/part load: sustained signal,
	# bounded 250 ms energy variation and no hard sample clipping.
	for rpm in [2000.0,3500.0,5000.0,7000.0]:
		renderer.reset(rpm)
		renderer.render_frames(8000,rpm,0.35,1.65)
		var low := INF
		var high := 0.0
		for j in range(8):
			var block := renderer.render_frames(8000,rpm,0.35,1.65)
			var energy := 0.0
			for sample in block:
				energy += sample.x*sample.x
			var rms := sqrt(energy/float(block.size()))
			low = minf(low,rms)
			high = maxf(high,rms)
		print("NATIVE STEADY ",id," rpm=",rpm," rms_min=",low," rms_max=",high," ratio=",high/maxf(low,0.000001))
		check(low > 0.005 and high/low < 2.5,"steady level %d RPM" % int(rpm))
		check(renderer.clipped_frames == 0,"no hard clipping %d RPM" % int(rpm))
	engine.free()
	quit(0 if failures == 0 else 1)
