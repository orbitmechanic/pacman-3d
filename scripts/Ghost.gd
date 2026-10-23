class_name Ghost
extends Node3D

## One ghost: house release, scatter/chase targeting, frightened wandering,
## eaten-eyes return trip. Movement reuses GridMover so ghosts obey the same
## tile rules as Pac-Man, and every decision is a pure function of the board,
## the current tile and the target - which is what makes GhostProbe possible.

enum Personality { BLINKY, PINKY, INKY, CLYDE }
enum State { IN_HOUSE, LEAVING, ROAMING, EATEN }

const SPEED := 6.2
const FRIGHTENED_SPEED := 4.4
const EATEN_SPEED := 12.0
const LEAVING_SPEED := 4.0
const HOUSE_CENTER := Vector2i(13, 13)
const TILE_DIRS := [
	Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT,
]

const SCATTER_CORNERS := {
	Personality.BLINKY: Vector2i(25, 0),
	Personality.PINKY: Vector2i(2, 0),
	Personality.INKY: Vector2i(27, 30),
	Personality.CLYDE: Vector2i(0, 30),
}

@export var personality: Personality = Personality.BLINKY
@export var tint := Color(1.0, 0.2, 0.2)

var mover: GridMover
var state: State = State.IN_HOUSE
var game: Game
var pac: Pacman
var speed_scale := 1.0
var rng := RandomNumberGenerator.new()

var _release_left := 0.0
var _bob := 0.0
var _facing := Vector2i.LEFT
var _body_mat: StandardMaterial3D
var _fright_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _body: MeshInstance3D
var _face: Node3D
var _pupils: Array[MeshInstance3D] = []

@onready var visual: Node3D = $Visual
@onready var body: MeshInstance3D = $Visual/Body

const VISUAL_Y := 0.56

func _ready() -> void:
	rng.seed = 0xA11CE + personality
	mover = GridMover.new(_house_cell())
	mover.tiles_per_second = SPEED
	mover.decide = _decide
	_build_materials()
	body.mesh = GhostMesh.build()
	body.material_override = _body_mat
	_build_face()
	position = Vector3(0.0, VISUAL_Y, 0.0)

func setup(game_ref: Game, pac_ref: Pacman) -> void:
	game = game_ref
	pac = pac_ref
	reset_to_spawn()

func reset_to_spawn() -> void:
	state = State.ROAMING if personality == Personality.BLINKY else State.IN_HOUSE
	mover.frozen = false
	mover.allow_door = false
	body.visible = true
	_pupils_visible(true)
	if state == State.IN_HOUSE:
		mover.place(_house_cell())
		_release_left = _release_delay()
	else:
		mover.place(MazeData.HOUSE_EXIT)
		_release_left = 0.0
	_sync_visual()

## Advance one physics step. Called by Game so the whole cast ticks together
## and probes can drive any ghost in isolation.
func tick(delta: float) -> void:
	mover.tiles_per_second = current_speed()
	if state == State.IN_HOUSE:
		_bob += delta
		_release_left -= delta
		if _release_left <= 0.0:
			_start_leaving()
		return
	mover.tick(delta)

func current_speed() -> float:
	var base := SPEED
	match state:
		State.EATEN:
			base = EATEN_SPEED
		State.LEAVING:
			base = LEAVING_SPEED
		State.IN_HOUSE:
			base = 0.0
		_:
			base = FRIGHTENED_SPEED if _frightened() else SPEED
	return base * speed_scale

func is_dangerous() -> bool:
	return state == State.ROAMING and not _frightened()

## Tile this ghost is heading for under the current mode - exposed for probes.
func target_cell() -> Vector2i:
	if state == State.EATEN:
		return HOUSE_CENTER
	if _frightened() or pac == null:
		return mover.cell
	if game != null and game.ghost_mode == Game.GhostMode.SCATTER:
		return SCATTER_CORNERS[personality]

	var ahead: Vector2i = pac.mover.cell + pac.mover.dir * 2
	match personality:
		Personality.BLINKY:
			return pac.mover.cell
		Personality.PINKY:
			return pac.mover.cell + pac.mover.dir * 4
		Personality.INKY:
			var blinky := _blinky_cell()
			return blinky + 2 * (ahead - blinky)
		_:
			var dist := Vector2(pac.mover.cell - mover.cell).length()
			return SCATTER_CORNERS[Personality.CLYDE] if dist < 8.0 else pac.mover.cell

func get_eaten() -> void:
	if state != State.ROAMING:
		return
	state = State.EATEN
	body.visible = false
	_pupils_visible(true)
	mover.allow_door = true

func on_frightened_started() -> void:
	if state == State.ROAMING and mover.dir != Vector2i.ZERO:
		mover.request(-mover.dir)

func on_mode_changed() -> void:
	if state != State.ROAMING or _frightened():
		return
	if mover.dir != Vector2i.ZERO:
		mover.request(-mover.dir)

## Pure direction chooser: never reverses unless it is the only way out, and
## otherwise minimises squared distance to `target`. Static so GhostProbe can
## unit-test the rule without a scene.
static func choose_direction(
	at: Vector2i,
	current: Vector2i,
	target: Vector2i,
	allow_door := false,
	allow_reverse := false
) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in TILE_DIRS:
		if not allow_reverse and d == -current:
			continue
		if MazeData.is_walkable(at + d, allow_door):
			options.append(d)
	if options.is_empty():
		var back := -current
		if back != Vector2i.ZERO and MazeData.is_walkable(at + back, allow_door):
			return back
		return Vector2i.ZERO
	var best: Vector2i = options[0]
	var best_dist := _dist2(at + best, target)
	for i in range(1, options.size()):
		var d: Vector2i = options[i]
		var cand := _dist2(at + d, target)
		if cand < best_dist:
			best = d
			best_dist = cand
	return best

func _decide(at: Vector2i) -> Vector2i:
	match state:
		State.LEAVING:
			if at != MazeData.HOUSE_EXIT:
				return Vector2i.UP
			state = State.ROAMING
			mover.allow_door = false
			body.visible = true
		State.EATEN:
			if at == HOUSE_CENTER:
				_enter_house()
				return Vector2i.ZERO
			return choose_direction(at, mover.dir, HOUSE_CENTER, true, true)
		State.IN_HOUSE:
			return Vector2i.ZERO
	if _frightened():
		return _random_turn(at)
	return choose_direction(at, mover.dir, target_cell())

func _random_turn(at: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in TILE_DIRS:
		if d == -mover.dir:
			continue
		if MazeData.is_walkable(at + d, false):
			options.append(d)
	if options.is_empty():
		return -mover.dir
	return options[rng.randi_range(0, options.size() - 1)]

func _start_leaving() -> void:
	state = State.LEAVING
	mover.place(HOUSE_CENTER)
	mover.allow_door = true
	mover.request(Vector2i.UP)

func _enter_house() -> void:
	state = State.IN_HOUSE
	mover.place(HOUSE_CENTER)
	mover.allow_door = false
	body.visible = true
	_bob = 0.0
	_release_left = 1.2

func _process(delta: float) -> void:
	if mover == null:
		return
	_bob += delta if state == State.IN_HOUSE else 0.0
	_sync_visual()
	_sync_appearance()

func _sync_visual() -> void:
	var pos := mover.world_position()
	var hover := sin(_bob * 4.0) * 0.07 if state == State.IN_HOUSE else 0.0
	position = Vector3(pos.x, VISUAL_Y + hover, pos.z)
	if mover.dir != Vector2i.ZERO:
		_facing = mover.dir
	var looked := Vector3(_facing.x, 0.0, _facing.y)
	visual.rotation.y = atan2(-looked.z, looked.x)

func _sync_appearance() -> void:
	if state == State.EATEN:
		body.material_override = _body_mat
		return
	var frightened := _frightened()
	var mat := _body_mat
	if frightened:
		var ending: bool = game.frightened_left < 2.0
		var blink := int(game.frightened_left * 6.0) % 2 == 0
		mat = _flash_mat if ending and blink else _fright_mat
	body.material_override = mat
	_pupils_visible(not frightened)

func _pupils_visible(shown: bool) -> void:
	for p in _pupils:
		p.visible = shown

func _frightened() -> bool:
	return game != null and game.is_frightened()

func _house_cell() -> Vector2i:
	match personality:
		Personality.PINKY:
			return Vector2i(13, 13)
		Personality.INKY:
			return Vector2i(11, 13)
		Personality.CLYDE:
			return Vector2i(16, 13)
		_:
			return MazeData.HOUSE_EXIT

func _release_delay() -> float:
	match personality:
		Personality.PINKY:
			return 1.5
		Personality.INKY:
			return 4.0
		Personality.CLYDE:
			return 7.0
		_:
			return 0.0

func _blinky_cell() -> Vector2i:
	if game != null:
		for g in game.ghosts:
			if g.personality == Personality.BLINKY:
				return g.mover.cell
	return MazeData.HOUSE_EXIT

static func _dist2(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return d.x * d.x + d.y * d.y

func _build_materials() -> void:
	_body_mat = _make_material(tint)
	_fright_mat = _make_material(Color(0.45, 0.58, 1.0))
	_flash_mat = _make_material(Color(1.0, 1.0, 1.0))

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = color * 0.25
	return mat

func _build_face() -> void:
	_face = $Visual/Face
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.13
	eye_mesh.height = 0.22
	var white := _make_material(Color(0.96, 0.96, 0.98))
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.06
	pupil_mesh.height = 0.1
	var pupil_mat := _make_material(Color(0.05, 0.08, 0.5))
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = white
		eye.position = Vector3(0.33, 0.15, 0.17 * side)
		_face.add_child(eye)
		var pupil := MeshInstance3D.new()
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(0.44, 0.15, 0.17 * side)
		_face.add_child(pupil)
		_pupils.append(pupil)
