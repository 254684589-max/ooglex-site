#!/usr/bin/env python3
"""用纯 Python 合成《打工》的全部音频（无第三方素材、无版权问题）。

输出到 godot/assets/audio/：
  music_menu / music_city / music_intro / music_ending  背景音乐（合成波循环）
  amb_city / amb_rain / amb_shop / amb_office            环境声循环
  sfx_*                                                  界面、交互、脚步等短音效；sfx_engine 为汽车发动机循环
  （只重新生成发动机声：python3 games/working-life/tools/gen_audio.py engine）
全部 22.05 kHz 单声道 16 位 WAV；Godot 导入时压缩为 QOA。

    python3 games/working-life/tools/gen_audio.py
"""
from __future__ import annotations

import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "godot" / "assets" / "audio"


def write(name: str, samples: list[float], gain_to: float = 0.85) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = gain_to / peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))


def midi(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(samples: list[float], k: float) -> list[float]:
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def env(t: float, a: float, d: float) -> float:
    return min(1.0, t / a) * math.exp(-d * t) if a > 0 else math.exp(-d * t)


def saw(phase: float) -> float:
    return 2.0 * (phase % 1.0) - 1.0


def square(phase: float, pw: float = 0.5) -> float:
    return 1.0 if (phase % 1.0) < pw else -1.0


# ---------------------------------------------------------------- 音乐
def synthwave(bpm: float, bars: int, chords: list[list[int]], lead: list[int | None], drums: bool, mood: float, seed: int) -> list[float]:
    rnd = random.Random(seed)
    beat = 60.0 / bpm
    n = int(RATE * beat * 4 * bars)
    out = [0.0] * n
    step = beat / 4  # 十六分音符
    steps = int(bars * 16)
    # 和弦垫（慢起的锯齿波 + 失谐）
    for bar in range(bars):
        ch = chords[bar % len(chords)]
        start = int(bar * 4 * beat * RATE)
        length = int(4 * beat * RATE)
        for note in ch:
            f = midi(note)
            for det in (-0.12, 0.12):
                ph = rnd.random()
                inc = f * (1 + det / 100) / RATE
                for i in range(length):
                    t = i / RATE
                    a = min(1.0, t / 0.6) * (1.0 - max(0.0, (t - 4 * beat + 0.3) / 0.3))
                    ph += inc
                    out[start + i] += saw(ph) * 0.05 * a * mood
    out = lowpass(out, 0.08)
    # 贝斯：八分音符根音
    for s in range(0, steps, 2):
        bar = s // 16
        root = chords[bar % len(chords)][0] - 12
        start = int(s * step * RATE)
        length = int(step * 2 * RATE * 0.9)
        f = midi(root)
        ph = 0.0
        for i in range(length):
            t = i / RATE
            ph += f / RATE
            if start + i < n:
                out[start + i] += (square(ph, 0.35) * 0.12 + math.sin(ph * 2 * math.pi) * 0.1) * env(t, 0.005, 3.5)
    # 琶音
    for s in range(steps):
        bar = s // 16
        ch = chords[bar % len(chords)]
        note = ch[(s * 3 + bar) % len(ch)] + 12 * (1 + (s // 4) % 2)
        start = int(s * step * RATE)
        length = int(step * RATE * 1.6)
        f = midi(note)
        ph = 0.0
        for i in range(length):
            if start + i >= n:
                break
            t = i / RATE
            ph += f / RATE
            out[start + i] += square(ph, 0.25) * 0.035 * env(t, 0.002, 9.0)
    # 主旋律（每拍一个音）
    for k, note in enumerate(lead):
        if note is None:
            continue
        start = int(k * beat * RATE)
        length = int(beat * RATE * 1.8)
        f = midi(note)
        ph = 0.0
        for i in range(length):
            if start + i >= n:
                break
            t = i / RATE
            vib = 1 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
            ph += f * vib / RATE
            out[start + i] += (saw(ph) * 0.5 + math.sin(2 * math.pi * ph) * 0.5) * 0.07 * env(t, 0.02, 1.8)
    # 鼓
    if drums:
        for b in range(bars * 4):
            t0 = int(b * beat * RATE)
            # 底鼓
            if b % 2 == 0:
                ph = 0.0
                for i in range(int(0.25 * RATE)):
                    t = i / RATE
                    ph += (45 + 90 * math.exp(-30 * t)) / RATE
                    if t0 + i < n:
                        out[t0 + i] += math.sin(2 * math.pi * ph) * 0.35 * math.exp(-9 * t)
            # 军鼓（门控噪声）
            if b % 2 == 1:
                noise = lowpass([rnd.uniform(-1, 1) for _ in range(int(0.2 * RATE))], 0.5)
                for i, x in enumerate(noise):
                    t = i / RATE
                    if t0 + i < n:
                        out[t0 + i] += x * 0.18 * math.exp(-18 * t)
            # 踩镲
            for h in range(2):
                th = t0 + int(h * beat / 2 * RATE)
                for i in range(int(0.04 * RATE)):
                    if th + i < n:
                        out[th + i] += rnd.uniform(-1, 1) * 0.04 * math.exp(-90 * i / RATE)
    return out


def music() -> None:
    am = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]      # Am F C G
    dm = [[50, 53, 57], [46, 50, 53], [53, 57, 60], [52, 55, 59]]      # Dm Bb F E
    lead_city = [69, None, 72, 71, 69, None, 67, 64, 65, None, 69, 67, 64, None, 62, 64] * 2
    write("music_city", synthwave(96, 8, am, lead_city, True, 1.0, 1), 0.7)
    lead_menu = [None, None, 76, None, 74, None, 72, None, 69, None, None, None, 67, None, 69, None] * 2
    write("music_menu", synthwave(80, 8, dm, lead_menu, False, 1.2, 2), 0.7)
    lead_intro = [64, None, 67, None, 72, None, 71, None, 69, None, 67, None, 64, None, None, None]
    write("music_intro", synthwave(84, 4, am, lead_intro, False, 1.2, 3), 0.7)
    up = [[48, 52, 55], [55, 59, 62], [57, 60, 64], [53, 57, 60]]      # C G Am F
    lead_end = [72, None, 74, 76, None, 79, 76, None, 74, None, 72, 74, 72, None, None, None] * 2
    write("music_ending", synthwave(72, 8, up, lead_end, False, 1.1, 4), 0.7)


# ---------------------------------------------------------------- 环境声
def ambience() -> None:
    rnd = random.Random(7)
    n = RATE * 8
    # 城市：低频轰鸣 + 远处车流 + 偶尔的悬浮车掠过
    base = lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.01)
    city = [b * 1.6 for b in base]
    for k in range(3):
        c = rnd.randint(0, n - RATE * 2)
        f0 = rnd.uniform(300, 500)
        ph = 0.0
        for i in range(RATE * 2):
            t = i / RATE
            a = math.sin(math.pi * t / 2.0) ** 2
            ph += f0 * (1.0 - 0.15 * t) / RATE
            city[c + i] += math.sin(2 * math.pi * ph) * 0.05 * a
    write("amb_city", city, 0.4)
    # 雨：高频噪声 + 滴答
    hi = [rnd.uniform(-1, 1) for _ in range(n)]
    lo = lowpass(hi, 0.25)
    rain = [h - l * 0.8 for h, l in zip(hi, lowpass(lo, 0.02))]
    for k in range(260):
        c = rnd.randint(0, n - 400)
        for i in range(300):
            rain[c + i] += math.sin(2 * math.pi * rnd.uniform(2000, 4000) * i / RATE) * 0.3 * math.exp(-40 * i / RATE)
    write("amb_rain", lowpass(rain, 0.5), 0.35)
    # 商店：冰柜嗡嗡声 + 轻音乐般的叮
    shop = [math.sin(2 * math.pi * 120 * i / RATE) * 0.03 + math.sin(2 * math.pi * 240 * i / RATE) * 0.01 for i in range(n)]
    shop = [s + b * 0.4 for s, b in zip(shop, base)]
    for k in range(2):
        c = rnd.randint(0, n - RATE)
        for i in range(RATE):
            t = i / RATE
            shop[c + i] += (math.sin(2 * math.pi * 1318 * t) + math.sin(2 * math.pi * 1046 * t)) * 0.03 * math.exp(-4 * t)
    write("amb_shop", shop, 0.3)
    # 办公室：空调声 + 键盘
    office = [b * 0.8 for b in lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.05)]
    t = 0.0
    while t < 7.8:
        t += rnd.uniform(0.08, 0.35)
        c = int(t * RATE)
        for i in range(250):
            if c + i < n:
                office[c + i] += rnd.uniform(-1, 1) * 0.12 * math.exp(-80 * i / RATE)
    write("amb_office", office, 0.3)


# ---------------------------------------------------------------- 音效
def tone(freqs: list[tuple[float, float]], dur: float, decay: float, wave_fn=math.sin, vol: float = 1.0) -> list[float]:
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for f, start in freqs:
            if t >= start:
                tt = t - start
                s += wave_fn(2 * math.pi * f * tt) * math.exp(-decay * tt) * min(1.0, tt / 0.003)
        out.append(s * vol)
    return out


def sfx() -> None:
    rnd = random.Random(3)
    write("sfx_click", tone([(1800, 0)], 0.05, 90))
    write("sfx_coin", tone([(1318.5, 0), (1760, 0.08)], 0.5, 9))
    write("sfx_levelup", tone([(523, 0), (659, 0.09), (784, 0.18), (1046, 0.27)], 0.8, 5))
    write("sfx_quest", tone([(880, 0), (1174, 0.1)], 0.45, 7))
    write("sfx_quest_done", tone([(784, 0), (988, 0.1), (1175, 0.2), (1568, 0.32)], 1.0, 4))
    write("sfx_message", tone([(1568, 0), (2093, 0.07)], 0.3, 14))
    write("sfx_phone", tone([(1400, 0), (1100, 0.1), (1400, 0.2), (1100, 0.3)], 0.5, 6, lambda x: square(x / (2 * math.pi))))
    write("sfx_beep", tone([(2400, 0)], 0.07, 40))
    write("sfx_ok", tone([(988, 0), (1319, 0.06)], 0.22, 14))
    write("sfx_error", tone([(220, 0), (180, 0.1)], 0.3, 8, lambda x: square(x / (2 * math.pi))), 0.5)
    write("sfx_travel", tone([(300, 0), (450, 0.15), (600, 0.3)], 0.7, 4))
    n = int(RATE * 0.12)
    write("sfx_step", [x * math.exp(-45 * i / RATE) for i, x in enumerate(lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.15))])
    n = int(RATE * 0.16)
    write("sfx_pickup", [(math.sin(2 * math.pi * (110 - 50 * i / n) * i / RATE) * 0.8 + x * 0.6) * math.exp(-22 * i / RATE) for i, x in enumerate(lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.08))])
    n = int(RATE * 0.22)
    write("sfx_place", [x * math.exp(-30 * i / RATE) for i, x in enumerate(lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.3))])
    n = int(RATE * 0.4)
    write("sfx_door", [(math.sin(2 * math.pi * 600 * i / RATE) * 0.2 + x) * math.exp(-8 * i / RATE) for i, x in enumerate(lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.1))])
    n = int(RATE * 0.35)
    eat = []
    for i in range(n):
        t = i / RATE
        crunch = rnd.uniform(-1, 1) if (int(t * 12) % 2 == 0) else 0.0
        eat.append(crunch * math.exp(-5 * t))
    write("sfx_eat", lowpass(eat, 0.3))


def engine() -> None:
    """私家车发动机怠速循环（1 秒，首尾相位对齐可无缝循环；游戏里按车速调音高）。"""
    rnd = random.Random(11)
    n = RATE
    base = 42.0  # 1 秒内整数个周期
    noise = lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.05)
    out = []
    for i in range(n):
        t = i / RATE
        ph = 2 * math.pi * base * t
        # 四缸发动机：基频 + 二、三、四次谐波，外加点火脉动与低通噪声
        s = 0.55 * math.sin(ph) + 0.35 * math.sin(2 * ph + 0.3) + 0.18 * math.sin(3 * ph + 1.1) + 0.1 * math.sin(4 * ph)
        s *= 0.8 + 0.2 * math.sin(2 * math.pi * 4 * t)
        out.append(s + noise[i] * 0.5)
    write("sfx_engine", lowpass(out, 0.35), 0.6)


def main() -> None:
    import sys
    if sys.argv[1:] == ["engine"]:
        engine()
        return
    music()
    ambience()
    sfx()
    engine()
    total = sum(p.stat().st_size for p in OUT.glob("*.wav"))
    print(f"写入 {OUT}：{len(list(OUT.glob('*.wav')))} 个文件，{total / 1048576:.1f} MB")


if __name__ == "__main__":
    main()
