extends Node
## 全局短音效中心：统一音量、并发播放与高频事件节流。

const PLAYER_COUNT: int = 10
const COLLISION_COOLDOWN_MS: int = 110
const UI_COOLDOWN_MS: int = 55
const FOOTSTEP_COOLDOWN_MS: int = 150

const MUSIC_LEVEL = preload("res://assets/audio/music/omusubi_bouken.ogg")
const SFX_FOOTSTEP: AudioStream = preload("res://assets/audio/sfx/footstep_grass.ogg")
const SFX_BALL_IMPACT: AudioStream = preload("res://assets/audio/sfx/ball_impact.ogg")
const SFX_BALL_BURST: AudioStream = preload("res://assets/audio/sfx/ball_burst.ogg")
const SFX_GATE_BLOCKED: AudioStream = preload("res://assets/audio/sfx/gate_blocked.ogg")
const SFX_GATE_BREAK: AudioStream = preload("res://assets/audio/sfx/gate_break.ogg")
const SFX_LEVEL_CLEAR: AudioStream = preload("res://assets/audio/sfx/level_clear.ogg")
const SFX_UI_CLICK: AudioStream = preload("res://assets/audio/sfx/ui_click.ogg")
const SFX_UI_READY: AudioStream = preload("res://assets/audio/sfx/ui_ready.ogg")
const SFX_UI_ERROR: AudioStream = preload("res://assets/audio/sfx/ui_error.ogg")

var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer = null
var _music_tween: Tween = null
var _music_key: String = ""
var _next_player: int = 0
var _last_collision_ms: int = -1000
var _last_ui_ms: int = -1000
var _last_footstep_ms: Dictionary[int, int] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "BackgroundMusic"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	for i: int in PLAYER_COUNT:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % (i + 1)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)
	if not GameState.settings_changed.is_connected(_apply_master_volume):
		GameState.settings_changed.connect(_apply_master_volume)
	_apply_master_volume()

func _apply_master_volume() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var linear: float = clampf(GameState.master_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, linear <= 0.001)
	if linear > 0.001:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))

func play_footstep(slot: int) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_footstep_ms.get(slot, -1000) < FOOTSTEP_COOLDOWN_MS:
		return
	_last_footstep_ms[slot] = now
	var base_pitch: float = 0.94 if slot == 0 else 1.04
	_play(SFX_FOOTSTEP, -15.0, base_pitch + randf_range(-0.025, 0.025))

func play_ball_impact(strength: float, collision_category: String) -> void:
	# 门由明确的成功/失败判定发声，不能再叠一层普通碰撞。
	if collision_category == "breakable_gate":
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_collision_ms < COLLISION_COOLDOWN_MS:
		return
	_last_collision_ms = now
	var weight: float = clampf(inverse_lerp(90.0, 260.0, strength), 0.0, 1.0)
	_play(SFX_BALL_IMPACT, lerpf(-11.0, -3.0, weight), lerpf(1.08, 0.88, weight))

func play_gate_blocked() -> void:
	_play(SFX_GATE_BLOCKED, -4.0, randf_range(0.94, 1.0))

func play_gate_break() -> void:
	_play(SFX_GATE_BREAK, -1.0, randf_range(0.96, 1.03))

func play_ball_burst() -> void:
	_play(SFX_BALL_BURST, -1.0, randf_range(0.96, 1.02))

func play_level_clear() -> void:
	_play(SFX_LEVEL_CLEAR, -2.0, 1.0)

func play_ui_click() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ui_ms < UI_COOLDOWN_MS:
		return
	_last_ui_ms = now
	_play(SFX_UI_CLICK, -2.0, randf_range(0.99, 1.01))

func play_ui_ready() -> void:
	_play(SFX_UI_READY, -7.0, 1.0)

func play_ui_error() -> void:
	_play(SFX_UI_ERROR, -7.0, 1.0)

func start_level_music() -> void:
	_start_music("level", MUSIC_LEVEL, -20.0)

func _start_music(key: String, stream: AudioStream, target_db: float) -> void:
	if _music_player == null or stream == null:
		return
	if _music_key == key and _music_player.playing:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_player.stop()
	var playback_stream: AudioStream = stream
	if stream is AudioStreamOggVorbis:
		var loop_stream: AudioStreamOggVorbis = stream.duplicate() as AudioStreamOggVorbis
		loop_stream.loop = true
		playback_stream = loop_stream
	_music_key = key
	_music_player.stream = playback_stream
	_music_player.volume_db = target_db - 12.0
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func stop_level_music(fade_seconds: float = 0.4) -> void:
	if _music_key != "level":
		return
	stop_music(fade_seconds)

func stop_music(fade_seconds: float = 0.4) -> void:
	if _music_player == null or not _music_player.playing:
		return
	if _music_tween != null:
		_music_tween.kill()
	if fade_seconds <= 0.0:
		_music_player.stop()
		_music_key = ""
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -40.0, fade_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_music_tween.tween_callback(func() -> void:
		_music_player.stop()
		_music_key = ""
	)

func stop_all() -> void:
	if _music_tween != null:
		_music_tween.kill()
	if _music_player != null:
		_music_player.stop()
	_music_key = ""
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null

func _play(stream: AudioStream, volume_db: float, pitch_scale: float) -> void:
	if stream == null or GameState.master_volume <= 0.001 or _players.is_empty():
		return
	var player: AudioStreamPlayer = _find_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

func _find_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	return player

func _exit_tree() -> void:
	stop_all()
