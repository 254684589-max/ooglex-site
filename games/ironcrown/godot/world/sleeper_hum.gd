class_name SleeperHum
extends AudioStreamPlayer
## 长眠者的声音（2026-11-07 所有者「长眠者能再恐怖些」→ 按建议：走近时听到一片很低的、整齐的呼吸声，脚下踩雪也是同一个节拍；离开就停）。
## 不用外部音频素材：一段 4.8 秒的循环在代码里合成（同 Sfx / Bell）——
##   呼吸：几十个人一起吸、一起呼（几股噪声过带通滤波，吸气高一点、呼气低一点，彼此只差几十毫秒：整齐，但听得出不是一个人）；
##   底下一层很低的嗡声（两个差一点点的低频正弦，慢慢拍）；
##   走着的（steps = true）：每 0.6 秒一下闷闷的踩雪声，跟呼吸同一个节拍。
## 音量按 dist_fn（离镜头最近的那个长眠者多远）：NEAR 米以内最响，FAR 米以外不放。「声音」关了不放。

const RATE := 22050
const CYCLE := 4.8
const NEAR := 3.0
const FAR := 24.0
const LOUD_DB := -7.0
const QUIET_DB := -40.0

var dist_fn: Callable
var steps := true


static func make(p_dist_fn: Callable, p_steps: bool) -> SleeperHum:
	var h := SleeperHum.new()
	h.name = "SleeperHum"
	h.dist_fn = p_dist_fn
	h.steps = p_steps
	return h


func _ready() -> void:
	bus = "Master"
	stream = synth(steps)
	volume_db = QUIET_DB


func _process(_delta: float) -> void:
	var d: float = float(dist_fn.call()) if dist_fn.is_valid() else INF
	var on := Settings.sound and d < FAR
	if not on:
		if playing:
			stop()
		return
	var k := clampf(1.0 - (d - NEAR) / (FAR - NEAR), 0.0, 1.0)
	volume_db = lerpf(QUIET_DB, LOUD_DB, pow(k, 1.4))
	if not playing:
		play(randf() * CYCLE)


## 合成一段能无缝循环的 4.8 秒
static func synth(with_steps: bool) -> AudioStreamWAV:
	var n := int(CYCLE * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4801
	for v in 5:                                   # 五股呼吸，起点差几十毫秒
		var off := rng.randf_range(0.0, 0.09)
		var low := 0.0
		var band := 0.0
		for i in n:
			var t := fposmod(float(i) / RATE - off, CYCLE)
			var inhale := t < 1.9
			var u := t / 1.9 if inhale else (t - 2.1) / 2.3
			var env := 0.0
			if inhale:
				env = sin(PI * u) * 0.8
			elif u >= 0.0 and u <= 1.0:
				env = pow(sin(PI * u), 0.8)
			var fc := (520.0 + 120.0 * u) if inhale else (380.0 - 90.0 * u)
			var f := 2.0 * sin(PI * fc / RATE)
			low += f * band
			var high := rng.randf_range(-1.0, 1.0) - low - 1.2 * band
			band += f * high
			b[i] += band * env * 0.22
	for i in n:                                   # 很低的嗡：55 Hz 和 56.25 Hz 慢慢拍（4.8 秒正好拍 6 下，接得上）
		var t := float(i) / RATE
		b[i] += (sin(TAU * 55.0 * t) + sin(TAU * 56.25 * t)) * 0.03
	if with_steps:
		for s in 8:                               # 每 0.6 秒一下踩雪：一小段低通噪声，起得快、收得快
			var start := int(s * 0.6 * RATE)
			var y := 0.0
			var f := 1.0 - exp(-TAU * 900.0 / RATE)
			for j in int(0.16 * RATE):
				var i := (start + j) % n
				y += f * (rng.randf_range(-1.0, 1.0) - y)
				var env := exp(-j / (0.035 * RATE)) * minf(1.0, j / (0.004 * RATE))
				b[i] += y * env * 0.9
	var peak := 0.0
	for v in b:
		peak = maxf(peak, absf(v))
	var g := 0.85 / maxf(peak, 0.0001)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(b[i] * g, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st
