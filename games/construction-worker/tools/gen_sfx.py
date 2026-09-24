#!/usr/bin/env python3
"""用纯 Python 合成《工地搬砖》的几个短音效（无第三方素材、无版权问题）。

输出到 godot/assets/audio/*.wav（22.05 kHz 单声道 16 位），总共几十 KB。
    python3 games/construction-worker/tools/gen_sfx.py
"""
from __future__ import annotations

import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "godot" / "assets" / "audio"


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = 0.85 / peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))


def env(i: int, n: int, attack: float = 0.004, decay: float = 8.0) -> float:
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-decay * t)


def lowpass(samples: list[float], k: float) -> list[float]:
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def pickup() -> list[float]:
    n = int(RATE * 0.16)
    rnd = random.Random(1)
    noise = lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.08)
    out = []
    phase = 0.0
    for i in range(n):
        f = 110 - 50 * i / n
        phase += 2 * math.pi * f / RATE
        out.append((math.sin(phase) * 0.8 + noise[i] * 0.6) * env(i, n, 0.003, 22))
    return out


def place() -> list[float]:
    n = int(RATE * 0.22)
    rnd = random.Random(2)
    out = [0.0] * n
    for start, vol in ((0, 1.0), (int(RATE * 0.07), 0.55)):
        burst = lowpass([rnd.uniform(-1, 1) for _ in range(int(RATE * 0.09))], 0.35)
        for j, s in enumerate(burst):
            if start + j < n:
                t = j / RATE
                ring = math.sin(2 * math.pi * 820 * t) * 0.35
                out[start + j] += (s + ring) * vol * math.exp(-60 * t)
    return out


def coin() -> list[float]:
    n = int(RATE * 0.5)
    out = []
    for i in range(n):
        t = i / RATE
        f = 1318.5 if t < 0.08 else 1760.0
        tt = t if t < 0.08 else t - 0.08
        s = math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 2 * t)
        out.append(s * math.exp(-9 * tt) * min(1.0, t / 0.003))
    return out


def click() -> list[float]:
    n = int(RATE * 0.05)
    return [math.sin(2 * math.pi * 1800 * i / RATE) * env(i, n, 0.001, 90) for i in range(n)]


def levelup() -> list[float]:
    notes = [523.25, 659.25, 783.99, 1046.5]
    step = int(RATE * 0.09)
    n = step * len(notes) + int(RATE * 0.3)
    out = [0.0] * n
    for k, f in enumerate(notes):
        start = k * step
        length = n - start
        for j in range(length):
            t = j / RATE
            out[start + j] += (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t)) * math.exp(-6 * t) * 0.6
    return out


def door() -> list[float]:
    n = int(RATE * 0.35)
    rnd = random.Random(3)
    noise = lowpass([rnd.uniform(-1, 1) for _ in range(n)], 0.05)
    out = []
    phase = 0.0
    for i in range(n):
        f = 180 + 60 * math.sin(i / n * 7)
        phase += 2 * math.pi * f / RATE
        out.append((math.sin(phase) * 0.25 + noise[i]) * env(i, n, 0.02, 6))
    return out


def main() -> None:
    for name, fn in [("pickup", pickup), ("place", place), ("coin", coin), ("click", click), ("levelup", levelup), ("door", door)]:
        write(name, fn())
    total = sum(p.stat().st_size for p in OUT.glob("*.wav"))
    print(f"写入 {OUT}：{total / 1024:.0f} KB")


if __name__ == "__main__":
    main()
