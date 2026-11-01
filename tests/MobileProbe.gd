extends SceneTree

## Gate 2 probe for the mobile/polish layer: gamepad bindings, the on-screen
## pad's hit geometry, swipe steering, start/pause wiring, pause freezing the
## cast, high-score tracking and the procedural sound bank. Prints KEY=value
## facts; exit != 0 fails.

func _initialize() -> void:
	var failures: Array[String] = []

	# --- Gamepad and pause live in the input map, not in code --------------
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		var has_axis := false
		var has_dpad := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				has_axis = true
			elif event is InputEventJoypadButton:
				has_dpad = true
		if not has_axis:
			failures.append("%s_missing_stick" % action)
		if not has_dpad:
			failures.append("%s_missing_dpad" % action)
	if not InputMap.has_action("pause"):
		failures.append("pause_action_missing")

	TouchPad.force = 1
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var game: Game = main.get_node("Game")
	var pac: Pacman = main.get_node("Pacman")
	var pad: TouchPad = main.get_node("UI/TouchPad")
	var sfx: Sfx = main.get_node("Sfx")

	# --- Pad geometry and visibility --------------------------------------
	print("pad active=", pad.active, " visible=", pad.visible,
		" size=", pad.size, " dpad=", pad.dpad_center())
	if not pad.active or not pad.visible:
		failures.append("touchpad_not_visible")
	if pad.size.x < 100.0 or pad.size.y < 100.0:
		failures.append("touchpad_zero_size")
	if pad.button_at(pad.button_center(TouchPad.BUTTON_UP)) != TouchPad.BUTTON_UP:
		failures.append("hit_up")
	if pad.button_at(pad.button_center(TouchPad.BUTTON_LEFT)) != TouchPad.BUTTON_LEFT:
		failures.append("hit_left")
	if pad.button_at(pad.button_center(TouchPad.BUTTON_ACTION)) != TouchPad.BUTTON_ACTION:
		failures.append("hit_action")
	if pad.button_at(pad.size * 0.5) != -1:
		failures.append("hit_field")

	# --- Action button starts the run -------------------------------------
	_touch(pad, true, pad.button_center(TouchPad.BUTTON_ACTION), 0)
	_touch(pad, false, pad.button_center(TouchPad.BUTTON_ACTION), 0)
	await process_frame
	print("after_tap state=", game.state, " in_play=", pad.in_play)
	if game.state != Game.State.READY:
		failures.append("tap_did_not_start")
	if not pad.in_play:
		failures.append("pad_not_in_play")

	# --- d-pad and swipe both reach Pac-Man -------------------------------
	var dirs: Array[Vector2i] = []
	pad.steered.connect(func(direction: Vector2i) -> void: dirs.append(direction))
	_touch(pad, true, pad.button_center(TouchPad.BUTTON_UP), 1)
	_touch(pad, false, pad.button_center(TouchPad.BUTTON_UP), 1)
	print("dpad_dirs=", dirs, " desired=", pac.desired_dir)
	if dirs != [Vector2i.UP]:
		failures.append("dpad_emission")
	if pac.desired_dir != Vector2i.UP:
		failures.append("dpad_did_not_steer")

	dirs.clear()
	var origin := pad.size * 0.5
	_touch(pad, true, origin, 2)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = origin + Vector2(-90.0, 4.0)
	drag.relative = Vector2(-90.0, 4.0)
	pad._gui_input(drag)
	_touch(pad, false, drag.position, 2)
	print("swipe_dirs=", dirs, " desired=", pac.desired_dir)
	if dirs != [Vector2i.LEFT]:
		failures.append("swipe_emission")
	if pac.desired_dir != Vector2i.LEFT:
		failures.append("swipe_did_not_steer")

	# --- Pause button freezes and resumes ---------------------------------
	game.tick_timers(Game.READY_SECONDS + 0.01)
	_touch(pad, true, pad.button_center(TouchPad.BUTTON_ACTION), 3)
	_touch(pad, false, pad.button_center(TouchPad.BUTTON_ACTION), 3)
	print("paused=", game.paused, " frozen=", pac.mover.frozen, " pad_paused=", pad.paused)
	if not game.paused or not pac.mover.frozen or not pad.paused:
		failures.append("pause_did_not_freeze")
	_touch(pad, true, pad.button_center(TouchPad.BUTTON_ACTION), 4)
	_touch(pad, false, pad.button_center(TouchPad.BUTTON_ACTION), 4)
	if game.paused or pac.mover.frozen or pad.paused:
		failures.append("pause_did_not_resume")

	# --- High score tracks the run and survives a restart ------------------
	game.high_score = 0
	game.score = 0
	var highs: Array[int] = []
	game.high_score_changed.connect(func(value: int) -> void: highs.append(value))
	game._add_score(1234)
	print("high_score=", game.high_score, " events=", highs)
	if game.high_score != 1234 or highs != [1234]:
		failures.append("high_score_tracking")
	game.start_game()
	if game.score != 0 or game.high_score != 1234:
		failures.append("high_score_restart")

	# --- Procedural bank built and one-shots fire -------------------------
	var streams_ok := true
	for name in ["chomp_high", "chomp_low", "pellet", "ghost_eaten", "death",
			"level_clear", "ready", "game_over", "siren", "fright_loop"]:
		var stream: AudioStreamWAV = sfx.streams.get(name)
		if stream == null or stream.data.size() == 0:
			streams_ok = false
			failures.append("stream_%s" % name)
	game.dot_eaten.emit()
	await process_frame
	print("streams=", sfx.streams.size(), " voices=", sfx.active_voices())
	if not streams_ok:
		failures.append("stream_bank_incomplete")
	if sfx.active_voices() < 1:
		failures.append("chomp_did_not_play")

	# --- Force-off hides the pad on a desktop client ----------------------
	TouchPad.force = 0
	var desktop_pad := TouchPad.new()
	desktop_pad.size = Vector2(1280.0, 720.0)
	main.get_node("UI").add_child(desktop_pad)
	await process_frame
	print("desktop_pad visible=", desktop_pad.visible, " active=", desktop_pad.active)
	if desktop_pad.visible or desktop_pad.active:
		failures.append("desktop_pad_visible")

	print("failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _touch(pad: TouchPad, pressed: bool, at: Vector2, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	pad._gui_input(event)
