extends SceneTree
## Master runner for Aster Valley Recorded Audio QA Integration.
## Run with:
## godot --headless --script tests/integration/audio_qa/run_audio_qa.gd

func _initialize() -> void:
	print("\nStarting Aster Valley Audio QA Integration Suite...")
	var runner_script = load("res://modules/audio/recorded_runtime/qa/audio_capture_runner.gd")
	if not runner_script:
		push_error("Could not load AsterAudioCaptureRunner!")
		quit(1)
		return

	var runner = runner_script.new()
	var results: Dictionary = await runner.execute_suite(self, "res://tests/integration/audio_qa/results.json")
	var success: bool = bool(results.get("overall_success", false))

	if success:
		print("\n*** ALL AUDIO QA TESTS PASSED SUCCESSFULLY ***\n")
		quit(0)
	else:
		push_error("\n*** AUDIO QA TESTS FAILED ***\n")
		quit(1)
