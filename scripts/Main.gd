extends Node3D

## Scene wiring and presentation. Gameplay rules live in Game; this node maps
## its states onto the HUD, the camera and the dev hooks.
##
## Dev hooks (pass after `--`):
##   --capture <path> --frames N  : render N frames, save a PNG, quit 0
##   --demo                       : left-hand-rule autopilot (attract mode)
##   --frighten                   : start with the frightened window open
##   --state <name>               : force title|ready|dying|clear|over for a shot

const PLAY_POS := Vector3(0.0, 33.0, 15.0)
const PLAY_ROT := -68.0
const PLAY_FOV := 50.0
const TITLE_POS := Vector3(0.0, 38.0, 21.0)
const TITLE_ROT := -62.0
const TITLE_FOV := 58.0

@onready var pac: Pacman = $Pacman
@onready var game: Game = $Game
@onready var maze: MazeView = $MazeView
@onready var camera: Camera3D = $Camera3D
@onready var title: Label = $UI/Title
@onready var score_label: Label = $UI/Score
@onready var level_label: Label = $UI/Level
@onready var lives_display: LivesDisplay = $UI/Lives
@onready var title_screen: Control = $UI/TitleScreen
@onready var ready_label: Label = $UI/Ready
@onready var clear_label: Label = $UI/LevelClear
@onready var game_over_label: Label = $UI/GameOver
@onready var game_over_hint: Label = $UI/GameOverHint

var _demo := false
var _cam_base := PLAY_POS
var _cam_pos := PLAY_POS
var _cam_rot := PLAY_ROT
var _cam_fov := PLAY_FOV
var _shake := 0.0
var _state_time := 0.0
var _demo_over_hold := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_demo = args.has("--demo")
	var ghost_nodes: Array[Ghost] = []
	for child in $Ghosts.get_children():
		if child is Ghost:
			ghost_nodes.append(child)
	game.score_changed.connect(_on_score_changed)
	game.level_changed.connect(_on_level_changed)
	game.lives_changed.connect(_on_lives_changed)
	game.state_changed.connect(_on_state_changed)
	game.game_over.connect(_on_game_over)
	game.setup(pac, maze, ghost_nodes)
	pac.arrived.connect(_on_pac_arrived)
	if args.has("--state"):
		_apply_state_hook(args[args.find("--state") + 1])
	elif _demo:
		title.text = "PAC-MAN 3D — demo"
		game.start_game()
		pac.steer(Vector2i.LEFT)
	if args.has("--frighten"):
		game.frightened_left = Game.FRIGHTENED_SECONDS
	_cam_base = camera.position
	_maybe_capture_on_exit()

func _process(delta: float) -> void:
	_state_time += delta
	_update_camera(delta)
	_update_flash()
	if _demo and game.state == Game.State.GAME_OVER:
		_demo_over_hold += delta
		if _demo_over_hold > 2.0:
			_demo_over_hold = 0.0
			game.start_game()
			pac.steer(Vector2i.LEFT)
	if Input.is_action_just_pressed("start"):
		if game.state == Game.State.TITLE or game.state == Game.State.GAME_OVER:
			game.start_game()

func _update_camera(delta: float) -> void:
	var t := 1.0 - exp(-3.2 * delta)
	_cam_base = _cam_base.lerp(_cam_pos, t)
	camera.rotation_degrees = Vector3(lerp(camera.rotation_degrees.x, _cam_rot, t), 0.0, 0.0)
	camera.fov = lerp(camera.fov, _cam_fov, t)
	var shake_offset := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
		var amp := 0.45 * _shake
		shake_offset = Vector3(
			sin(_state_time * 63.0) * amp,
			cos(_state_time * 47.0) * amp * 0.5,
			0.0
		)
	camera.position = _cam_base + shake_offset

func _update_flash() -> void:
	if game.state != Game.State.LEVEL_CLEAR:
		maze.set_flash_amount(0.0)
		return
	# Bright pulsing glow rather than a hard blink: reads as a flash at any
	# capture time and never leaves the board fully dim.
	maze.set_flash_amount(0.7 + 0.3 * sin(_state_time * 9.0))

func _on_state_changed(state: int) -> void:
	title_screen.visible = state == Game.State.TITLE
	ready_label.visible = state == Game.State.READY
	clear_label.visible = state == Game.State.LEVEL_CLEAR
	game_over_label.visible = state == Game.State.GAME_OVER
	game_over_hint.visible = state == Game.State.GAME_OVER
	title.visible = state != Game.State.TITLE
	_state_time = 0.0
	if state == Game.State.TITLE:
		_cam_pos = TITLE_POS
		_cam_rot = TITLE_ROT
		_cam_fov = TITLE_FOV
	elif state != Game.State.GAME_OVER:
		_cam_pos = PLAY_POS
		_cam_rot = PLAY_ROT
		_cam_fov = PLAY_FOV
	if state == Game.State.DYING:
		_shake = 1.0

func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE %d" % score

func _on_level_changed(level: int) -> void:
	level_label.text = "LEVEL %d" % level
	maze.apply_level_tint(level)

func _on_lives_changed(lives: int) -> void:
	lives_display.set_lives(lives)

func _on_game_over() -> void:
	_demo_over_hold = 0.0

func _on_pac_arrived(cell: Vector2i) -> void:
	if not _demo:
		return
	var back := -pac.mover.dir
	for d in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		if d == back:
			continue
		if MazeData.is_walkable(cell + d):
			pac.steer(d)
			return
	if MazeData.is_walkable(cell + back):
		pac.steer(back)

## Reproducible screenshots of every state (see CONTRIBUTING.md).
func _apply_state_hook(name: String) -> void:
	if name == "title":
		return
	game.start_game()
	game.tick_timers(Game.READY_SECONDS + 0.01)
	match name:
		"ready":
			game.start_game()
		"dying":
			pac.steer(Vector2i.LEFT)
			game.lose_life()
		"clear":
			for cell in MazeData.dot_cells():
				maze.eat_dot(cell)
			for cell in MazeData.pellet_cells():
				maze.eat_pellet(cell)
			game.begin_level_clear()
		"over":
			game.lives = 1
			game.lose_life()
			game.tick_timers(Game.DEATH_SECONDS + 0.01)

func _maybe_capture_on_exit() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture"):
		return
	var path: String = args[args.find("--capture") + 1]
	var frames := 60
	if args.has("--frames"):
		frames = int(args[args.find("--frames") + 1])
	for i in frames:
		await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("capture_saved=", path, " err=", err)
	get_tree().quit(0)
