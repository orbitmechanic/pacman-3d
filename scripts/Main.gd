extends Node3D

## Dev hooks (pass after `--`):
##   --capture <path> --frames N  : render N frames, save a PNG, quit 0
##   --demo                       : left-hand-rule autopilot (attract mode)

@onready var pac: Pacman = $Pacman
@onready var title: Label = $UI/Title

var _demo := false

func _ready() -> void:
	_demo = OS.get_cmdline_user_args().has("--demo")
	pac.arrived.connect(_on_pac_arrived)
	if _demo:
		title.text = "PAC-MAN 3D — demo"
		pac.steer(Vector2i.LEFT)
	_maybe_capture_on_exit()

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
