class_name MazeView
extends Node3D

## Builds the 3D board from MazeData: floor, one instanced draw call of wall
## boxes, dot/pellet meshes. Also owns the remaining-food bookkeeping, since
## food removal is a view concern the game controller queries.

const WALL_HEIGHT := 0.85
const DOT_Y := 0.35
const PELLET_Y := 0.5

var dots: Node3D
var pellets: Node3D
var dots_left := 0
var pellets_left := 0

var _dot_nodes: Dictionary = {}
var _pellet_nodes: Dictionary = {}

func _ready() -> void:
	_build_floor()
	_build_walls()
	dots = Node3D.new()
	dots.name = "Dots"
	add_child(dots)
	pellets = Node3D.new()
	pellets.name = "Pellets"
	add_child(pellets)
	_respawn_food()

func _process(time: float) -> void:
	# Gentle always-on pulse for power pellets; presentation only.
	var pulse := 1.0 + 0.15 * sin(time * 4.0)
	for node in _pellet_nodes.values():
		node.scale = Vector3.ONE * pulse

func food_remaining() -> int:
	return dots_left + pellets_left

## Removes the dot on `cell`; returns true only if one was actually eaten,
## so callers can score exactly once per dot.
func eat_dot(cell: Vector2i) -> bool:
	var node: MeshInstance3D = _dot_nodes.get(cell)
	if node == null:
		return false
	_dot_nodes.erase(cell)
	node.queue_free()
	dots_left -= 1
	return true

func eat_pellet(cell: Vector2i) -> bool:
	var node: MeshInstance3D = _pellet_nodes.get(cell)
	if node == null:
		return false
	_pellet_nodes.erase(cell)
	node.queue_free()
	pellets_left -= 1
	return true

## Frees any remaining food and lays out a fresh board (next level).
func reset_food() -> void:
	for node in _dot_nodes.values():
		node.queue_free()
	for node in _pellet_nodes.values():
		node.queue_free()
	_dot_nodes.clear()
	_pellet_nodes.clear()
	_respawn_food()

func _respawn_food() -> void:
	dots_left = 0
	pellets_left = 0
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.09
	dot_mesh.height = 0.18
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	var dot_mat := _food_material(Color(0.99, 0.8, 0.75), Color(0.6, 0.35, 0.3))
	for cell in MazeData.dot_cells():
		var node := _food_node(dot_mesh, dot_mat, cell, DOT_Y)
		dots.add_child(node)
		_dot_nodes[cell] = node
		dots_left += 1

	var pellet_mesh := SphereMesh.new()
	pellet_mesh.radius = 0.22
	pellet_mesh.height = 0.44
	pellet_mesh.radial_segments = 12
	pellet_mesh.rings = 6
	var pellet_mat := _food_material(Color(1.0, 0.9, 0.4), Color(0.8, 0.6, 0.1))
	for cell in MazeData.pellet_cells():
		var node := _food_node(pellet_mesh, pellet_mat, cell, PELLET_Y)
		pellets.add_child(node)
		_pellet_nodes[cell] = node
		pellets_left += 1

func _build_floor() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.09)
	mat.roughness = 0.9
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(MazeData.WIDTH, MazeData.HEIGHT)
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = mat
	add_child(floor_mi)

func _build_walls() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.0, WALL_HEIGHT, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.09, 0.5)
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.11, 0.55)
	mat.emission_energy_multiplier = 0.6
	box.material = mat

	# Render only wall tiles that touch walkable space or the board edge:
	# wall bands become hollow outlines instead of solid blocks (classic look).
	var visible_walls: Array[Vector2i] = []
	for cell in MazeData.wall_cells():
		if _wall_is_visible(cell):
			visible_walls.append(cell)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = visible_walls.size()
	for i in visible_walls.size():
		var pos := MazeData.tile_to_world(visible_walls[i]) + Vector3(0.0, WALL_HEIGHT / 2.0, 0.0)
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walls"
	mmi.multimesh = multimesh
	add_child(mmi)

static func _wall_is_visible(cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := cell + Vector2i(dx, dy)
			if n.y < 0 or n.y >= MazeData.HEIGHT:
				return true
			if MazeData.is_walkable(n):
				return true
	return false

static func _food_node(mesh: Mesh, mat: Material, cell: Vector2i, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = MazeData.tile_to_world(cell) + Vector3(0.0, y, 0.0)
	return mi

static func _food_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.8
	return mat
