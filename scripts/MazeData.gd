class_name MazeData
extends RefCounted

## Single source of truth for the board: 28x31 ASCII rows.
## Legend: '#' wall, '.' dot, 'o' power pellet, ',' open floor (no dot),
## '-' ghost-house door, ' ' void (outside the maze).
##
## Rows are built as left half + mirrored right half; validated headlessly by
## tests/MazeProbe.gd (palindrome, connectivity, pellet count).

const ROWS := [
	"############################",
	"#............##............#",
	"#.####.#####.##.#####.####.#",
	"#o####.#####.##.#####.####o#",
	"#.####.#####.##.#####.####.#",
	"#............##............#",
	"#.####.##.########.##.####.#",
	"#.####.##.########.##.####.#",
	"#......##....##....##......#",
	"######.#####.##.#####.######",
	"     #.#####,,,,#####.#     ",
	"     #.######--######.#     ",
	"     #.####,,,,,,####.#     ",
	"     #.####,,,,,,####.#     ",
	",,,,,,,####,,,,,,####,,,,,,,",
	"     #,##############,#     ",
	"     #,##############,#     ",
	"######,##############,######",
	"#..........................#",
	"#.####.#####.##.#####.####.#",
	"#.####.#####.##.#####.####.#",
	"#......##....##....##......#",
	"#.####.##.########.##.####.#",
	"#............,,............#",
	"#.####.##.########.##.####.#",
	"#.##.####.########.####.##.#",
	"#......##.########.##......#",
	"#o####.#####.##.#####.####o#",
	"#.####.#####.##.#####.####.#",
	"#..........................#",
	"############################",
]

const WALL := "#"
const DOT := "."
const PELLET := "o"
const OPEN := ","
const DOOR := "-"
const VOID := " "

const WIDTH := 28
const HEIGHT := 31
const TUNNEL_ROW := 14
const PAC_SPAWN := Vector2i(13, 23)
const HOUSE_EXIT := Vector2i(13, 10)

static func tile(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= HEIGHT:
		return WALL
	var col: int = wrapi(cell.x, 0, WIDTH)
	return ROWS[cell.y][col]

static func is_wall(cell: Vector2i) -> bool:
	var t := tile(cell)
	return t == WALL or t == VOID

static func is_walkable(cell: Vector2i, allow_door := false) -> bool:
	var t := tile(cell)
	if t == DOOR:
		return allow_door
	return not is_wall(cell)

static func wrap(cell: Vector2i) -> Vector2i:
	return Vector2i(wrapi(cell.x, 0, WIDTH), cell.y)

static func dot_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in HEIGHT:
		for col in WIDTH:
			if ROWS[row][col] == DOT:
				cells.append(Vector2i(col, row))
	return cells

static func pellet_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in HEIGHT:
		for col in WIDTH:
			if ROWS[row][col] == PELLET:
				cells.append(Vector2i(col, row))
	return cells

static func wall_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in HEIGHT:
		for col in WIDTH:
			if ROWS[row][col] == WALL:
				cells.append(Vector2i(col, row))
	return cells
