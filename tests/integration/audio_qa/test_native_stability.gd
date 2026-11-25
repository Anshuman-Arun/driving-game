extends SceneTree
const EngineControllerScript := preload("res://modules/audio/recorded_runtime/engine/recorded_engine_controller.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func _run() -> void:
	var id := OS.get_environment("ASTER_AUDIO_TEST_PROFILE")
	var engine := EngineControllerScript.new()
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
	# At exactly 3000 RPM a full 720-degree cycle lasts 40 ms = 1280
	# frames. Sample-level periodicity detects tonal modulation that the
	# earlier 250 ms aggregate RMS test could not detect.
	for load in [0.0,0.35,0.8]:
		renderer.reset(3000.0)
		renderer.cruise_target = 1.0
		renderer.render_frames(3200,3000.0,load,1.65)
		var block := renderer.render_frames(12800,3000.0,load,1.65)
		var difference := 0.0
		var energy := 0.0
		for i in range(1280,block.size()):
			var x := block[i].x
			var y := block[i-1280].x
			difference += (x-y)*(x-y)
			energy += x*x
		var error := sqrt(difference/maxf(energy,0.00000001))
		print("NATIVE CRUISE CYCLE ",id," load=",load," normalized_error=",error)
		check(energy > 0.1 and error < 0.002,"constant RPM waveform has no slow pitch/timbre cycle")
		check(renderer.clipped_frames == 0,"cruise no hard clipping")
	# Simulate physical motor flutter while the same gear stays coupled
	# to a constant road speed. Actual motor RPM remains visible in telemetry.
	engine.snap_to_idle()
	for i in range(180):
		engine.update_telemetry({"rpm":3500.0,"throttle":0.35,"gear":3,"speed_mps":22.0,"audio_locked_rpm":3450.0,"audio_coupled":true})
		engine._process(1.0/120.0)
	var pitch_low := INF
	var pitch_high := -INF
	for i in range(240):
		var flutter := 250.0*sin(TAU*2.0*float(i)/120.0)
		engine.update_telemetry({"rpm":3500.0+flutter,"throttle":0.35,"gear":3,"speed_mps":22.0,"audio_locked_rpm":3450.0,"audio_coupled":true})
		engine._process(1.0/120.0)
		pitch_low = minf(pitch_low,engine._smoothed_rpm)
		pitch_high = maxf(pitch_high,engine._smoothed_rpm)
	print("NATIVE COUPLED CRUISE ",id," pitch_span=",pitch_high-pitch_low)
	check(engine._cruise_weight > 0.95 and pitch_high-pitch_low < 70.0,"coupled road reference removes motor flutter")
	engine.update_telemetry({"rpm":2500.0,"throttle":0.6,"gear":4,"speed_mps":22.0,"audio_locked_rpm":2450.0,"audio_coupled":false,"shift_active":true,"requested_gear":5})
	for i in range(24):
		engine._process(1.0/120.0)
	check(engine._cruise_weight < 0.15 and engine._smoothed_rpm < 2700.0,"shift exits cruise and follows motor")
	engine.free()
	quit(0 if failures == 0 else 1)
