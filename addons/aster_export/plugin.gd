@tool
extends EditorPlugin

class RuntimeScripts extends EditorExportPlugin:
	func _get_name() -> String:
		return "Aster Valley runtime scripts"

	func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		# Godot's resource scanner skips the separate module projects.
		for folder in ["res://modules/game_shell/scripts", "res://modules/world_runtime/src", "res://modules/scenery/src"]:
			for filename: String in DirAccess.get_files_at(folder):
				if filename.get_extension() not in ["gd", "gdshader", "gdshaderinc"]:
					continue
				var path: String = folder.path_join(filename)
				add_file(path, FileAccess.get_file_as_bytes(path), false)

		# Imported glTFs are remapped in PCKs, so preserve exact CC0 source bytes
		# at a separate non-resource path for the pilot's SHA/declaration checks.
		for species: String in ["fern", "shrub", "sapling", "reed", "wildflower"]:
			for lod in 2:
				var filename := "%s_lod%d.gltf" % [species, lod]
				var source := "res://assets/environment_overhaul/" + filename
				if FileAccess.file_exists(source):
					add_file("res://assets/environment_overhaul/source_bytes/" + filename + ".json", FileAccess.get_file_as_bytes(source), false)

var _runtime := RuntimeScripts.new()

func _enter_tree() -> void:
	add_export_plugin(_runtime)

func _exit_tree() -> void:
	remove_export_plugin(_runtime)
