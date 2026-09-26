class_name Sfx
extends Node
## 程序合成音效（P11，移植 V0.1 的 Snd：WebAudio 振荡器 + 带通噪声，配方逐条照搬）。
## 不用任何外部音频素材：每个音效第一次播放时在内存里合成一段 22050 Hz 单声道 16 位的采样（AudioStreamWAV），之后复用。
##   tone(频率, 时长, 波形, 音量, 滑音倍数, 延迟)：正弦 / 方波 / 锯齿 / 三角波，音量按指数衰减，滑音 = 频率指数滑到 f × slide
##   noise(时长, 音量, 中心频率, Q)：白噪声经双二阶带通滤波，音量指数衰减
## 用法：Sfx.play("hit")。场景里没有 Sfx 节点时（自动化测试）什么也不做，只记下调用（last / counts），方便测试。
## 8 个播放器轮流用，同一个音效 40 毫秒内不重复播放（一群怪同时挨打时不会炸耳朵）。

const RATE := 22050
const VOICES := 8

static var instance: Sfx = null
static var enabled := true
static var last := ""
static var counts := {}

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_t := {}


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func play(n: String) -> void:
	last = n
	counts[n] = int(counts.get(n, 0)) + 1
	if instance == null or not enabled:
		return
	instance._play(n)


func _play(n: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_t.get(n, -1000)) < 40:
		return
	_last_t[n] = now
	if not _cache.has(n):
		var s := synth(n)
		if s == null:
			return
		_cache[n] = s
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _cache[n]
	p.play()


## V0.1 Snd.play 的配方（数值原样）
static func recipe(n: String) -> Array:
	match n:
		"swing": return [["n", .12, .07, 2600, .8]]
		"hit": return [["n", .1, .22, 700, 1.0], ["t", 120, .1, "square", .04, .5]]
		"crit": return [["n", .14, .28, 500, 1.0], ["t", 90, .18, "sawtooth", .07, .4]]
		"fire": return [["n", .35, .1, 500, .7], ["t", 260, .28, "sawtooth", .03, .35]]
		"boom": return [["n", .45, .26, 260, .6]]
		"ice": return [["n", .6, .14, 5000, 2.0], ["t", 1200, .4, "sine", .04, .5]]
		"whirl": return [["n", .35, .12, 1800, .6]]
		"blink": return [["t", 900, .25, "sine", .07, .25]]
		"gold": return [["t", 1500, .07, "triangle", .07], ["t", 2000, .09, "triangle", .05, 0, .06]]
		"pick": return [["t", 620, .08, "triangle", .09]]
		"magic": return [["t", 700, .12, "triangle", .08], ["t", 1050, .15, "triangle", .06, 0, .07]]
		"rare": return [["t", 660, .15, "triangle", .08], ["t", 990, .2, "triangle", .07, 0, .09], ["t", 1320, .25, "triangle", .06, 0, .18]]
		"legend": return [["t", 523, .5, "triangle", .07, 0, 0.0], ["t", 659, .5, "triangle", .07, 0, .09], ["t", 784, .5, "triangle", .07, 0, .18], ["t", 1046, .5, "triangle", .07, 0, .27]]
		"lvl": return [["t", 392, .35, "square", .04, 0, 0.0], ["t", 523, .35, "square", .04, 0, .08], ["t", 659, .35, "square", .04, 0, .16], ["t", 784, .35, "square", .04, 0, .24]]
		"die": return [["t", 180, .45, "sawtooth", .05, .35], ["n", .3, .08, 400, 1.0]]
		"hurt": return [["t", 95, .18, "square", .06, .6]]
		"potion": return [["t", 420, .18, "sine", .1, 1.9]]
		"portal": return [["t", 260, .7, "sine", .08, 3.0]]
		"chest": return [["n", .25, .14, 380, 1.0], ["t", 220, .2, "triangle", .05, 1.5]]
		"barrel": return [["n", .2, .2, 300, .5]]
		"shrine": return [["t", 330, .6, "sine", .05, 0, 0.0], ["t", 440, .6, "sine", .05, 0, .12], ["t", 554, .6, "sine", .05, 0, .24], ["t", 660, .6, "sine", .05, 0, .36]]
		"arrow": return [["n", .12, .06, 3500, 3.0]]
		"bolt": return [["t", 500, .25, "sawtooth", .03, .5]]
		"boss": return [["t", 70, 1.2, "sawtooth", .08, .6], ["t", 105, 1.2, "sawtooth", .05, .6]]
		"click": return [["t", 800, .04, "triangle", .04]]
	return []


## 把配方合成为一段采样；未知音效返回 null
static func synth(n: String) -> AudioStreamWAV:
	var parts := recipe(n)
	if parts.is_empty():
		return null
	var dur := 0.0
	for p in parts:
		if p[0] == "t":
			dur = maxf(dur, float(p[2]) + (float(p[6]) if p.size() > 6 else 0.0) + 0.03)
		else:
			dur = maxf(dur, float(p[1]) + 0.03)
	var n_s := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n_s)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n)
	for p in parts:
		if p[0] == "t":
			buf = _tone(buf, float(p[1]), float(p[2]), String(p[3]), float(p[4]), float(p[5]) if p.size() > 5 else 0.0, float(p[6]) if p.size() > 6 else 0.0)
		else:
			buf = _noise(buf, rng, float(p[1]), float(p[2]), float(p[3]), float(p[4]))
	var bytes := PackedByteArray()
	bytes.resize(n_s * 2)
	for i in n_s:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * 2.2, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## 音量从 v 指数衰减到 0.0008（WebAudio exponentialRampToValueAtTime 的曲线）
static func _env(v: float, t: float, d: float) -> float:
	return v * pow(0.0008 / v, clampf(t / d, 0.0, 1.0))


static func _tone(buf: PackedFloat32Array, f: float, d: float, type: String, v: float, slide: float, delay: float) -> PackedFloat32Array:
	var i0 := int(delay * RATE)
	var n := int(d * RATE)
	var phase := 0.0
	for i in n:
		var k := i0 + i
		if k >= buf.size():
			break
		var t := float(i) / RATE
		var fr := f * pow(maxf(20.0 / f, slide), t / d) if slide > 0.0 else f
		phase = fmod(phase + fr / RATE, 1.0)
		var s := 0.0
		match type:
			"square": s = 1.0 if phase < 0.5 else -1.0
			"sawtooth": s = phase * 2.0 - 1.0
			"triangle": s = 1.0 - 4.0 * absf(phase - 0.5)
			_: s = sin(phase * TAU)
		buf[k] += s * _env(v, t, d)
	return buf


static func _noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, d: float, v: float, freq: float, q: float) -> PackedFloat32Array:
	# 双二阶带通（RBJ 公式，常数 0 dB 峰值增益），与 WebAudio BiquadFilter 'bandpass' 一致
	var w0 := TAU * minf(freq, RATE * 0.45) / RATE
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var n := mini(int(d * RATE), buf.size())
	for i in n:
		var x := rng.randf() * 2.0 - 1.0
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] += y * _env(v, float(i) / RATE, d)
	return buf
