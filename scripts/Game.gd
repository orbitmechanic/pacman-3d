class_name Game
extends Node

## Gameplay controller: score, levels, the power-pellet frightened window,
## scatter/chase waves, collisions, lives and game over. Ghost actors own their
## own steering; this node owns everything shared and every rule that spans
## more than one actor.

signal score_changed(score: int)
signal level_changed(level: int)
signal frightened_changed(active: bool)
signal lives_changed(lives: int)
signal ghost_mode_changed(mode: int)
signal ghost_eaten(points: int)
signal game_over

enum GhostMode { SCATTER, CHASE }
enum State { PLAYING, DYING, GAME_OVER }

const DOT_SCORE := 10
const PELLET_SCORE := 50
const FRIGHTENED_SECONDS := 6.0
const START_LIVES := 3
const DEATH_SECONDS := 1.2
const GHOST_CHAIN := [200, 400, 800, 1600]
## Scatter/chase alternation in seconds; after the list runs out it stays chase.
const WAVE_DURATIONS := [7.0, 20.0, 7.0, 20.0, 5.0, 20.0, 5.0]

var score := 0
var level := 1
var lives := START_LIVES
var frightened_left := 0.0
var ghost_mode: GhostMode = GhostMode.SCATTER
var state: State = State.PLAYING

var pac: Pacman
var maze: MazeView
var ghosts: Array[Ghost] = []

var _wave := 0
var _wave_left: float = WAVE_DURATIONS[0]
var _death_left := 0.0
var _chain := 0

func setup(pac_node: Pacman, maze_node: MazeView, ghost_nodes: Array[Ghost]) -> void:
	pac = pac_node
	maze = maze_node
	ghosts = ghost_nodes
	pac.arrived.connect(_on_pac_arrived)
	for g in ghosts:
		g.setup(self, pac)
	lives_changed.emit(lives)

func is_frightened() -> bool:
	return frightened_left > 0.0

func _process(delta: float) -> void:
	tick_timers(delta)

func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	for g in ghosts:
		g.tick(delta)
	resolve_collisions()

## Public so headless probes can advance timers deterministically.
func tick_timers(delta: float) -> void:
	match state:
		State.DYING:
			_death_left -= delta
			if _death_left <= 0.0:
				_finish_death()
		State.PLAYING:
			_tick_frightened(delta)
			_tick_waves(delta)

func resolve_collisions() -> void:
	if state != State.PLAYING:
		return
	var pac_cell := pac.mover.nearest_cell()
	for g in ghosts:
		if g.state != Ghost.State.ROAMING:
			continue
		if g.mover.nearest_cell() != pac_cell:
			continue
		if is_frightened():
			_eat_ghost(g)
		else:
			_lose_life()
		return

func _tick_frightened(delta: float) -> void:
	if frightened_left <= 0.0:
		return
	frightened_left = maxf(0.0, frightened_left - delta)
	if frightened_left == 0.0:
		_chain = 0
		frightened_changed.emit(false)

func _tick_waves(delta: float) -> void:
	if is_frightened():
		return  # waves pause during a frightened window, like the arcade
	_wave_left -= delta
	if _wave_left > 0.0:
		return
	_wave += 1
	if _wave >= WAVE_DURATIONS.size():
		ghost_mode = GhostMode.CHASE
		_wave_left = INF
	else:
		ghost_mode = GhostMode.CHASE if _wave % 2 == 1 else GhostMode.SCATTER
		_wave_left = WAVE_DURATIONS[_wave]
	ghost_mode_changed.emit(ghost_mode)
	for g in ghosts:
		g.on_mode_changed()

func _on_pac_arrived(cell: Vector2i) -> void:
	if state != State.PLAYING:
		return
	if maze.eat_dot(cell):
		_add_score(DOT_SCORE)
	elif maze.eat_pellet(cell):
		_add_score(PELLET_SCORE)
		_frighten()

	if maze.food_remaining() == 0:
		_advance_level()

func _frighten() -> void:
	frightened_left = FRIGHTENED_SECONDS
	_chain = 0
	frightened_changed.emit(true)
	for g in ghosts:
		g.on_frightened_started()

func _eat_ghost(g: Ghost) -> void:
	var points: int = GHOST_CHAIN[mini(_chain, GHOST_CHAIN.size() - 1)]
	_chain += 1
	_add_score(points)
	g.get_eaten()
	ghost_eaten.emit(points)

func _lose_life() -> void:
	lives -= 1
	lives_changed.emit(lives)
	state = State.DYING
	_death_left = DEATH_SECONDS
	_chain = 0
	if frightened_left > 0.0:
		frightened_left = 0.0
		frightened_changed.emit(false)
	pac.mover.frozen = true

func _finish_death() -> void:
	if lives <= 0:
		state = State.GAME_OVER
		game_over.emit()
		return
	state = State.PLAYING
	pac.mover.frozen = false
	pac.respawn()
	for g in ghosts:
		g.reset_to_spawn()
	_reset_waves()

func _add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func _reset_waves() -> void:
	ghost_mode = GhostMode.SCATTER
	_wave = 0
	_wave_left = WAVE_DURATIONS[0]
	ghost_mode_changed.emit(ghost_mode)

func _advance_level() -> void:
	level += 1
	frightened_left = 0.0
	_chain = 0
	maze.reset_food()
	pac.respawn()
	for g in ghosts:
		g.reset_to_spawn()
	_reset_waves()
	level_changed.emit(level)
