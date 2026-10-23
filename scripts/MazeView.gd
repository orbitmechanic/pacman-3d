class_name MazeView
extends Node3D

## Builds the 3D board from MazeData: floor, one instanced draw call of wall
## boxes, dot/pellet meshes. Pure presentation - no game logic here.

const WALL_HEIGHT := 0.85
const DOT_Y := 0.35
const PELLET_Y := 0.5

var dots: Node3D
var pellets: Node3D
var _pellet_nodes: Array[MeshInstance3D] = []

func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_dots()
	_build_pellets()

func _process(time: float) -> void:
	# Gentle always-on pulse for power pellets; presentation only.
	var pulse := 1.0 + 0.15 * sin(time * 4.0)
	for node in _pellet_nodes:
		node.scale = Vector3.ONE * pulse

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
	var wall_cells := MazeData.wall_cells()
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
	for cell in wall_cells:
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

func _build_dots() -> void:
	dots = Node3D.new()
	dots.name = "Dots"
	add_child(dots)
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := _dot_material(Color(0.99, 0.8, 0.75), Color(0.6, 0.35, 0.3))
	for cell in MazeData.dot_cells():
		dots.add_child(_food_node(mesh, mat, cell, DOT_Y))

func _build_pellets() -> void:
	pellets = Node3D.new()
	pellets.name = "Pellets"
	add_child(pellets)
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 12
	mesh.rings = 6
	var mat := _dot_material(Color(1.0, 0.9, 0.4), Color(0.8, 0.6, 0.1))
	for cell in MazeData.pellet_cells():
		var node := _food_node(mesh, mat, cell, PELLET_Y)
		pellets.add_child(node)
		_pellet_nodes.append(node)

static func _food_node(mesh: Mesh, mat: Material, cell: Vector2i, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = MazeData.tile_to_world(cell) + Vector3(0.0, y, 0.0)
	return mi

static func _dot_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.8
	return mat
