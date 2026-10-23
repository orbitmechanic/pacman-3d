extends Node3D

## Dev hooks (pass after `--`):
##   --capture <path> --frames N  : render N frames, save a PNG, quit 0
##   --demo                       : left-hand-rule autopilot (attract mode)
##   --frighten                   : start with the frightened window open

@onready var pac: Pacman = $Pacman
@onready var game: Game = $Game
@onready var maze: MazeView = $MazeView
@onready var title: Label = $UI/Title
@onready var score_label: Label = $UI/Score
@onready var level_label: Label = $UI/Level
@onready var lives_label: Label = $UI/Lives
@onready var game_over_label: Label = $UI/GameOver

var _demo := false

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
	game.game_over.connect(_on_game_over)
	game.setup(pac, maze, ghost_nodes)
	pac.arrived.connect(_on_pac_arrived)
	if _demo:
		title.text = "PAC-MAN 3D — demo"
		pac.steer(Vector2i.LEFT)
	if args.has("--frighten"):
		game.frightened_left = Game.FRIGHTENED_SECONDS
	_maybe_capture_on_exit()

func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE %d" % score

func _on_level_changed(level: int) -> void:
	level_label.text = "LEVEL %d" % level

func _on_lives_changed(lives: int) -> void:
	lives_label.text = "LIVES %d" % lives

func _on_game_over() -> void:
	game_over_label.visible = true

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
