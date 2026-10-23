extends SceneTree

## Gate 2 smoke probe: the scaffold main scene loads, runs frames, and its
## essential 3D presentation nodes exist. Prints KEY=value facts; exit!=0 fails.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var failures: Array[String] = []
	for node_path in [
		"Camera3D", "DirectionalLight3D", "WorldEnvironment",
		"MazeView", "MazeView/Floor", "MazeView/Walls", "MazeView/Dots",
		"Pacman", "Ghosts", "Ghosts/Blinky", "Ghosts/Pinky",
		"Ghosts/Inky", "Ghosts/Clyde", "UI/Title", "UI/Score", "UI/Lives",
		"UI/Level", "UI/GameOver",
	]:
		if main.get_node_or_null(node_path) == null:
			failures.append(node_path)

	var cam := main.get_node_or_null("Camera3D") as Camera3D
	var walls := main.get_node_or_null("MazeView/Walls") as MultiMeshInstance3D

	print("missing_nodes=", failures)
	print("camera_current=", cam != null and cam.current)
	print("wall_instances=", walls.multimesh.instance_count if walls != null else -1)

	var ok := (
		failures.is_empty()
		and cam != null and cam.current
		and walls != null and walls.multimesh.instance_count > 150
	)
	quit(0 if ok else 1)
