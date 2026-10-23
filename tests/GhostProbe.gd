extends SceneTree

## Gate 2 probe for ghost behaviour (issue #4): cast and house spawns,
## scatter/chase targets, the pure direction chooser, house release through
## the door, frightened timing, the 200/400/800/1600 chain, eaten return, life
## loss and game over. Everything is driven by fixed ticks so the whole run is
## deterministic.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame

	var pac: Pacman = main.get_node("Pacman")
	var game: Game = main.get_node("Game")
	var lives_display: LivesDisplay = main.get_node("UI/Lives")
	var over_label: Label = main.get_node("UI/GameOver")
	var ghosts: Array[Ghost] = []
	for child in main.get_node("Ghosts").get_children():
		if child is Ghost:
			ghosts.append(child)
	var failures: Array[String] = []

	pac.set_physics_process(false)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_game()
	game.tick_timers(Game.READY_SECONDS + 0.01)

	var blinky := ghosts[0]
	var pinky := ghosts[1]
	var inky := ghosts[2]
	var clyde := ghosts[3]

	# --- 4.1 cast and house spawns ---------------------------------------
	print("cast=", ghosts.size(), " blinky=", blinky.personality,
		" cell=", blinky.mover.cell, " state=", blinky.state)
	if ghosts.size() != 4:
		failures.append("cast=%d" % ghosts.size())
	if blinky.state != Ghost.State.ROAMING or blinky.mover.cell != MazeData.HOUSE_EXIT:
		failures.append("blinky_spawn")
	for g in [pinky, inky, clyde]:
		if g.state != Ghost.State.IN_HOUSE:
			failures.append("house_spawn_%d_state=%d" % [g.personality, g.state])
	print("house_cells=", pinky.mover.cell, inky.mover.cell, clyde.mover.cell)
	if pinky.mover.cell != Vector2i(13, 13) or inky.mover.cell != Vector2i(11, 13) \
			or clyde.mover.cell != Vector2i(16, 13):
		failures.append("house_cells")
	if lives_display.lives != Game.START_LIVES:
		failures.append("lives_hud=%d" % lives_display.lives)

	# --- 4.2 scatter route targets ---------------------------------------
	game.ghost_mode = Game.GhostMode.SCATTER
	var corners := {
		Ghost.Personality.BLINKY: Vector2i(25, 0),
		Ghost.Personality.PINKY: Vector2i(2, 0),
		Ghost.Personality.INKY: Vector2i(27, 30),
		Ghost.Personality.CLYDE: Vector2i(0, 30),
	}
	for g in ghosts:
		var want: Vector2i = corners[g.personality]
		print("scatter[", g.personality, "]=", g.target_cell())
		if g.target_cell() != want:
			failures.append("scatter_%d" % g.personality)

	# --- 4.3 chase route targets -----------------------------------------
	# Park Pac-Man facing left on the spawn row; ghosts are outside/house.
	pac.mover.place(Vector2i(13, 23))
	pac.mover.dir = Vector2i.LEFT
	game.ghost_mode = Game.GhostMode.CHASE
	var blinky_at := blinky.mover.cell
	var ahead: Vector2i = pac.mover.cell + pac.mover.dir * 2
	var want_inky: Vector2i = blinky_at + 2 * (ahead - blinky_at)
	print("chase blinky=", blinky.target_cell(), " pinky=", pinky.target_cell(),
		" inky=", inky.target_cell(), " clyde=", clyde.target_cell())
	if blinky.target_cell() != pac.mover.cell:
		failures.append("chase_blinky")
	if pinky.target_cell() != pac.mover.cell + Vector2i(-4, 0):
		failures.append("chase_pinky=%s" % str(pinky.target_cell()))
	if inky.target_cell() != want_inky:
		failures.append("chase_inky=%s want=%s" % [str(inky.target_cell()), str(want_inky)])
	if clyde.target_cell() != pac.mover.cell:
		failures.append("chase_clyde_far=%s" % str(clyde.target_cell()))
	# Clyde switches to his corner once he is within 8 tiles.
	clyde.mover.place(Vector2i(13, 21))
	print("clyde_close=", clyde.target_cell())
	if clyde.target_cell() != corners[Ghost.Personality.CLYDE]:
		failures.append("chase_clyde_close=%s" % str(clyde.target_cell()))
	clyde.mover.place(Vector2i(16, 13))

	# --- 4.4 pure direction chooser --------------------------------------
	var junction := Vector2i(6, 21)
	var open_dirs := 0
	for d in Ghost.TILE_DIRS:
		if MazeData.is_walkable(junction + d):
			open_dirs += 1
	var picked := Ghost.choose_direction(junction, Vector2i.UP, Vector2i(1, 20))
	var forced := Ghost.choose_direction(Vector2i(6, 20), Vector2i.UP, Vector2i(6, 30))
	var allowed := Ghost.choose_direction(Vector2i(6, 20), Vector2i.UP, Vector2i(6, 30), false, true)
	var avoid_reverse := Ghost.choose_direction(junction, Vector2i.UP, Vector2i(6, 22))
	print("junction_open=", open_dirs, " picked=", picked, " forced=", forced,
		" allow_rev=", allowed, " no_reverse=", avoid_reverse)
	if open_dirs != 3:
		failures.append("junction_shape=%d" % open_dirs)
	if picked != Vector2i.LEFT:
		failures.append("chooser_pick=%s" % str(picked))
	if forced != Vector2i.UP:
		failures.append("chooser_forced=%s" % str(forced))
	if allowed != Vector2i.DOWN:
		failures.append("chooser_allow_reverse=%s" % str(allowed))
	if avoid_reverse == Vector2i.DOWN:
		failures.append("chooser_reversed_into_dead_end")

	# --- 4.5 house release through the door ------------------------------
	var steps := 0
	while pinky.state != Ghost.State.ROAMING and steps < 400:
		pinky.tick(1.0 / 60.0)
		steps += 1
	print("pinky_release_steps=", steps, " state=", pinky.state,
		" cell=", pinky.mover.cell, " allow_door=", pinky.mover.allow_door)
	if pinky.state != Ghost.State.ROAMING:
		failures.append("pinky_never_released")
	if pinky.mover.cell != MazeData.HOUSE_EXIT:
		failures.append("pinky_exit_cell=%s" % str(pinky.mover.cell))
	if pinky.mover.allow_door:
		failures.append("pinky_still_has_door_access")

	# --- 4.6 frightened: speed, paused waves, reversal on wave change ----
	game.ghost_mode = Game.GhostMode.SCATTER
	game.frightened_left = 6.0
	game._wave_left = 0.01
	game.tick_timers(0.02)
	print("fright_speed=", blinky.current_speed(), " mode=", game.ghost_mode,
		" wave_left=", game._wave_left)
	if not is_equal_approx(blinky.current_speed(), Ghost.FRIGHTENED_SPEED):
		failures.append("fright_speed=%f" % blinky.current_speed())
	if game.ghost_mode != Game.GhostMode.SCATTER or game._wave_left != 0.01:
		failures.append("wave_ran_while_frightened")

	game.frightened_left = 0.0
	blinky.mover.place(Vector2i(5, 23))
	blinky.state = Ghost.State.ROAMING
	blinky.mover.request(Vector2i.RIGHT)
	for i in 6:
		blinky.mover.tick(1.0 / 60.0)
	game.tick_timers(0.02)
	print("wave_switch mode=", game.ghost_mode, " blinky_dir=", blinky.mover.dir,
		" speed=", blinky.current_speed())
	if game.ghost_mode != Game.GhostMode.CHASE:
		failures.append("wave_switch_mode=%d" % game.ghost_mode)
	if blinky.mover.dir != Vector2i.LEFT:
		failures.append("wave_reversal=%s" % str(blinky.mover.dir))

	# --- 4.7 eaten chain: 200/400/800/1600 capped ------------------------
	var chain_points: Array[int] = []
	game.frightened_left = 6.0
	for i in 5:
		blinky.state = Ghost.State.ROAMING
		blinky.mover.allow_door = false
		blinky.mover.place(Vector2i(13, 23))
		pac.mover.place(Vector2i(13, 23))
		var before := game.score
		game.resolve_collisions()
		chain_points.append(game.score - before)
	game.frightened_left = 0.0
	print("chain_points=", chain_points, " blinky_state=", blinky.state,
		" body_visible=", blinky.body.visible, " allow_door=", blinky.mover.allow_door)
	if chain_points != [200, 400, 800, 1600, 1600]:
		failures.append("chain=%s" % str(chain_points))
	if blinky.state != Ghost.State.EATEN or blinky.body.visible:
		failures.append("eaten_visual_state")

	# An eaten ghost must not hurt Pac-Man even when it overlaps him.
	var lives_before := game.lives
	game.resolve_collisions()
	print("eaten_overlap_lives=", game.lives, " state=", game.state)
	if game.lives != lives_before or game.state != Game.State.PLAYING:
		failures.append("eaten_ghost_killed_pac")

	# --- 4.8 eaten ghost flies home through the door ---------------------
	blinky.mover.place(MazeData.HOUSE_EXIT)
	steps = 0
	while blinky.state != Ghost.State.IN_HOUSE and steps < 600:
		blinky.tick(1.0 / 60.0)
		steps += 1
	print("return_home_steps=", steps, " state=", blinky.state,
		" cell=", blinky.mover.cell, " body_visible=", blinky.body.visible)
	if blinky.state != Ghost.State.IN_HOUSE:
		failures.append("eaten_never_home=%d" % blinky.state)
	if blinky.mover.cell != Ghost.HOUSE_CENTER or not blinky.body.visible:
		failures.append("eaten_home_cell=%s" % str(blinky.mover.cell))
	if blinky.mover.allow_door:
		failures.append("eaten_kept_door_access")

	# --- 4.9 life loss, reset and HUD ------------------------------------
	game.frightened_left = 0.0
	pinky.mover.place(Vector2i(13, 23))
	pinky.state = Ghost.State.ROAMING
	pac.mover.place(Vector2i(13, 23))
	game.resolve_collisions()
	print("after_hit lives=", game.lives, " state=", game.state,
		" frozen=", pac.mover.frozen, " pucks=", lives_display.lives)
	if game.lives != Game.START_LIVES - 1 or game.state != Game.State.DYING:
		failures.append("hit_lives=%d state=%d" % [game.lives, game.state])
	if not pac.mover.frozen:
		failures.append("pac_not_frozen")
	if lives_display.lives != Game.START_LIVES - 1:
		failures.append("lives_hud_after_hit=%d" % lives_display.lives)

	game.tick_timers(Game.DEATH_SECONDS + 0.1)
	print("after_death state=", game.state, " pac=", pac.mover.cell,
		" blinky=", blinky.mover.cell, blinky.state, " pinky=", pinky.mover.cell, pinky.state,
		" frozen=", pac.mover.frozen)
	if game.state != Game.State.READY:
		failures.append("death_ready_state=%d" % game.state)
	if pac.mover.cell != MazeData.PAC_SPAWN:
		failures.append("pac_not_respawned=%s" % str(pac.mover.cell))
	if blinky.mover.cell != MazeData.HOUSE_EXIT or blinky.state != Ghost.State.ROAMING:
		failures.append("blinky_not_reset")
	if pinky.state != Ghost.State.IN_HOUSE:
		failures.append("pinky_not_reset=%d" % pinky.state)
	game.tick_timers(Game.READY_SECONDS + 0.1)
	if game.state != Game.State.PLAYING or pac.mover.frozen:
		failures.append("ready_not_resolved=%d" % game.state)

	# --- 4.10 lose the remaining lives, then restart ----------------------
	var deaths := 0
	while game.state != Game.State.GAME_OVER and deaths < 6:
		deaths += 1
		pinky.mover.place(pac.mover.nearest_cell())
		pinky.state = Ghost.State.ROAMING
		game.resolve_collisions()
		game.tick_timers(Game.DEATH_SECONDS + 0.1)
		if game.state == Game.State.READY:
			game.tick_timers(Game.READY_SECONDS + 0.1)
	print("game_over deaths=", deaths, " state=", game.state, " lives=", game.lives,
		" pucks=", lives_display.lives, " overlay=", over_label.visible)
	if game.state != Game.State.GAME_OVER or game.lives != 0:
		failures.append("game_over_state=%d lives=%d" % [game.state, game.lives])
	if lives_display.lives != 0:
		failures.append("game_over_pucks=%d" % lives_display.lives)
	if not over_label.visible:
		failures.append("game_over_overlay")

	game.start_game()
	game.tick_timers(Game.READY_SECONDS + 0.1)
	print("restart state=", game.state, " lives=", game.lives, " score=", game.score,
		" dots=", main.get_node("MazeView").dots_left, " pucks=", lives_display.lives,
		" overlay=", over_label.visible)
	if game.state != Game.State.PLAYING or game.lives != Game.START_LIVES:
		failures.append("restart_state=%d lives=%d" % [game.state, game.lives])
	if game.score != 0 or lives_display.lives != Game.START_LIVES:
		failures.append("restart_hud")
	if main.get_node("MazeView").dots_left != 258:
		failures.append("restart_food")
	if over_label.visible:
		failures.append("restart_overlay")

	print("failures=", failures)
	quit(0 if failures.is_empty() else 1)
