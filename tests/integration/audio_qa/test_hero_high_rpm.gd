extends SceneTree
## Fixed RPM A/B: isolate grain cadence from vehicle RPM, gearshift and limiter.
const EngineScript := preload("res://modules/audio/recorded_runtime/engine/recorded_engine_controller.gd")
const Renderer := preload("res://modules/audio/recorded_runtime/engine/phase_grain_engine.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory := OS.get_environment("ASTER_AUDIO_CAPTURE_DIR")
	for id in ["aventador_svj","mclaren_senna"]:
		var engine := EngineScript.new()
		engine.setup(id)
		var extended: PhaseGrainEngine = engine._grain_engine
		assert(extended != null and extended.prepared)
		var short := Renderer.new()
		assert(short.prepare(engine._manifest.loops,engine._prepared_loops,extended.order,engine._idle_rpm,extended.idle_gain,id=="mclaren_senna",false))
		for label in ["short","extended"]:
			var renderer: PhaseGrainEngine = short if label=="short" else extended
			var capture: FileAccess = null
			if not directory.is_empty():
				DirAccess.make_dir_recursive_absolute(directory)
				capture = FileAccess.open(directory.path_join(id+"_high_rpm_"+label+".wav"),FileAccess.WRITE)
				assert(capture != null)
				_header(capture,Renderer.RATE*12)
			for target in [engine._redline_rpm*0.85,engine._redline_rpm]:
				for load in [1.0,0.0]:
					renderer.reset(engine._idle_rpm)
					for i in range(100):
						renderer.render_frames(320,target,load,0.8)
					var sum_sq := 0.0
					var peak := 0.0
					for i in range(300):
						var block := renderer.render_frames(320,target,load,0.8)
						assert(block.size()==320)
						var pcm := PackedByteArray()
						pcm.resize(640)
						for j in range(block.size()):
							var sample := block[j].x
							assert(is_finite(sample))
							sum_sq += sample*sample
							peak = maxf(peak,absf(sample))
							pcm.encode_s16(j*2,roundi(sample*32767.0))
						if capture != null:
							capture.store_buffer(pcm)
					assert(peak < 0.95 and sum_sq > 0.1)
					print("HERO HOLD %s %s rpm %.0f load %.1f rms %.4f peak %.4f" % [id,label,target,load,sqrt(sum_sq/96000.0),peak])
			if capture != null:
				capture.close()
		short.free()
		engine.free()
	print("High RPM steady-state A/B complete")
	quit(0)

func _header(file: FileAccess, frames: int) -> void:
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36+frames*2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(Renderer.RATE)
	file.store_32(Renderer.RATE*2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(frames*2)
