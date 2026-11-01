class_name TouchPad
extends Control

## On-screen direction pad and action button for touch clients, plus
## swipe-anywhere steering. The pad is drawn with `_draw()` so the project
## keeps its no-binary-assets rule; input is handled here rather than through
## the action map because a thumb on a button must not disturb held keys.
##
## Layout is in the 1280x720 stretched canvas space, so the pad lands in the
## same place on every phone and tablet. `TouchPad.force` and the
## `--touch-controls` / `--no-touch-controls` dev hooks let probes and desktop
## reviewers exercise the touch path without a touchscreen.

signal steered(direction: Vector2i)
signal start_pressed
signal pause_pressed

const BUTTON_UP := 0
const BUTTON_RIGHT := 1
const BUTTON_DOWN := 2
const BUTTON_LEFT := 3
const BUTTON_ACTION := 4

const MARGIN := 30.0
const CELL := 82.0
const PAD_RADIUS := 37.0
const PAD_HIT_RADIUS := 46.0
const ACTION_RADIUS := 52.0
const ACTION_HIT_RADIUS := 64.0
const SWIPE_MIN := 26.0

const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

## -1 decides by the client, 0 forces off, 1 forces on. Set before the scene
## is instantiated (probes) or via the dev hooks below.
static var force := -1

## Whether this client gets the pads. The title legend reads this too, so the
## prompt and the visible controls cannot disagree.
var active := false

## True while the board accepts steering (READY or PLAYING); flips the action
## button between "start" and "pause" glyphs.
var in_play := false
var paused := false

var _field_pointer := -1
var _action_pointer := -1
var _button_pointers: Dictionary = {}
var _held := -1
var _swipe_origin := Vector2.ZERO
var _swipe_active := false
var _last_swipe_dir := Vector2i.ZERO
var _using_touch := false

## Browser probe: iPadOS reports a macOS user agent, so touch points are the
## reliable tablet signal. Matches the rule used by the other Godot web ports.
const MOBILE_JS := """
String(/android|iphone|ipad|ipod|mobile/i.test(navigator.userAgent)
	|| (/Mac/i.test(navigator.platform) && navigator.maxTouchPoints > 1))
"""

static func is_mobile_client() -> bool:
	if force != -1:
		return force == 1
	if OS.has_feature("web"):
		return JavaScriptBridge.eval(MOBILE_JS, true) == "true"
	return DisplayServer.is_touchscreen_available()

func _ready() -> void:
	_apply_overrides()
	active = is_mobile_client()
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	set_process_input(true)

static func _apply_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-controls":
			force = 1
		elif arg == "--no-touch-controls":
			force = 0
	var env := OS.get_environment("TOUCH_CONTROLS")
	if env == "1":
		force = 1
	elif env == "0":
		force = 0

func set_in_play(value: bool) -> void:
	in_play = value
	queue_redraw()

func set_paused(value: bool) -> void:
	paused = value
	queue_redraw()

## Centre of the d-pad's middle button; the four arrows sit one CELL away.
func dpad_center() -> Vector2:
	return Vector2(MARGIN + CELL * 1.5, size.y - MARGIN - CELL * 1.5)

func button_center(index: int) -> Vector2:
	if index == BUTTON_ACTION:
		return Vector2(size.x - MARGIN - ACTION_RADIUS, size.y - MARGIN - ACTION_RADIUS)
	var offset: Vector2 = {
		BUTTON_UP: Vector2(0.0, -CELL),
		BUTTON_RIGHT: Vector2(CELL, 0.0),
		BUTTON_DOWN: Vector2(0.0, CELL),
		BUTTON_LEFT: Vector2(-CELL, 0.0),
	}[index]
	return dpad_center() + offset

## Which pad a point belongs to, or -1 for the play field (swipe territory).
func button_at(point: Vector2) -> int:
	if point.distance_to(button_center(BUTTON_ACTION)) <= ACTION_HIT_RADIUS:
		return BUTTON_ACTION
	for i in 4:
		if point.distance_to(button_center(i)) <= PAD_HIT_RADIUS:
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		_using_touch = true
		if event.pressed:
			_press_at(event.position, event.index)
		else:
			_release(event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _field_pointer:
			_drag(event.position)
		accept_event()
	elif event is InputEventMouseButton and not _using_touch:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_at(event.position, 0)
			else:
				_release(0)
			accept_event()
	elif event is InputEventMouseMotion and not _using_touch and _field_pointer == 0:
		_drag(event.position)
		accept_event()

func _press_at(point: Vector2, pointer: int) -> void:
	var pad := button_at(point)
	if pad == BUTTON_ACTION:
		# One thumb owns the action button; a second press must not toggle twice.
		if _action_pointer != -1:
			return
		_action_pointer = pointer
		if in_play:
			pause_pressed.emit()
		else:
			start_pressed.emit()
		return
	if pad >= 0:
		# One pointer per button, but the D-pad and the action button can be
		# held by different thumbs at the same time.
		if _button_pointers.has(pointer):
			return
		_button_pointers[pointer] = pad
		_held = pad
		_steer(DIRS[pad])
		if not in_play:
			start_pressed.emit()
		queue_redraw()
		return
	# Empty field: a tap starts the run, a drag steers.
	if _field_pointer != -1:
		return
	_field_pointer = pointer
	_swipe_origin = point
	_swipe_active = true
	_last_swipe_dir = Vector2i.ZERO
	if not in_play:
		start_pressed.emit()

func _drag(point: Vector2) -> void:
	if not _swipe_active:
		return
	var delta := point - _swipe_origin
	if delta.length() < SWIPE_MIN:
		return
	var dir: Vector2i
	if absf(delta.x) > absf(delta.y):
		dir = Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
	else:
		dir = Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP
	# Reset the origin each time so a single long drag can trace a path.
	_swipe_origin = point
	if dir != _last_swipe_dir:
		_last_swipe_dir = dir
		_steer(dir)

func _release(pointer: int) -> void:
	if pointer == _action_pointer:
		_action_pointer = -1
	if _button_pointers.has(pointer):
		var pad: int = _button_pointers[pointer]
		_button_pointers.erase(pointer)
		if _held == pad:
			_held = -1
	if pointer == _field_pointer:
		_field_pointer = -1
		_swipe_active = false
		_last_swipe_dir = Vector2i.ZERO
	queue_redraw()

func _steer(dir: Vector2i) -> void:
	steered.emit(dir)

func _notification(what: int) -> void:
	# A backgrounded tab never delivers pointerup; drop every held direction.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_field_pointer = -1
		_action_pointer = -1
		_button_pointers.clear()
		_held = -1
		_swipe_active = false
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	var pad_fill := Color(0.92, 0.94, 1.0, 0.06)
	var pad_line := Color(0.75, 0.8, 1.0, 0.28)
	var held_fill := Color(0.98, 0.84, 0.16, 0.22)
	var held_line := Color(1.0, 0.88, 0.25, 0.8)
	for i in 4:
		var centre := button_center(i)
		var is_held := _held == i
		draw_circle(centre, PAD_RADIUS, held_fill if is_held else pad_fill)
		draw_arc(centre, PAD_RADIUS, 0.0, TAU, 40, held_line if is_held else pad_line, 2.0, true)
		_draw_arrow(centre, i, held_line if is_held else Color(0.82, 0.86, 1.0, 0.55))
	# Action button: play triangle on the title/game-over screens, pause bars
	# while a run is live (tap again to resume).
	var action := button_center(BUTTON_ACTION)
	draw_circle(action, ACTION_RADIUS, pad_fill)
	draw_arc(action, ACTION_RADIUS, 0.0, TAU, 48, pad_line, 2.0, true)
	if in_play and not paused:
		var bar := Color(0.82, 0.86, 1.0, 0.6)
		draw_rect(Rect2(action + Vector2(-15.0, -17.0), Vector2(9.0, 34.0)), bar)
		draw_rect(Rect2(action + Vector2(6.0, -17.0), Vector2(9.0, 34.0)), bar)
	else:
		var tri := PackedVector2Array([
			action + Vector2(-12.0, -18.0),
			action + Vector2(-12.0, 18.0),
			action + Vector2(20.0, 0.0),
		])
		draw_colored_polygon(tri, Color(1.0, 0.88, 0.25, 0.75))

func _draw_arrow(centre: Vector2, index: int, color: Color) -> void:
	var points: PackedVector2Array
	match index:
		BUTTON_UP:
			points = PackedVector2Array([
				centre + Vector2(0.0, -13.0),
				centre + Vector2(-11.0, 9.0),
				centre + Vector2(11.0, 9.0),
			])
		BUTTON_RIGHT:
			points = PackedVector2Array([
				centre + Vector2(13.0, 0.0),
				centre + Vector2(-9.0, -11.0),
				centre + Vector2(-9.0, 11.0),
			])
		BUTTON_DOWN:
			points = PackedVector2Array([
				centre + Vector2(0.0, 13.0),
				centre + Vector2(11.0, -9.0),
				centre + Vector2(-11.0, -9.0),
			])
		_:
			points = PackedVector2Array([
				centre + Vector2(-13.0, 0.0),
				centre + Vector2(9.0, 11.0),
				centre + Vector2(9.0, -11.0),
			])
	draw_colored_polygon(points, color)
