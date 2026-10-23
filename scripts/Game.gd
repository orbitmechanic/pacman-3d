class_name Game
extends Node

## Gameplay controller and state machine: title → ready → playing → dying /
## level clear → game over. Owns score, levels, the power-pellet frightened
## window, scatter/chase waves, collisions and lives. Ghost actors own their
## own steering; this node owns everything shared and every rule that spans
## more than one actor.

signal score_changed(score: int)
signal level_changed(level: int)
signal frightened_changed(active: bool)
signal lives_changed(lives: int)
signal ghost_mode_changed(mode: int)
signal ghost_eaten(points: int)
signal state_changed(state: int)
signal game_over

enum GhostMode { SCATTER, CHASE }
enum State { TITLE, READY, PLAYING, DYING, LEVEL_CLEAR, GAME_OVER }

const DOT_SCORE := 10
const PELLET_SCORE := 50
const FRIGHTENED_SECONDS := 6.0
const START_LIVES := 3
const DEATH_SECONDS := 1.2
const READY_SECONDS := 2.0
const LEVEL_CLEAR_SECONDS := 1.8
const GHOST_CHAIN := [200, 400, 800, 1600]
## Scatter/chase alternation in seconds; after the list runs out it stays chase.
const WAVE_DURATIONS := [7.0, 20.0, 7.0, 20.0, 5.0, 20.0, 5.0]
const SPEED_STEP := 0.06
const MAX_SPEED_SCALE := 1.35

var score := 0
var level := 1
var lives := START_LIVES
var frightened_left := 0.0
var ghost_mode: GhostMode = GhostMode.SCATTER
var state: State = State.TITLE

var pac: Pacman
var maze: MazeView
var ghosts: Array[Ghost] = []

var _wave := 0
var _wave_left: float = WAVE_DURATIONS[0]
var _ready_left := 0.0
var _death_left := 0.0
var _clear_left := 0.0
var _chain := 0

func setup(pac_node: Pacman, maze_node: MazeView, ghost_nodes: Array[Ghost]) -> void:
	pac = pac_node
	maze = maze_node
	ghosts = ghost_nodes
	pac.arrived.connect(_on_pac_arrived)
	for g in ghosts:
		g.setup(self, pac)
	state = State.TITLE
	_freeze_all(true)
	lives_changed.emit(lives)
	state_changed.emit(state)

## New run from the title screen or the game-over prompt. Also the restart
## path used by tests and the attract-mode demo.
func start_game() -> void:
	score = 0
	level = 1
	lives = START_LIVES
	frightened_left = 0.0
	_chain = 0
	maze.reset_food()
	pac.respawn()
	for g in ghosts:
		g.reset_to_spawn()
	_reset_waves()
	_apply_speeds()
	score_changed.emit(score)
	level_changed.emit(level)
	lives_changed.emit(lives)
	_enter_ready(READY_SECONDS)

func is_frightened() -> bool:
	return frightened_left > 0.0

## Movement speed multiplier for level `level`; later levels play faster.
func speed_scale() -> float:
	return minf(1.0 + SPEED_STEP * (level - 1), MAX_SPEED_SCALE)

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
		State.READY:
			_ready_left -= delta
			if _ready_left <= 0.0:
				_enter_playing()
		State.PLAYING:
			_tick_frightened(delta)
			_tick_waves(delta)
		State.DYING:
			_death_left -= delta
			if _death_left <= 0.0:
				_finish_death()
		State.LEVEL_CLEAR:
			_clear_left -= delta
			if _clear_left <= 0.0:
				_begin_next_level()

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
			lose_life()
		return

## One life gone: freeze the board, animate Pac-Man, then respawn or end.
func lose_life() -> void:
	if state != State.PLAYING:
		return
	lives -= 1
	lives_changed.emit(lives)
	state = State.DYING
	_death_left = DEATH_SECONDS
	_chain = 0
	if frightened_left > 0.0:
		frightened_left = 0.0
		frightened_changed.emit(false)
	pac.mover.frozen = true
	pac.play_death()
	state_changed.emit(state)

## Board cleared: hold on the flashing maze before the next level starts.
func begin_level_clear() -> void:
	if state != State.PLAYING:
		return
	state = State.LEVEL_CLEAR
	_clear_left = LEVEL_CLEAR_SECONDS
	if frightened_left > 0.0:
		frightened_left = 0.0
		frightened_changed.emit(false)
	_chain = 0
	_freeze_all(true)
	state_changed.emit(state)

func _enter_ready(seconds: float) -> void:
	state = State.READY
	_ready_left = seconds
	_freeze_all(true)
	state_changed.emit(state)

func _enter_playing() -> void:
	state = State.PLAYING
	_freeze_all(false)
	state_changed.emit(state)

func _finish_death() -> void:
	if lives <= 0:
		state = State.GAME_OVER
		state_changed.emit(state)
		game_over.emit()
		return
	pac.respawn()
	for g in ghosts:
		g.reset_to_spawn()
	_reset_waves()
	_apply_speeds()
	_enter_ready(READY_SECONDS)

func _begin_next_level() -> void:
	level += 1
	maze.reset_food()
	pac.respawn()
	for g in ghosts:
		g.reset_to_spawn()
	_reset_waves()
	_apply_speeds()
	level_changed.emit(level)
	_enter_ready(READY_SECONDS)

func _on_pac_arrived(cell: Vector2i) -> void:
	if state != State.PLAYING:
		return
	if maze.eat_dot(cell):
		_add_score(DOT_SCORE)
	elif maze.eat_pellet(cell):
		_add_score(PELLET_SCORE)
		_frighten()

	if maze.food_remaining() == 0:
		begin_level_clear()

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

func _add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func _reset_waves() -> void:
	ghost_mode = GhostMode.SCATTER
	_wave = 0
	_wave_left = WAVE_DURATIONS[0]
	ghost_mode_changed.emit(ghost_mode)

func _apply_speeds() -> void:
	var scale := speed_scale()
	pac.mover.tiles_per_second = Pacman.BASE_SPEED * scale
	for g in ghosts:
		g.speed_scale = scale

func _freeze_all(frozen: bool) -> void:
	pac.mover.frozen = frozen
	for g in ghosts:
		g.mover.frozen = frozen
