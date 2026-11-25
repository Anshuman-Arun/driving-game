extends RefCounted
## AudioServer mixes on its own clock. Tests must give stopped playback
## time to leave the mixer before destroying nodes and exiting the process.

static func stop_tree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_stop_players(node)

static func _stop_players(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_stop_players(child)

static func drain(tree: SceneTree) -> void:
	# Allow both main-thread playback updates and the audio mix thread to run.
	await tree.process_frame
	await tree.create_timer(0.15).timeout
	await tree.process_frame

static func dispose(tree: SceneTree, node: Node) -> void:
	stop_tree(node)
	await drain(tree)
	node.free()
	await drain(tree)
