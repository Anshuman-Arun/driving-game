extends SceneTree
## On-screen Godot 4.7.2 Forward+ RAW capture; do not run --headless.
## From repo root: godot --path showcase/environment_hd --script res://capture_views.gd
## Each frame is saved directly from the renderer viewport; no artistic edits.
func _initialize() -> void:
    call_deferred("_capture_all")

func _capture_all() -> void:
    var packed := load("res://standalone.tscn") as PackedScene
    if packed == null:
        push_error("Needle Pass: standalone scene not found")
        quit(1)
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        push_error("Needle Pass: failed to instantiate scene")
        quit(1)
        return
    root.add_child(scene)
    await process_frame
    await process_frame
    if scene.get("_shots").size() != 6:
        push_error("Needle Pass: camera manifest unavailable")
        quit(1)
        return
    var output_dir := ProjectSettings.globalize_path("res://renders_godot")
    var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
    if directory_error != OK:
        push_error("Needle Pass: cannot create Godot capture directory")
        quit(1)
        return
    for index in range(6):
        scene.call("_select_view", index)
        await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        if image == null or image.is_empty():
            push_error("Needle Pass: renderer returned no image")
            quit(1)
            return
        image.flip_y()
        var output_path := output_dir.path_join("view_%02d.png" % [index + 1])
        if image.save_png(output_path) != OK:
            push_error("Needle Pass: failed to save " + output_path)
            quit(1)
            return
        print("Godot RAW capture: ", output_path)
    quit()
