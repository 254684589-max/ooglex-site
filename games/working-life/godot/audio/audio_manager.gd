extends Node
## 音频管理（自动加载名：AudioManager）。
## 总线：Master / Music / SFX / Ambience。背景音乐、城市环境声、商店 / 办公室环境声、雨声、
## 界面音效、脚步声、交互音效都通过这里播放。
## 素材按约定放在 res://assets/audio/：music_<id>.wav、amb_<id>.wav、sfx_<id>.wav。
## 缺少的素材会被静默跳过（不会报错），以后替换成正式音频只需要覆盖同名文件。

const DIR := "res://assets/audio/"
const SFX_POOL := 8

var _music: AudioStreamPlayer
var _amb: Array = []
var _amb_ids: Array = ["", ""]
var _sfx: Array = []
var _sfx_next := 0
var _cache: Dictionary = {}
var _music_id := ""
var _step_toggle := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(func(): if _music.stream != null: _music.play())
	add_child(_music)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.finished.connect(_loop_amb.bind(i))
		add_child(p)
		_amb.append(p)
	for i in SFX_POOL:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		add_child(s)
		_sfx.append(s)
	apply_volumes()


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[name] = s
	return s


func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 1.0))


func apply_volumes() -> void:
	var sm := SettingsManager
	AudioServer.set_bus_volume_db(0, _db(float(sm.get_v("master", 0.9))))
	var pairs := {"Music": "music", "SFX": "sfx", "Ambience": "ambience"}
	for bus in pairs:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, _db(float(sm.get_v(pairs[bus], 0.7))))


func play_sfx(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _stream("sfx_" + id)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func footstep(running: bool) -> void:
	_step_toggle = not _step_toggle
	play_sfx("step", -14.0 if not running else -10.0, (1.05 if _step_toggle else 0.95) * (1.1 if running else 1.0))


func play_music(id: String) -> void:
	if id == _music_id:
		return
	_music_id = id
	var s := _stream("music_" + id) if id != "" else null
	_music.stream = s
	if s != null:
		_music.play()
	else:
		_music.stop()


## 环境声两层：layer 0 = 城市 / 室内，layer 1 = 雨声
func set_ambience(layer: int, id: String) -> void:
	if layer < 0 or layer > 1 or _amb_ids[layer] == id:
		return
	_amb_ids[layer] = id
	var p: AudioStreamPlayer = _amb[layer]
	var s := _stream("amb_" + id) if id != "" else null
	p.stream = s
	if s != null:
		p.play()
	else:
		p.stop()


func _loop_amb(i: int) -> void:
	var p: AudioStreamPlayer = _amb[i]
	if p.stream != null:
		p.play()


func _exit_tree() -> void:
	shutdown()


## 退出时释放所有音频流（主场景退出时调用一次，自动加载退出时再兜底一次）
func shutdown() -> void:
	stop_all()
	for p in _sfx:
		(p as AudioStreamPlayer).stream = null
	for p in _amb:
		(p as AudioStreamPlayer).stream = null
	_music.stream = null
	_cache.clear()


func stop_all() -> void:
	_music.stop()
	_music_id = ""
	for i in 2:
		_amb[i].stop()
		_amb_ids[i] = ""
