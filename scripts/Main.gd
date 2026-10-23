extends Node3D

## Dev hook: `godot --path . -- --capture /tmp/shot.png --frames 90`
## renders N frames, saves a PNG, and exits 0.

func _ready() -> void:
	_maybe_capture_on_exit()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_down") \
			or Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		$UI/Title.text = "scaffold: movement lands in PR #2"

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
