extends SceneTree

## Gate 2 probe for eating/scoring (issue #3): drives Pac-Man across known
## tiles with fixed ticks and asserts exact score, HUD text, frightened timer,
## and the board-clear -> next-level loop.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame

	var pac: Pacman = main.get_node("Pacman")
	var game: Game = main.get_node("Game")
	var maze: MazeView = main.get_node("MazeView")
	var score_label: Label = main.get_node("UI/Score")
	var level_label: Label = main.get_node("UI/Level")
	pac.set_physics_process(false)
	game.set_process(false)
	var mover := pac.mover
	mover.tiles_per_second = 10.0
	var failures: Array[String] = []

	print("initial dots=", maze.dots_left, " pellets=", maze.pellets_left,
		" score=", game.score, " hud=", score_label.text)
	if maze.dots_left != 258 or maze.pellets_left != 4 or game.score != 0:
		failures.append("initial_food_state")
	if score_label.text != "SCORE 0":
		failures.append("initial_hud")

	# --- Dot on arrival, exactly once per tile ---------------------------
	mover.place(Vector2i(12, 23))
	pac.steer(Vector2i.LEFT)
	_tick_until_arrivals(mover, 1)
	print("after_dot score=", game.score, " dots=", maze.dots_left, " cell=", mover.cell)
	if game.score != 10 or maze.dots_left != 257 or mover.cell != Vector2i(11, 23):
		failures.append("first_dot")

	# Re-enter the already-eaten tile from a controlled position: no score.
	mover.place(Vector2i(12, 23))
	pac.steer(Vector2i.LEFT)
	_tick_until_arrivals(mover, 1)
	print("after_revisit score=", game.score, " dots=", maze.dots_left, " cell=", mover.cell)
	if game.score != 10 or maze.dots_left != 257 or mover.cell != Vector2i(11, 23):
		failures.append("double_score")

	# A fresh dot still scores.
	mover.place(Vector2i(13, 23))
	pac.steer(Vector2i.LEFT)
	_tick_until_arrivals(mover, 1)
	print("fresh_dot score=", game.score, " dots=", maze.dots_left, " cell=", mover.cell)
	if game.score != 20 or maze.dots_left != 256 or mover.cell != Vector2i(12, 23):
		failures.append("fresh_dot")

	# --- Pellet: score, fright window, timer expiry ----------------------
	var fright_events: Array[bool] = []
	game.frightened_changed.connect(func(active: bool) -> void: fright_events.append(active))
	mover.place(Vector2i(1, 4))
	pac.steer(Vector2i.UP)
	_tick_until_arrivals(mover, 1)  # (1,3) is a pellet
	print("after_pellet score=", game.score, " pellets=", maze.pellets_left,
		" frightened=", game.is_frightened(), " hud=", score_label.text)
	if game.score != 70 or maze.pellets_left != 3:
		failures.append("pellet_score")
	if not game.is_frightened():
		failures.append("pellet_fright")
	if score_label.text != "SCORE 70":
		failures.append("hud_after_pellet")
	game.tick_timers(3.0)
	if not game.is_frightened():
		failures.append("fright_ended_early")
	game.tick_timers(4.0)
	print("fright_events=", fright_events, " frightened_after_7s=", game.is_frightened())
	if game.is_frightened():
		failures.append("fright_did_not_expire")
	if fright_events != [true, false]:
		failures.append("fright_events=%s" % str(fright_events))

	# --- Board clear: refill, level++, respawn ---------------------------
	for cell in MazeData.dot_cells():
		maze.eat_dot(cell)
	var pellets := MazeData.pellet_cells()
	for i in pellets.size():
		if i < pellets.size() - 1:
			maze.eat_pellet(pellets[i])
	var last_pellet: Vector2i = pellets[pellets.size() - 1]
	print("pre_clear food=", maze.food_remaining(), " last_pellet=", last_pellet)
	if maze.food_remaining() != 1:
		failures.append("pre_clear_food=%d" % maze.food_remaining())

	mover.place(last_pellet + Vector2i.DOWN)
	pac.steer(Vector2i.UP)
	_tick_until_arrivals(mover, 1)
	print("after_clear level=", game.level, " dots=", maze.dots_left,
		" pellets=", maze.pellets_left, " cell=", mover.cell,
		" score=", game.score, " hud=", level_label.text)
	if game.level != 2:
		failures.append("level=%d" % game.level)
	if maze.dots_left != 258 or maze.pellets_left != 4:
		failures.append("board_not_refilled")
	if mover.cell != MazeData.PAC_SPAWN:
		failures.append("pac_not_respawned=%s" % str(mover.cell))
	if game.score != 120:
		failures.append("score_after_clear=%d" % game.score)
	if level_label.text != "LEVEL 2":
		failures.append("level_hud=%s" % level_label.text)

	print("failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _tick_until_arrivals(mover: GridMover, count: int) -> void:
	var seen := [0]
	var callback := func(_cell: Vector2i) -> void: seen[0] += 1
	mover.arrived.connect(callback)
	var guard := 0
	while seen[0] < count and guard < 200:
		mover.tick(1.0 / 60.0)
		guard += 1
	mover.arrived.disconnect(callback)
