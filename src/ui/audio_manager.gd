class_name AudioManager
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const SFX_POOL := 3
const BUS_NAMES := ["Music", "Ambience", "SFX", "UI"]
const BUS_VOLUMES := {"Music": 0.7, "Ambience": 0.5, "SFX": 0.8, "UI": 0.7}

var _ui_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index := 0
var _cache: Dictionary = {}
var _muted := false
var _volumes: Dictionary = BUS_VOLUMES.duplicate()
var _last_played: Dictionary = {}
var _last_group: Dictionary = {}
const REPEAT_WINDOW_MS := 180


func _ready() -> void:
	_ensure_ready()


func _exit_tree() -> void:
	if is_instance_valid(_ui_player):
		_ui_player.stop()
		_ui_player.stream = null
	for player in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_cache.clear()


func _ensure_ready() -> void:
	_ensure_buses()
	if _ui_player != null:
		return
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "UI"
	add_child(_ui_player)
	for _index in SFX_POOL:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)


func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			index = AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		AudioServer.set_bus_volume_db(index, linear_to_db(float(_volumes.get(bus_name, 1.0))))


func play_ui(id: String) -> bool:
	_ensure_ready()
	return _play(_ui_player, id)


func play_sfx(id: String, pitch: float = 1.0) -> bool:
	if not is_inside_tree():
		return false
	_ensure_ready()
	if _muted or _sfx_players.is_empty():
		return false
	var stream := _load_sfx(id)
	if stream == null:
		return false
	if not _allow_sound(id):
		return false
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	if id in ["victory", "defeat", "choice"]:
		for playing in _sfx_players:
			playing.stop()
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.5, 2.0)
	player.play()
	return true


func play_deadline(remaining: int) -> bool:
	return play_sfx("ddl", 0.6 if remaining <= 1 else (0.8 if remaining <= 3 else 1.0))


func play_event(event_type: String) -> bool:
	var id := event_sfx(event_type)
	return play_sfx(id) if not id.is_empty() else false


func event_sfx(event_type: String) -> String:
	match event_type:
		"card_drawn":
			return "card_draw"
		"card_played":
			return "card_play"
		"card_discarded":
			return "card_discard"
		"card_exhausted":
			return "card_exhaust"
		"status_gained", "status_changed", "status_removed":
			return ""
		"pressure_applied", "task_summoned", "task_transformed", "task_self_destructed":
			return "task_hit"
		"task_advanced":
			return "chapter"
		"task_completed":
			return "task_done"
		"ddl_ticked", "deadline_expired":
			return "ddl"
		"paper_progress_gained", "paper_cited", "paper_published":
			return "paper"
		"chapter_deployed", "chapter_ran", "chapter_returned", "chapter_slots_swapped":
			return "chapter"
		"choice_requested":
			return "choice"
		"unit_entered", "unit_summoned", "unit_replaced", "unit_left", "ally_target_changed":
			return "chapter"
		"reward_claimed", "year_reward_created", "campaign_reward_claimed", "item_purchased", "card_upgraded":
			return "task_done"
		"battle_finished":
			return "victory"
		"battle_lost":
			return "defeat"
		_:
			return ""


func set_muted(value: bool) -> void:
	_ensure_buses()
	_muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), value)


func is_muted() -> bool:
	return _muted


func set_bus_volume(bus_name: String, linear: float) -> void:
	if bus_name not in ["Master"] + BUS_NAMES:
		return
	_volumes[bus_name] = clampf(linear, 0.0, 1.0)
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, float(_volumes[bus_name]))))


func get_bus_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 1.0))


func _play(player: AudioStreamPlayer, id: String) -> bool:
	if _muted or not is_inside_tree() or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var stream := _load_sfx(id)
	if stream == null:
		return false
	if not _allow_sound(id):
		return false
	player.stream = stream
	player.play()
	return true


func _allow_sound(id: String) -> bool:
	if id == "ui_hover":
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -10000)) < REPEAT_WINDOW_MS:
		return false
	var group := "important" if id in ["victory", "defeat", "choice", "error", "task_done"] else ("ui" if id.begins_with("ui_") or id == "detail_open" else "battle")
	var quiet_window := 80 if group == "ui" else 160
	if group != "important" and (now - int(_last_group.get(group, -10000)) < quiet_window or now - int(_last_group.get("important", -10000)) < 220):
		return false
	_last_played[id] = now
	_last_group[group] = now
	return true


func apply_settings(settings: Dictionary) -> void:
	_ensure_buses()
	for bus in ["Master"] + BUS_NAMES:
		set_bus_volume(bus, int(settings.get(bus, 100)) / 100.0)
	set_muted(bool(settings.get("muted", false)))


func _load_sfx(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	var path := SFX_DIR + id + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	_cache[id] = stream
	return stream
