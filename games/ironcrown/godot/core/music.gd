extends Node
## 背景音乐（路线图 M.1；TECH.md 4.24）。按区域和时段放曲子（data/music.json），换曲子时交叉淡入淡出 2 秒；
## 音量和开关在暂停菜单里（Settings.music、music_volume；「声音」关了音乐也关）。暂停时照样放。
## 曲子都是 tools/compose_music.py 代码作曲合成的原创曲（assets/SOURCES.md）。
## 不在运行时新建音频总线：网页版（不开线程，声音按「样本」交给浏览器放）在运行时加总线会把主总线的输出改接到新总线上，
## 主总线不再接到扬声器，整个游戏都没声音（2026-10-17 上线后所有者反馈「听不到音乐」，查出来连开场的钟声也没了）。
## 所以两个播放器都走主总线，音量和淡入淡出在播放器上算：volume_db = 淡入淡出系数 × 设置里的音乐音量。
## 网页上的样本不一定按曲子的循环标记循环，放完（finished）就从头再放。

const PATH := "res://data/music.json"
const FADE := 2.0
const SILENT_DB := -80.0

var data := {}
var players: Array[AudioStreamPlayer] = []
var fades: Array[float] = [0.0, 0.0]     # 每个播放器的淡入淡出系数 0..1（tween 改它，_process 换算成 volume_db）
var tweens: Array = [null, null]          # 每个播放器正在跑的淡入 / 淡出（换回来时先停掉，不然没跑完的淡出会把新曲子停掉）
var active := 0
var track := ""                           # 现在放的曲目编号（"" = 没放）
var fighting := false                     # 正在打（main 按 in_combat() 设）：放「battle」，打完回到区域的曲子
const CALM_DELAY := 4.0                   # 打完以后安静多少秒才换回去（免得敌人一会儿警觉一会儿不警觉，曲子来回切）
var _calm_left := 0.0
var _area := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	data = d if d is Dictionary else {}
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = SILENT_DB
		p.finished.connect(_on_finished.bind(k))
		add_child(p)
		players.append(p)
	Settings.changed.connect(apply_volume)


## 这个区域、这个时段放哪首（没有就 ""）
func track_for(area: String, daypart: String) -> String:
	var a: Variant = data.get("areas", {}).get(area, "")
	if a is Dictionary:
		return str(a.get(daypart, a.get("*", "")))
	return str(a)


func play_area(area: String) -> void:
	_area = area
	if fighting:
		return                            # 打着的时候不换（打完回来时再按区域和时段选）
	play(track_for(area, GameState.daypart))


## 战斗配乐（审查配乐与剧本：酒馆打架、桦林伏击、渡口对峙、营地都在打，原来放的还是安静的曲子）：
## main 每帧告诉这里在不在打。开打马上换「battle」；不打了等 CALM_DELAY 秒再换回区域的曲子。军阵试验场本来就是「battle」
func set_fighting(on: bool, delta: float) -> void:
	if on:
		_calm_left = CALM_DELAY
		if not fighting:
			fighting = true
			play("battle")
	elif fighting:
		_calm_left -= delta
		if _calm_left <= 0.0:
			fighting = false
			if _area != "":
				play(track_for(_area, GameState.daypart))


## 换曲子：新的从无声淡进来，旧的淡出去再停；同一首不重放（换区域时接着放）
func play(id: String) -> void:
	if id == track:
		return
	track = id
	var old := players[active]
	if old.playing:
		var oi := active
		_kill(oi)
		var tw := create_tween()
		tw.tween_method(func(v: float): fades[oi] = v, fades[oi], 0.0, FADE)
		tw.tween_callback(old.stop)
		tweens[oi] = tw
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
	fades[active] = 0.0
	apply_volume()
	p.play()
	var ni := active
	tweens[ni] = create_tween()
	(tweens[ni] as Tween).tween_method(func(v: float): fades[ni] = v, 0.0, 1.0, FADE)
	print("IC_MUSIC track=%s" % id)


func _process(_delta: float) -> void:
	apply_volume()


## 音量：播放器的 volume_db = 淡入淡出系数 × 设置里的音乐音量；「声音」或「背景音乐」关了就静音
func apply_volume() -> void:
	var level := Settings.music_volume if Settings.sound and Settings.music else 0.0
	for i in players.size():
		var v := fades[i] * level
		players[i].volume_db = linear_to_db(v) if v > 0.0001 else SILENT_DB


## 放完了（网页上的样本不按循环标记循环时）：还是现在这首就从头再放
func _on_finished(i: int) -> void:
	if i == active and track != "" and players[i].stream != null:
		players[i].play()


func _kill(i: int) -> void:
	if tweens[i] != null and (tweens[i] as Tween).is_valid():
		(tweens[i] as Tween).kill()
	tweens[i] = null


## 马上停（不淡出）、放掉曲子（测试退出前用；音频服务器要过一两帧才放掉播放对象）
func stop_now() -> void:
	track = ""
	fighting = false
	for i in players.size():
		_kill(i)
		fades[i] = 0.0
		players[i].stop()
		players[i].stream = null


func _exit_tree() -> void:
	stop_now()
