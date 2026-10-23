extends SceneTree

## Gate 2 probe for Pac-Man movement (issue #2). Drives GridMover directly with
## fixed ticks - fully deterministic, no input timing, no rendering.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame

	var pac: Pacman = main.get_node("Pacman")
	pac.set_physics_process(false)
	var mover := pac.mover
	var failures: Array[String] = []

	print("spawn=", mover.cell, " body_y=", pac.get_node("Body").position.y)
	if mover.cell != MazeData.PAC_SPAWN:
		failures.append("spawn=%s" % str(mover.cell))

	# 1. Walk left along the spawn row until the outer wall stops us.
	pac.steer(Vector2i.LEFT)
	var wall_violations := 0
	var last := mover.cell
	var tiles := 0
	for i in 400:
		mover.tick(1.0 / 60.0)
		if not MazeData.is_walkable(mover.cell):
			wall_violations += 1
		if mover.cell != last:
			tiles += 1
			last = mover.cell
	print("walked_left_tiles=", tiles, " stopped_at=", mover.cell)
	if mover.cell != Vector2i(1, 23):
		failures.append("left_stop=%s" % str(mover.cell))
	if wall_violations > 0:
		failures.append("wall_violations=%d" % wall_violations)
	if pac.mover.dir != Vector2i.ZERO:
		failures.append("should_be_stopped")

	# 2. A wall directly ahead must not start movement at all.
	mover.place(Vector2i(13, 23))
	pac.steer(Vector2i.UP)
	for i in 60:
		mover.tick(1.0 / 60.0)
	print("blocked_up_cell=", mover.cell)
	if mover.cell != Vector2i(13, 23):
		failures.append("entered_wall_up=%s" % str(mover.cell))

	# 3. Tunnel wrap: (1,14) -> (0,14) -> (27,14) across the seam.
	mover.place(Vector2i(1, 14))
	mover.tiles_per_second = 6.0
	pac.steer(Vector2i.LEFT)
	var wrapped := false
	for i in 25:
		mover.tick(1.0 / 60.0)
		if mover.cell == Vector2i(27, 14):
			wrapped = true
	print("tunnel_wrap=", wrapped, " cell=", mover.cell)
	if not wrapped:
		failures.append("tunnel_wrap_failed")

	# 4. Mid-tile reversal is instant and position-continuous.
	mover.place(Vector2i(5, 23))
	mover.tiles_per_second = 7.0
	pac.steer(Vector2i.LEFT)
	for i in 6:
		mover.tick(1.0 / 60.0)
	var before := mover.progress
	pac.steer(Vector2i.RIGHT)
	print("reversal_progress_before=", before, " after=", mover.progress, " dir=", mover.dir)
	if mover.dir != Vector2i.RIGHT:
		failures.append("reversal_dir=%s" % str(mover.dir))
	if absf(mover.progress - (1.0 - before)) > 0.001:
		failures.append("reversal_progress")
	for i in 60:
		mover.tick(1.0 / 60.0)
	print("reversal_resumed_cell=", mover.cell)
	if mover.cell.x < 5:
		failures.append("reversal_did_not_resume=%s" % str(mover.cell))

	# 5. Pac-Man may not pass the ghost-house door.
	mover.place(MazeData.HOUSE_EXIT)
	pac.steer(Vector2i.DOWN)
	for i in 60:
		mover.tick(1.0 / 60.0)
	print("door_blocked_cell=", mover.cell)
	if mover.cell.y != MazeData.HOUSE_EXIT.y:
		failures.append("entered_ghost_house=%s" % str(mover.cell))

	# 6. Arrival signal fires with the entered tile.
	mover.place(Vector2i(5, 23))
	var arrivals: Array[Vector2i] = []
	mover.arrived.connect(func(cell: Vector2i) -> void: arrivals.append(cell))
	pac.steer(Vector2i.RIGHT)
	for i in 60:
		mover.tick(1.0 / 60.0)
	print("arrivals=", arrivals.size(), " first=", arrivals[0] if not arrivals.is_empty() else "none")
	if arrivals.is_empty() or arrivals[0] != Vector2i(6, 23):
		failures.append("arrival_signal")

	# 7. Mouth mesh: with a 90-degree gap, no vertex may sit inside the wedge
	# (gap centered on local +X), and the yaw must map that gap onto travel.
	var mesh := PacMesh.build(1.0, 90.0)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var in_wedge := 0
	for v in verts:
		if absf(v.y) > 0.99:
			continue  # poles have no defined phi
		var phi := atan2(v.z, v.x)
		if absf(phi) < deg_to_rad(44.0):
			in_wedge += 1
	print("mouth_gap_vertices_in_wedge=", in_wedge)
	if in_wedge != 0:
		failures.append("mouth_wedge_geometry")

	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		mover.dir = d
		pac._face_travel()
		var mouth := Basis(Vector3.UP, pac.body.rotation.y) * Vector3.RIGHT
		if not mouth.is_equal_approx(Vector3(d.x, 0.0, d.y)):
			failures.append("mouth_yaw_dir=%s got=%s" % [str(d), str(mouth)])
	print("mouth_yaw_check=done")

	print("failures=", failures)
	quit(0 if failures.is_empty() else 1)
