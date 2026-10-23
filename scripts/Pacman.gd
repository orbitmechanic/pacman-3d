class_name Pacman
extends Node3D

## Pac-Man: input buffering, tile movement via GridMover, chomp presentation.
## Mouth is a sphere wedge: SphereMesh's phi sweep leaves a gap that faces the
## direction of travel.

signal arrived(cell: Vector2i)

const RADIUS := 0.46
const BODY_Y := 0.48
const MOUTH_GAP_MAX := 120.0
const CHOMP_RATE := 16.0

@onready var body: MeshInstance3D = $Body

var mover: GridMover
var desired_dir := Vector2i.ZERO

var _chomp := 0.0
var _gap := 0.0

func _ready() -> void:
	mover = GridMover.new(MazeData.PAC_SPAWN)
	mover.decide = _decide
	mover.arrived.connect(_on_mover_arrived)
	body.mesh = PacMesh.build(RADIUS, 0.0)
	body.position.y = BODY_Y
	_add_eyes()
	position = mover.world_position()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("move_up"):
		steer(Vector2i.UP)
	elif Input.is_action_just_pressed("move_down"):
		steer(Vector2i.DOWN)
	elif Input.is_action_just_pressed("move_left"):
		steer(Vector2i.LEFT)
	elif Input.is_action_just_pressed("move_right"):
		steer(Vector2i.RIGHT)
	mover.tick(delta)

func _process(delta: float) -> void:
	position = mover.world_position()
	_face_travel()
	_chomp_step(delta)

## Public so probes and attract mode can drive Pac-Man without a keyboard.
func steer(direction: Vector2i) -> void:
	desired_dir = direction
	mover.request(direction)

func _decide(at: Vector2i) -> Vector2i:
	if desired_dir != Vector2i.ZERO and MazeData.is_walkable(at + desired_dir):
		return desired_dir
	if mover.dir != Vector2i.ZERO and MazeData.is_walkable(at + mover.dir):
		return mover.dir
	return Vector2i.ZERO

func _on_mover_arrived(cell: Vector2i) -> void:
	arrived.emit(cell)

func _face_travel() -> void:
	if mover.dir == Vector2i.ZERO:
		return
	var looked := Vector3(mover.dir.x, 0.0, mover.dir.y)
	# Wedge gap starts along local +X; yaw it onto the travel direction.
	body.rotation.y = atan2(-looked.z, looked.x)

func _chomp_step(delta: float) -> void:
	var target := 0.0
	if mover.is_moving():
		_chomp += delta * CHOMP_RATE
		target = (0.5 - 0.5 * cos(_chomp)) * MOUTH_GAP_MAX
	if absf(target - _gap) > 1.0:
		_gap = target
		body.mesh = PacMesh.build(RADIUS, _gap)

func _add_eyes() -> void:
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.075
	eye_mesh.height = 0.13
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.04)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = mat
		eye.position = Vector3(0.33, 0.24, 0.17 * side)
		body.add_child(eye)
