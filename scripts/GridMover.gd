class_name GridMover
extends RefCounted

## Tile-to-tile movement shared by Pac-Man and the ghosts.
##
## `cell` is the last tile arrived at; while `progress` runs 0..1 the actor is
## between `cell` and `to_cell`. Direction choice happens exactly at tile
## boundaries via the `decide` callback, which keeps the arcade feel (no
## mid-corridor turning except instant 180-degree reversals) and keeps all
## movement logic deterministic and headless-testable.

signal arrived(cell: Vector2i)

var cell: Vector2i
var to_cell: Vector2i
var dir := Vector2i.ZERO
var progress := 1.0
var tiles_per_second := 7.0
var allow_door := false
var frozen := false
## func(at_cell: Vector2i) -> Vector2i; Vector2i.ZERO means "stop here".
var decide: Callable

var _from_pos := Vector3.ZERO
var _to_pos := Vector3.ZERO

func _init(start_cell: Vector2i) -> void:
	place(start_cell)

func place(at: Vector2i) -> void:
	cell = at
	to_cell = at
	dir = Vector2i.ZERO
	progress = 1.0
	_from_pos = MazeData.tile_to_world(at)
	_to_pos = _from_pos

func is_moving() -> bool:
	return progress < 1.0

func world_position() -> Vector3:
	return _from_pos.lerp(_to_pos, progress)

## Tile the actor is closest to; used for collisions and dot eating.
func nearest_cell() -> Vector2i:
	return cell if progress < 0.5 else to_cell

## Ask for a direction now: instant 180-degree reversals, otherwise the
## request is picked up at the next tile boundary by `decide`.
func request(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	if is_moving() and direction == -dir:
		_reverse()
	elif not is_moving():
		_try_start(direction)

func tick(delta: float) -> void:
	if frozen:
		return
	var remaining := delta
	while remaining > 0.0 and not frozen:
		if progress >= 1.0 and not _choose_next():
			break
		var need := 1.0 - progress
		var advance := tiles_per_second * remaining
		if advance < need:
			progress += advance
			remaining = 0.0
		else:
			progress = 1.0
			remaining -= need / tiles_per_second
			_arrive()

func _choose_next() -> bool:
	var next_dir: Vector2i = dir
	if decide.is_valid():
		next_dir = decide.call(cell)
	if next_dir == Vector2i.ZERO or not MazeData.is_walkable(cell + next_dir, allow_door):
		dir = Vector2i.ZERO
		return false
	_begin(next_dir)
	return true

func _try_start(direction: Vector2i) -> void:
	if MazeData.is_walkable(cell + direction, allow_door):
		_begin(direction)

func _begin(direction: Vector2i) -> void:
	dir = direction
	var next_unwrapped := cell + direction
	to_cell = MazeData.wrap(next_unwrapped)
	_from_pos = MazeData.tile_to_world(cell)
	# Unwrapped target keeps tunnel crossings continuous instead of snapping.
	_to_pos = MazeData.tile_to_world(next_unwrapped)
	progress = 0.0

func _arrive() -> void:
	cell = to_cell
	# Snap the visual anchor to the wrapped tile so stopping at a tunnel seam
	# never leaves the actor rendered outside the board.
	_from_pos = MazeData.tile_to_world(cell)
	progress = 1.0
	arrived.emit(cell)

func _reverse() -> void:
	var old_cell := cell
	cell = to_cell
	to_cell = old_cell
	var old_from := _from_pos
	_from_pos = _to_pos
	_to_pos = old_from
	progress = 1.0 - progress
	dir = -dir
