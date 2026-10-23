extends SceneTree

## Gate 2 probe for the maze (issue #1). Structural invariants + BFS
## connectivity, all headless and deterministic.

func _initialize() -> void:
	var failures: Array[String] = []

	if MazeData.ROWS.size() != 31:
		failures.append("row_count=%d" % MazeData.ROWS.size())
	for r in MazeData.ROWS.size():
		var row: String = MazeData.ROWS[r]
		if row.length() != 28:
			failures.append("row_%d_width=%d" % [r, row.length()])
		elif row != row.reverse():
			failures.append("row_%d_not_palindrome" % r)

	var pellets := MazeData.pellet_cells()
	print("pellets=", pellets.size())
	if pellets.size() != 4:
		failures.append("pellets=%d" % pellets.size())
	print("dots=", MazeData.dot_cells().size())

	# Border sealed except the tunnel row; tunnel openings walkable on both ends.
	for col in 28:
		if MazeData.is_walkable(Vector2i(col, 0)) or MazeData.is_walkable(Vector2i(col, 30)):
			failures.append("border_row_open:%d" % col)
	for row in 31:
		if row == MazeData.TUNNEL_ROW:
			continue
		if MazeData.is_walkable(Vector2i(0, row)) or MazeData.is_walkable(Vector2i(27, row)):
			failures.append("border_col_open:%d" % row)
	if not MazeData.is_walkable(Vector2i(0, MazeData.TUNNEL_ROW)):
		failures.append("tunnel_left_closed")
	if not MazeData.is_walkable(Vector2i(27, MazeData.TUNNEL_ROW)):
		failures.append("tunnel_right_closed")

	# Wrap works across the tunnel.
	if MazeData.wrap(Vector2i(-1, MazeData.TUNNEL_ROW)) != Vector2i(27, MazeData.TUNNEL_ROW):
		failures.append("wrap_left")
	if MazeData.wrap(Vector2i(28, MazeData.TUNNEL_ROW)) != Vector2i(0, MazeData.TUNNEL_ROW):
		failures.append("wrap_right")

	# Every dot/pellet reachable from Pac-Man's spawn without using the door...
	var reachable := _bfs(MazeData.PAC_SPAWN, false)
	for cell in MazeData.dot_cells() + MazeData.pellet_cells():
		if not reachable.has(cell):
			failures.append("unreachable_food:%s" % str(cell))
	if not reachable.has(MazeData.HOUSE_EXIT):
		failures.append("house_exit_unreachable")
	if reachable.has(Vector2i(13, 13)):
		failures.append("pac_can_reach_ghost_house")

	# ...while ghosts with door access can reach the house interior.
	var ghost_reachable := _bfs(MazeData.PAC_SPAWN, true)
	if not ghost_reachable.has(Vector2i(13, 13)):
		failures.append("ghost_cannot_reach_house")

	print("reachable_food_check=done")
	print("failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _bfs(start: Vector2i, allow_door: bool) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := MazeData.wrap(cell + dir)
			if seen.has(next) or not MazeData.is_walkable(next, allow_door):
				continue
			seen[next] = true
			queue.append(next)
	return seen
