extends Node
## 背景音乐（路线图 M.1；TECH.md 4.24）。按区域和时段放曲子（data/music.json），换曲子时交叉淡入淡出 2 秒；
## 走「Music」总线，音量和开关在暂停菜单里（Settings.music、music_volume；「声音」关了音乐也关）。暂停时照样放。
## 曲子都是 tools/compose_music.py 代码作曲合成的原创曲（assets/SOURCES.md）。

const PATH := "res://data/music.json"
const BUS := "Music"
const FADE := 2.0
const SILENT_DB := -60.0

var data := {}
var players: Array[AudioStreamPlayer] = []
var tweens: Array = [null, null]       # 每个播放器正在跑的淡入 / 淡出（换回来时先停掉，不然没跑完的淡出会把新曲子停掉）
var active := 0
var track := ""                      # 现在放的曲目编号（"" = 没放）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	data = d if d is Dictionary else {}
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENT_DB
		add_child(p)
		players.append(p)
	Settings.changed.connect(apply_volume)
	apply_volume()


## 这个区域、这个时段放哪首（没有就 ""）
func track_for(area: String, daypart: String) -> String:
	var a: Variant = data.get("areas", {}).get(area, "")
	if a is Dictionary:
		return str(a.get(daypart, a.get("*", "")))
	return str(a)


func play_area(area: String) -> void:
	play(track_for(area, GameState.daypart))


## 换曲子：新的从无声淡进来，旧的淡出去再停；同一首不重放（换区域时接着放）
func play(id: String) -> void:
	if id == track:
		return
	track = id
	var old := players[active]
	if old.playing:
		_kill(active)
		var tw := create_tween()
		tw.tween_property(old, "volume_db", SILENT_DB, FADE)
		tw.tween_callback(old.stop)
		tweens[active] = tw
	if id == "":
		print("IC_MUSIC track=none")
		return
	var path := str(data.get("tracks", {}).get(id, ""))
	var stream := load(path) as AudioStreamOggVorbis if path != "" else null
	if stream == null:
		push_warning("背景音乐打不开：%s" % path)
		track = ""
		return
	stream.loop = true
	active = 1 - active
	_kill(active)
	var p := players[active]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	tweens[active] = create_tween()
	tweens[active].tween_property(p, "volume_db", 0.0, FADE)
	print("IC_MUSIC track=%s" % id)


func _kill(i: int) -> void:
	if tweens[i] != null and (tweens[i] as Tween).is_valid():
		(tweens[i] as Tween).kill()
	tweens[i] = null


## 马上停（不淡出）、放掉曲子（测试退出前用；音频服务器要过一两帧才放掉播放对象）
func stop_now() -> void:
	track = ""
	for i in players.size():
		_kill(i)
		players[i].stop()
		players[i].stream = null


func _exit_tree() -> void:
	stop_now()


## 音量：总线音量 = 设置里的音乐音量；「声音」或「背景音乐」关了就静音
func apply_volume() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var on := Settings.sound and Settings.music and Settings.music_volume > 0.001
	AudioServer.set_bus_mute(i, not on)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(Settings.music_volume, 0.001)))
