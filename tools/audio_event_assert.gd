extends SceneTree
## 音效事件冒烟：资源可载入、门碰撞不双响、高频入口会更新节流状态。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio: Node = root.get_node_or_null("AudioHub")
	assert(audio != null, "AudioHub autoload missing")
	for path: String in [
		"res://assets/audio/music/omusubi_bouken.ogg",
		"res://assets/audio/sfx/footstep_grass.ogg",
		"res://assets/audio/sfx/ball_impact.ogg",
		"res://assets/audio/sfx/ball_burst.ogg",
		"res://assets/audio/sfx/gate_blocked.ogg",
		"res://assets/audio/sfx/gate_break.ogg",
		"res://assets/audio/sfx/level_clear.ogg",
		"res://assets/audio/sfx/ui_click.ogg",
		"res://assets/audio/sfx/ui_ready.ogg",
		"res://assets/audio/sfx/ui_error.ogg",
	]:
		assert(load(path) is AudioStream, "audio resource missing: %s" % path)

	audio.set("_last_collision_ms", -1000)
	audio.call("play_ball_impact", 220.0, "breakable_gate")
	assert(int(audio.get("_last_collision_ms")) == -1000, "gate collision must not double-play")
	audio.call("play_ball_impact", 220.0, "ordinary_obstacle")
	assert(int(audio.get("_last_collision_ms")) > 0, "ordinary collision did not reach AudioHub")

	audio.call("play_footstep", 0)
	assert((audio.get("_last_footstep_ms") as Dictionary).has(0), "footstep was not registered")
	audio.call("play_gate_blocked")
	audio.call("play_gate_break")
	audio.call("play_ball_burst")
	audio.call("play_level_clear")
	audio.call("play_ui_click")
	audio.call("play_ui_ready")
	audio.call("play_ui_error")
	assert((audio.get("_players") as Array).size() == 10, "SFX player pool size mismatch")
	var music_player: AudioStreamPlayer = audio.get("_music_player") as AudioStreamPlayer
	assert(music_player != null and not music_player.playing, "music must stay off before gameplay starts")
	audio.call("start_level_music")
	assert(music_player != null and music_player.playing, "level music did not start")
	assert(str(audio.get("_music_key")) == "level", "level music key mismatch")
	audio.call("stop_level_music", 0.0)
	assert(not music_player.playing, "level music did not stop")
	audio.call("stop_all")
	print("AUDIO_EVENT_ASSERT_OK")
	quit(0)
