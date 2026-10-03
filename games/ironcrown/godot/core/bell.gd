class_name Bell
extends RefCounted
## 镇上的钟声（路线图 3.8 开场；STORY.md 第三节「夜，钟声」）。不用外部音频素材：按教堂大钟的泛音在代码里合成一声——
## 嗡音、基音、小三度、五度、八度和几条高泛音各自按指数衰减（嗡音和基音各有一条差一点点的，听起来会「颤」），
## 开头 25 毫秒是敲击的噪声，最后过一道低通，像隔着雾从镇子另一头传来。
## 合成一次本机约 50 毫秒（网页上慢几倍），开场在标题卡显示的时候合成，不在玩家点下去的那一刻卡一下。

const RATE := 22050
const SECONDS := 4.5
const PRIME := 196.0                       # 基音 G3：镇上的大钟，低沉
const LOWPASS_HZ := 2400.0
## [相对基音的频率倍数, 振幅, 衰减时间（秒）]
const PARTIALS := [
	[0.5, 0.55, 2.6], [0.502, 0.25, 2.4],     # 嗡音
	[1.0, 0.6, 1.8], [1.003, 0.2, 1.6],       # 基音
	[1.19, 0.45, 1.2],                         # 小三度：钟声特有的那点「哀」
	[1.5, 0.3, 0.9], [2.0, 0.4, 0.8], [2.51, 0.18, 0.5], [2.66, 0.14, 0.45], [3.01, 0.1, 0.35],
]


## 合成一声钟（16 位单声道）
static func make_stream() -> AudioStreamWAV:
	var n := int(RATE * SECONDS)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for p in PARTIALS:
		# 正弦用旋转递推（每个采样只做乘加，不调 sin），振幅每个采样乘一次衰减系数
		var w := TAU * PRIME * float(p[0]) / RATE
		var c := cos(w)
		var s := sin(w)
		var re := 1.0
		var im := 0.0
		var amp := float(p[1])
		var dec := exp(-1.0 / (float(p[2]) * RATE))
		for i in n:
			var r2 := re * c - im * s
			im = re * s + im * c
			re = r2
			buf[i] += im * amp
			amp *= dec
	var rng := RandomNumberGenerator.new()
	rng.seed = 7                               # 固定种子：每次合成出来一样
	for i in int(RATE * 0.025):
		buf[i] += rng.randf_range(-1.0, 1.0) * 0.35 * exp(-float(i) / (RATE * 0.006))
	var a := 1.0 - exp(-TAU * LOWPASS_HZ / RATE)
	var y := 0.0
	var peak := 0.0
	for i in n:
		y += a * (buf[i] - y)
		buf[i] = y
		peak = maxf(peak, absf(y))
	var g := 0.85 / maxf(peak, 0.001)
	var fade := int(RATE * 0.4)                # 尾巴淡出，不咔哒一声断掉
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := buf[i] * g
		if i > n - fade:
			v *= float(n - i) / fade
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	return st
