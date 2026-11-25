extends SceneTree
## Test-only local manifest fixture. No user or repository audio files are changed.
const Manifest := preload("res://modules/audio/recorded_runtime/engine/engine_profile_manifest.gd")

func _initialize() -> void:
	var folder := "user://native_engine_banks/aventador_svj"
	var absolute := ProjectSettings.globalize_path(folder)
	if DirAccess.dir_exists_absolute(absolute):
		printerr("Refusing to overwrite existing local audio bank")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		quit(1)
		return
	var data := FileAccess.get_file_as_bytes("res://assets/audio/recorded/payload/engines/aventador_svj/on_950.wav")
	var rows: Array[Dictionary] = []
	var success := not data.is_empty()
	for layer in ["on", "off"]:
		for rpm in range(1000, 8001, 1000):
			var filename := "%s_%d.wav" % [layer, rpm]
			var path := folder.path_join(filename)
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				success = false
				continue
			file.store_buffer(data)
			file.close()
			rows.append({"file": filename, "layer": layer, "rpm": rpm, "gain": 0.5, "sha256": FileAccess.get_sha256(path)})
	var manifest_path := folder.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		success = false
	else:
		manifest_file.store_string(JSON.stringify({"profile": "aventador_svj", "status": "local_source_native_audition", "loops": rows}))
		manifest_file.close()
	var accepted: RefCounted = Manifest.load_native_bank("aventador_svj")
	success = success and accepted != null
	if accepted != null:
		success = success and accepted.on_anchors.size() == 8 and accepted.off_anchors.size() == 8
		success = success and accepted.manifest_directory == folder
	accepted = null
	# One altered byte stream must reject the entire override.
	var corrupted := FileAccess.open(folder.path_join("on_1000.wav"), FileAccess.WRITE)
	if corrupted != null:
		corrupted.store_8(0)
		corrupted.close()
	else:
		success = false
	success = success and Manifest.load_native_bank("aventador_svj") == null
	for row in rows:
		DirAccess.remove_absolute(absolute.path_join(str(row["file"])))
	DirAccess.remove_absolute(absolute.path_join("manifest.json"))
	DirAccess.remove_absolute(absolute)
	print("Native local bank validation: ", "PASS" if success else "FAIL")
	quit(0 if success else 1)
