class_name Game
extends Node

## Gameplay controller: score, level progression, and the power-pellet
## frightened window that the ghost actors will consume in a later PR.

signal score_changed(score: int)
signal level_changed(level: int)
signal frightened_changed(active: bool)

const DOT_SCORE := 10
const PELLET_SCORE := 50
const FRIGHTENED_SECONDS := 6.0

var score := 0
var level := 1
var frightened_left := 0.0

var pac: Pacman
var maze: MazeView

func setup(pac_node: Pacman, maze_node: MazeView) -> void:
	pac = pac_node
	maze = maze_node
	pac.arrived.connect(_on_pac_arrived)

func is_frightened() -> bool:
	return frightened_left > 0.0

func _process(delta: float) -> void:
	tick_timers(delta)

## Public so headless probes can advance timers deterministically.
func tick_timers(delta: float) -> void:
	if frightened_left <= 0.0:
		return
	frightened_left = maxf(0.0, frightened_left - delta)
	if frightened_left == 0.0:
		frightened_changed.emit(false)

func _on_pac_arrived(cell: Vector2i) -> void:
	if maze.eat_dot(cell):
		_add_score(DOT_SCORE)
	elif maze.eat_pellet(cell):
		_add_score(PELLET_SCORE)
		frightened_left = FRIGHTENED_SECONDS
		frightened_changed.emit(true)

	if maze.food_remaining() == 0:
		_advance_level()

func _add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func _advance_level() -> void:
	level += 1
	frightened_left = 0.0
	maze.reset_food()
	pac.respawn()
	level_changed.emit(level)
