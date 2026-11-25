extends SceneTree
## Real GEVP vehicle/adapter/telemetry integration, not scripted RPM input.
const Cleanup := preload("res://tests/integration/audio_qa/audio_test_cleanup.gd")
const BusBuilder := preload("res://modules/audio/recorded_runtime/mix/bus_layout_builder.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	BusBuilder.apply_to_audio_server(true)
	var bus := AudioServer.get_bus_index(&"Engine_Exhaust")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(bus, capture)
	var ground := StaticBody3D.new()
	ground.name = "Road"
	ground.collision_layer = 1
	ground.collision_mask = 2
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 2000.0)
	collider.shape = shape
	collider.position.y = -0.5
	ground.add_child(collider)
	root.add_child(ground)
	for id in ["aventador_svj", "mclaren_senna"]:
		await _drive(id, capture)
	ground.queue_free()
	await Cleanup.drain(self)
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == capture:
			AudioServer.remove_bus_effect(bus, i)
			break
	await Cleanup.drain(self)
	print("LIVE HERO AUDIO failures: ", failures)
	quit(0 if failures == 0 else 1)

func _drive(id: String, capture: AudioEffectCapture) -> void:
	var car: Vehicle = PlayerCarFactory.create(id)
	car.position = Vector3(0.0, 0.75, 400.0)
	root.add_child(car)
	var adapter := VehicleAdapter.new(car)
	var audio: AsterAudioController = car.get_node("VehicleAudio")
	var engine: RecordedEngineController = audio.recorded_engine
	var renderer: PhaseGrainEngine = engine._grain_engine
	_check(is_instance_valid(renderer) and renderer.prepared, id + " uses dedicated renderer")
	if not is_instance_valid(renderer):
		await Cleanup.dispose(self, car)
		return
	await create_timer(1.5).timeout
	_check(car.get_wheel_contact_count() == 4, id + " settles on road")
	var initial_skips := renderer.stream_skips()
	var initial_frames := renderer.generated_frames
	var discard_start := capture.get_discarded_frames()
	capture.clear_buffer()
	var previous_gear := car.current_gear
	var max_speed := 0.0
	var max_rpm := 0.0
	var on_count := 0
	var coast_count := 0
	var shift_count := 0
	var peak := 0.0
	var frames := 0
	var zero_run := 0
	var longest_zero := 0
	var max_rpm_error := 0.0
	var peak_rpm := 0.0
	var coast_rpm := INF
	var out_dir := OS.get_environment("ASTER_AUDIO_CAPTURE_DIR")
	var trace: FileAccess = null
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
		trace = FileAccess.open(out_dir.path_join(id + "_live_drive.csv"), FileAccess.WRITE)
		if trace != null:
			trace.store_line("time_s,rpm,target_rpm,smoothed_rpm,render_rpm,throttle,gear,speed_mps,shifting")
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 10000000:
		var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
		var throttle := 1.0 if elapsed < 6.0 else (0.0 if elapsed < 8.5 else 0.55)
		adapter.set_drive_input(0.0, throttle, 0.0, false)
		await physics_frame
		max_speed = maxf(max_speed, adapter.get_speed_mps())
		max_rpm = maxf(max_rpm, car.motor_rpm)
		max_rpm_error = maxf(max_rpm_error, absf(engine._target_rpm - maxf(100.0, car.motor_rpm)))
		if throttle > 0.9 and car.motor_rpm > car.idle_rpm + 500.0:
			on_count += 1
			peak_rpm = maxf(peak_rpm, car.motor_rpm)
		if elapsed > 6.2 and elapsed < 8.5:
			if float(audio._telemetry.get("engine_throttle", 1.0)) < 0.05:
				coast_count += 1
				coast_rpm = minf(coast_rpm, car.motor_rpm)
		if car.current_gear != previous_gear:
			shift_count += 1
			previous_gear = car.current_gear
		if trace != null:
			trace.store_line("%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.3f,%d" % [elapsed, car.motor_rpm, engine._target_rpm, engine._smoothed_rpm, renderer.rpm, throttle, car.current_gear, adapter.get_speed_mps(), int(car.is_shifting)])
		var n := capture.get_frames_available()
		if n > 0:
			var buffer := capture.get_buffer(n)
			frames += buffer.size()
			for sample in buffer:
				var amplitude := maxf(absf(sample.x), absf(sample.y))
				peak = maxf(peak, amplitude)
				if amplitude < 0.000015:
					zero_run += 1
					longest_zero = maxi(longest_zero, zero_run)
				else:
					zero_run = 0
	if trace != null:
		trace.close()
	adapter.set_drive_input(0.0, 0.0, 0.0, false)
	var skips := renderer.stream_skips() - initial_skips
	var gap_ms := 1000.0 * longest_zero / AudioServer.get_mix_rate()
	_check(max_speed > 12.0 and max_rpm > car.idle_rpm + 2000.0, id + " real acceleration")
	_check(on_count > 100 and coast_count > 60 and coast_rpm < peak_rpm, id + " actual pedal lift and falling RPM")
	_check(shift_count >= 2, id + " actual automatic gear changes")
	_check(max_rpm_error < 1500.0, id + " audio follows real motor RPM within a physics tick")
	_check(frames > AudioServer.get_mix_rate() * 9.0 and peak > 0.02 and peak < 0.95, id + " real exhaust signal and headroom")
	_check(skips == 0 and renderer.push_failures == 0 and capture.get_discarded_frames() == discard_start and gap_ms < 2.0, id + " continuous real-drive audio")
	print("LIVE HERO %s speed=%.2f max_rpm=%.1f coast_rpm=%.1f shifts=%d rpm_error=%.1f peak=%.4f frames=%d rendered=%d skips=%d max_gap_ms=%.3f" % [id,max_speed,max_rpm,coast_rpm,shift_count,max_rpm_error,peak,frames,renderer.generated_frames-initial_frames,skips,gap_ms])
	await Cleanup.dispose(self, car)
