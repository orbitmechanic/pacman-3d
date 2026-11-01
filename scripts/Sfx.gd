class_name Sfx
extends Node

## Procedural sound: every effect is synthesised into an `AudioStreamWAV` at
## start-up, so the project keeps its no-binary-assets rule and the web `.pck`
## stays tiny. The node listens to `Game` signals; gameplay never calls into
## audio directly, which keeps the rules headless-testable with no mixer.
##
## The browser will not start audio before a user gesture, so the siren only
## begins once a run starts (Enter, tap, or gamepad) - exactly the interactive
## moment browsers allow.

const RATE := 22050
const VOICES := 8
const WAVE_SQUARE := 0
const WAVE_TRIANGLE := 1
const WAVE_SINE := 2
const WAVE_SAW := 3

## Every synthesised stream, keyed by name. Public so probes can assert that
## the whole bank was built without opening an audio device.
var streams: Dictionary = {}

var _game: Game
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _siren: AudioStreamPlayer
var _fright_loop: AudioStreamPlayer
var _chomp_high := true

func _ready() -> void:
	_build_streams()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		voice.volume_db = -3.0
		add_child(voice)
		_voices.append(voice)
	# Dedicated players keep the two background loops independent of the
	# one-shot voice pool (and of each other while frightened).
	_siren = _make_player("siren", -19.0)
	_fright_loop = _make_player("fright_loop", -16.0)

## Wire the controller signals. Idempotent so probes can re-bind freely.
func bind(game: Game) -> void:
	if _game != null:
		var old := _game
		for connection in [
			[old.dot_eaten, _on_dot_eaten],
			[old.pellet_eaten, _on_pellet_eaten],
			[old.ghost_eaten, _on_ghost_eaten],
			[old.state_changed, _on_state_changed],
			[old.frightened_changed, _on_frightened_changed],
			[old.paused_changed, _on_paused_changed],
		]:
			var sig: Signal = connection[0]
			var callable: Callable = connection[1]
			if sig.is_connected(callable):
				sig.disconnect(callable)
	_game = game
	game.dot_eaten.connect(_on_dot_eaten)
	game.pellet_eaten.connect(_on_pellet_eaten)
	game.ghost_eaten.connect(_on_ghost_eaten)
	game.state_changed.connect(_on_state_changed)
	game.frightened_changed.connect(_on_frightened_changed)
	game.paused_changed.connect(_on_paused_changed)
	_sync_loops()

## How many one-shot voices are currently audible; used by the probe.
func active_voices() -> int:
	var count := 0
	for voice in _voices:
		if voice.playing:
			count += 1
	return count

func _play(name: String, volume_db := -3.0, pitch := 1.0) -> void:
	var stream: AudioStream = streams.get(name)
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()

func _on_dot_eaten() -> void:
	# Alternating two-tone chomp, the arcade "waka".
	_chomp_high = not _chomp_high
	_play("chomp_high" if _chomp_high else "chomp_low", -8.0)

func _on_pellet_eaten() -> void:
	_play("pellet", -4.0)

func _on_ghost_eaten(points: int) -> void:
	var pitch := clampf(1.0 + 0.06 * (points / 200 - 1), 1.0, 1.25)
	_play("ghost_eaten", -4.0, pitch)

func _on_state_changed(state: int) -> void:
	match state:
		Game.State.TITLE:
			_stop_loops()
		Game.State.READY:
			_stop_loops()
			_play("ready", -8.0)
		Game.State.PLAYING:
			_sync_loops()
		Game.State.DYING:
			_stop_loops()
			_play("death", -2.0)
		Game.State.LEVEL_CLEAR:
			_stop_loops()
			_play("level_clear", -3.0)
		Game.State.GAME_OVER:
			_stop_loops()
			_play("game_over", -2.0)

func _on_frightened_changed(_active: bool) -> void:
	_sync_loops()

func _on_paused_changed(_paused: bool) -> void:
	_sync_loops()

## Siren while playing, frightened wail while the power window is open, and
## silence for every other state (title, pause, death, clear, game over).
func _sync_loops() -> void:
	if _game == null or _game.state != Game.State.PLAYING or _game.paused:
		_stop_loops()
		return
	if _game.is_frightened():
		if _siren.playing:
			_siren.stop()
		if not _fright_loop.playing:
			_fright_loop.pitch_scale = 1.0 + 0.04 * float(mini(_game.level, 5) - 1)
			_fright_loop.play()
	else:
		if _fright_loop.playing:
			_fright_loop.stop()
		if not _siren.playing:
			_siren.pitch_scale = clampf(0.94 + 0.05 * float(_game.level - 1), 0.94, 1.3)
			_siren.play()

func _stop_loops() -> void:
	if _siren != null and _siren.playing:
		_siren.stop()
	if _fright_loop != null and _fright_loop.playing:
		_fright_loop.stop()

## Release the audio server's playbacks before the tree goes away. Without
## this, a headless probe that quits mid-chomp reports leaked WAV playbacks
## even though the node itself is freed.
func _exit_tree() -> void:
	for voice in _voices:
		voice.stop()
		voice.stream = null
	for player in [_siren, _fright_loop]:
		if player != null:
			player.stop()
			player.stream = null
	streams.clear()

func _make_player(name: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = name
	player.stream = streams.get(name)
	player.volume_db = volume_db
	add_child(player)
	return player

func _build_streams() -> void:
	streams["chomp_high"] = build_wav(_sweep(520.0, 250.0, 0.085, WAVE_SQUARE, 0.34, 0.0, 0.0, 1.4))
	streams["chomp_low"] = build_wav(_sweep(250.0, 520.0, 0.085, WAVE_SQUARE, 0.34, 0.0, 0.0, 1.4))
	streams["pellet"] = build_wav(_sweep(180.0, 920.0, 0.36, WAVE_SAW, 0.28, 18.0, 0.16, 1.0))
	streams["ghost_eaten"] = build_wav(_arpeggio([659.0, 880.0, 1319.0], 0.055, WAVE_SQUARE, 0.26))
	streams["death"] = build_wav(_sweep(620.0, 70.0, 1.05, WAVE_SAW, 0.32, 11.0, 0.14, 0.35))
	streams["level_clear"] = build_wav(_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.11, WAVE_TRIANGLE, 0.28))
	streams["ready"] = build_wav(_arpeggio([523.0, 659.0, 784.0], 0.075, WAVE_TRIANGLE, 0.24))
	streams["game_over"] = build_wav(_arpeggio([392.0, 330.0, 262.0, 196.0], 0.17, WAVE_SAW, 0.26))
	# Both loops start and end in a short silence, so the loop seam is silent
	# even though the oscillator phase is not continuous across it.
	streams["siren"] = build_wav(_siren_pattern(), true)
	streams["fright_loop"] = build_wav(_fright_pattern(), true)

## One siren cycle: two wailing sweeps separated by gaps.
func _siren_pattern() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append_array(_sweep(720.0, 480.0, 0.46, WAVE_TRIANGLE, 0.22, 5.0, 0.05, 0.1))
	out.append_array(_silence(0.09))
	out.append_array(_sweep(480.0, 720.0, 0.46, WAVE_TRIANGLE, 0.22, 5.0, 0.05, 0.1))
	out.append_array(_silence(0.09))
	return out

## The frightened wail: quick low pulses with a little wobble.
func _fright_pattern() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 3:
		out.append_array(_sweep(300.0, 210.0, 0.16, WAVE_SQUARE, 0.18, 22.0, 0.08, 0.2))
		out.append_array(_silence(0.07))
	return out

static func _sweep(
	start_hz: float,
	end_hz: float,
	duration: float,
	wave: int,
	gain: float,
	vibrato_hz := 0.0,
	vibrato_depth := 0.0,
	decay := 1.0
) -> PackedFloat32Array:
	var count := int(RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / duration
		var hz := lerpf(start_hz, end_hz, k)
		if vibrato_hz > 0.0:
			hz *= 1.0 + vibrato_depth * sin(TAU * vibrato_hz * t)
		phase = fposmod(phase + hz / RATE, 1.0)
		var attack := minf(1.0, t / 0.006)
		var envelope := attack * pow(maxf(0.0, 1.0 - k), decay)
		samples[i] = _osc(wave, phase) * gain * envelope
	return samples

static func _arpeggio(freqs: Array, note_seconds: float, wave: int, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for hz: float in freqs:
		out.append_array(_sweep(hz, hz, note_seconds, wave, gain, 0.0, 0.0, 0.6))
		out.append_array(_silence(0.012))
	return out

static func _silence(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * seconds))
	return samples

static func _osc(wave: int, phase: float) -> float:
	match wave:
		WAVE_TRIANGLE:
			return 1.0 - 4.0 * absf(phase - 0.5)
		WAVE_SINE:
			return sin(TAU * phase)
		WAVE_SAW:
			return 2.0 * phase - 1.0
		_:
			return 1.0 if phase < 0.5 else -1.0

## 16-bit mono PCM. `loop` marks the stream to repeat seamlessly; the source
## patterns already end in silence so the seam never clicks.
static func build_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
