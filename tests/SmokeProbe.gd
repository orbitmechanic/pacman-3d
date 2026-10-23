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
	for node_path in ["Camera3D", "DirectionalLight3D", "WorldEnvironment", "Floor", "UI/Title"]:
		if main.get_node_or_null(node_path) == null:
			failures.append(node_path)

	var cam := main.get_node_or_null("Camera3D") as Camera3D
	var floor_mi := main.get_node_or_null("Floor") as MeshInstance3D

	print("missing_nodes=", failures)
	print("camera_current=", cam != null and cam.current)
	print("floor_has_mesh=", floor_mi != null and floor_mi.mesh != null)

	var ok := failures.is_empty() and cam != null and cam.current and floor_mi != null and floor_mi.mesh != null
	quit(0 if ok else 1)
