extends Node
## 战斗音效（路线图 C.1）。不用外部音频素材：每一声都在代码里合成（同 Bell 的钟声）——
##   挥砍：一段噪声过一道中心频率扫上去又落下来的带通滤波器（「呼」的一声），重击更长更低、拳头更短；
##   砍中 / 拳头打中：一下低频的「咚」加一小段低通噪声（闷响）；木桩：几条短促的木头泛音；
##   格挡：几条不成谐波的金属泛音（「铛」）；完美格挡：更高更亮、拖得更长；破防：金属声加一声碎裂的低噪声；
##   自己挨打：更闷更低的一下。
## 合成都很短（0.1–0.7 秒，22050 Hz 单声道 16 位），开局以后一帧合成一声，用到还没合成的就当场合成。
## 播放：一池 AudioStreamPlayer 都走主总线（不在运行时新建总线，见 Music 的注释）；有位置的声音按离相机多远算音量（不做左右声道），
## 太远（MAX_DIST）不放；同一声 GAP 秒内不重复放（军阵里一下子几十下）；每次放音高随机上下浮一点。
## 「声音」关了（Settings.sound = false）就都不放。

const RATE := 22050
const POOL := 10
const MAX_DIST := 28.0
const GAP := 0.03
const BASE_DB := -4.0

## 名字 → 音量（分贝，叠在 BASE_DB 上）
const LEVEL := {
	"swing_light": -6.0, "swing_heavy": -3.0, "swing_fist": -9.0, "swing_blunt": -5.0,
	"hit_flesh": -2.0, "hit_heavy": 0.0, "hit_fist": -3.0, "hit_wood": -3.0, "hit_arrow": -5.0,
	"clang": -4.0, "perfect": -2.0, "guard_break": -1.0, "hurt": -2.0,
}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var _next := 0
var _todo: Array = []
var _last_at := {}
var clock := 0.0
var last := ""                     # 最近放的一声（测试看）
var played := 0                    # 一共放了几声（测试看）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	_todo = LEVEL.keys()


func _process(delta: float) -> void:
	clock += delta
	if not _todo.is_empty():
		stream_of(str(_todo.pop_front()))       # 一帧合成一声，不在开局那一下卡住


## 这一声的音频（没合成过就当场合成）
func stream_of(sound_name: String) -> AudioStreamWAV:
	if not streams.has(sound_name):
		streams[sound_name] = _make(sound_name)
	return streams[sound_name]


## 放一声。at = 世界坐标（按离相机的距离衰减）；不给 = 自己的声音（挥剑、挨打），不衰减
func play(sound_name: String, at: Variant = null, pitch_jitter := 0.08) -> bool:
	if not Settings.sound or not LEVEL.has(sound_name):
		return false
	if clock - float(_last_at.get(sound_name, -1.0)) < GAP:
		return false
	var db := BASE_DB + float(LEVEL[sound_name])
	if at is Vector3:
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		if cam:
			var d := cam.global_position.distance_to(at as Vector3)
			if d > MAX_DIST:
				return false
			db -= 20.0 * log(1.0 + d / 4.0) / log(10.0)
	_last_at[sound_name] = clock
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = stream_of(sound_name)
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	last = sound_name
	played += 1
	return true


## 挥砍的声音：按武器（blade / blunt / brawl）和招式
static func swing_name(skill: String, kind: String) -> String:
	if skill == "brawl" or skill == "fists":
		return "swing_fist"
	if kind == "heavy":
		return "swing_heavy"
	return "swing_blunt" if skill in ["blunt", "club"] else "swing_light"


## 打中的声音：按武器和招式
static func hit_name(skill: String, kind: String) -> String:
	if kind == "arrow":
		return "hit_arrow"
	if skill in ["brawl", "fists"]:
		return "hit_fist"
	return "hit_heavy" if kind == "heavy" or skill in ["blunt", "club"] else "hit_flesh"


# ---------------- 合成 ----------------

func _make(sound_name: String) -> AudioStreamWAV:
	var b := PackedFloat32Array()
	match sound_name:
		"swing_light":
			b = _whoosh(0.24, 650.0, 1900.0, 800.0, 0.38)
		"swing_heavy":
			b = _whoosh(0.4, 380.0, 1400.0, 450.0, 0.45)
		"swing_fist":
			b = _whoosh(0.14, 420.0, 950.0, 500.0, 0.35)
		"swing_blunt":
			b = _whoosh(0.3, 300.0, 950.0, 380.0, 0.42)
		"hit_flesh":
			b = _buf(0.22)
			_tone(b, 95.0, 1.0, 0.06)
			_tone(b, 62.0, 0.7, 0.09)
			_noise(b, 0.8, 0.035, 1800.0, 11)
			_noise(b, 0.25, 0.008, 6000.0, 12)
		"hit_heavy":
			b = _buf(0.3)
			_tone(b, 80.0, 1.0, 0.09)
			_tone(b, 52.0, 0.8, 0.13)
			_noise(b, 0.9, 0.05, 1400.0, 13)
			_noise(b, 0.3, 0.01, 5000.0, 14)
		"hit_fist":
			b = _buf(0.16)
			_tone(b, 120.0, 0.9, 0.05)
			_noise(b, 0.7, 0.02, 2600.0, 15)
		"hit_wood":
			b = _buf(0.2)
			_tone(b, 310.0, 0.7, 0.07)
			_tone(b, 640.0, 0.4, 0.05)
			_tone(b, 1150.0, 0.25, 0.03)
			_noise(b, 0.5, 0.006, 4000.0, 16)
		"hit_arrow":
			b = _buf(0.14)
			_tone(b, 150.0, 0.8, 0.035)
			_noise(b, 0.6, 0.012, 3000.0, 17)
		"clang":
			b = _buf(0.45)
			for p in [[1250.0, 0.5, 0.22], [1892.0, 0.45, 0.18], [2610.0, 0.35, 0.14], [3480.0, 0.25, 0.1], [640.0, 0.3, 0.12]]:
				_tone(b, p[0], p[1], p[2])
			_noise(b, 0.6, 0.006, 7000.0, 18)
		"perfect":
			b = _buf(0.75)
			for p in [[1568.0, 0.5, 0.55], [2350.0, 0.4, 0.45], [3136.0, 0.3, 0.38], [4180.0, 0.2, 0.28], [784.0, 0.35, 0.5], [1571.0, 0.2, 0.5]]:
				_tone(b, p[0], p[1], p[2])
			_noise(b, 0.5, 0.005, 8000.0, 19)
		"guard_break":
			b = _buf(0.45)
			for p in [[1180.0, 0.4, 0.12], [1760.0, 0.35, 0.1], [2480.0, 0.25, 0.08]]:
				_tone(b, p[0], p[1], p[2])
			_tone(b, 70.0, 0.8, 0.1)
			_noise(b, 0.9, 0.12, 900.0, 20)
		"hurt":
			b = _buf(0.26)
			_tone(b, 75.0, 1.0, 0.1)
			_tone(b, 48.0, 0.6, 0.14)
			_noise(b, 0.7, 0.08, 700.0, 21)
		_:
			b = _buf(0.05)
	return _to_wav(b)


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * seconds))
	return b


## 一条按指数衰减的正弦（旋转递推，同 Bell）
func _tone(b: PackedFloat32Array, freq: float, amp: float, decay: float) -> void:
	var w := TAU * freq / RATE
	var c := cos(w)
	var s := sin(w)
	var re := 1.0
	var im := 0.0
	var k := exp(-1.0 / (decay * RATE))
	var a := amp
	for i in b.size():
		var r2 := re * c - im * s
		im = re * s + im * c
		re = r2
		b[i] += im * a
		a *= k
		if a < 0.0005:
			break


## 一段按指数衰减的噪声，过一道一阶低通
func _noise(b: PackedFloat32Array, amp: float, decay: float, lowpass: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var f := 1.0 - exp(-TAU * lowpass / RATE)
	var y := 0.0
	var k := exp(-1.0 / (decay * RATE))
	var a := amp
	for i in b.size():
		y += f * (rng.randf_range(-1.0, 1.0) - y)
		b[i] += y * a * 2.0
		a *= k
		if a < 0.0005:
			break


## 挥砍的「呼」：噪声过状态变量带通，中心频率 f0 → f1（峰在 peak 处）→ f2；包络在 peak 处最响
func _whoosh(seconds: float, f0: float, f1: float, f2: float, peak: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 + f1)
	var low := 0.0
	var band := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / n
		var fc := lerpf(f0, f1, t / peak) if t < peak else lerpf(f1, f2, (t - peak) / (1.0 - peak))
		var f := 2.0 * sin(PI * fc / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - 0.9 * band
		band += f * high
		var env := pow(t / peak, 1.6) if t < peak else pow(1.0 - (t - peak) / (1.0 - peak), 2.2)
		b[i] = band * env
	return b


func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for v in b:
		peak = maxf(peak, absf(v))
	var g := 0.9 / maxf(peak, 0.0001)
	var n := b.size()
	var fade := mini(int(RATE * 0.02), n)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := b[i] * g
		if i > n - fade:
			v *= float(n - i) / fade                # 尾巴淡出，不咔哒一声断掉
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	return st
