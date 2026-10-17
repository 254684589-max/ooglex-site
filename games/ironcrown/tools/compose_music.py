#!/usr/bin/env python3
"""《铁冠之争》背景音乐（原创，代码作曲、代码合成）。

用法：python3 games/ironcrown/tools/compose_music.py [输出目录]
默认输出到 games/ironcrown/godot/assets/music/，每首一个 .ogg（Ogg Vorbis，单声道转立体声、22050 Hz），
首尾无缝循环（混响用循环卷积，曲尾的余音绕回曲头），五首听起来一样响（按 A 计权算：手机、笔记本的小喇叭上也一样）。只依赖 numpy 和 ffmpeg（libvorbis）。

五首，都是这里写的旋律与和声（调式音乐，没有引用任何现成曲子）：
  town   霜渡镇的清晨与白天、客栈：D 多利亚调式，拨弦琶音 + 木笛
  night  序章的夜（霜渡镇、墓园、教堂、桦林、渡口）：A 爱奥利亚调式，低音持续音 + 弦垫 + 稀疏的拨弦
  marsh  鹭沼：E 弗里吉亚调式，空五度持续音 + 带气声的木笛片段 + 芦苇沙沙声
  keep   黑鹭堡（庭院与堡内各处）：D 小调，弦垫和弦 + 低鼓 + 拨弦低音
  battle 军阵试验场：G 小调，战鼓 + 低音铜管般的固定音型
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 22050
RNG = np.random.default_rng(1701)
A4 = 440.0
NOTE = {"C": -9, "C#": -8, "Db": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5, "F": -4, "F#": -3, "Gb": -3, "G": -2, "G#": -1, "Ab": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}


def hz(name: str) -> float:
    """'D4' / 'F#3' / 'Bb2' -> 频率"""
    n, o = name[:-1], int(name[-1])
    return A4 * 2.0 ** ((NOTE[n] + (o - 4) * 12) / 12.0)


def env(n: int, a: float, r: float) -> np.ndarray:
    """起音 a 秒、释音 r 秒的包络（中间平）"""
    e = np.ones(n)
    na = min(n, max(1, int(a * SR)))
    nr = min(n - na, max(1, int(r * SR)))
    e[:na] = np.linspace(0, 1, na) ** 1.5
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr) ** 2
    return e


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """一阶低通（FFT 上乘一个平滑的衰减，省得逐点循环）"""
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1.0 / np.sqrt(1.0 + (fr / cutoff) ** 2)
    return np.fft.irfft(f, len(x))


# ---------------- 乐器 ----------------

def pluck(f: float, dur: float, bright: float = 0.5) -> np.ndarray:
    """拨弦（Karplus-Strong）：鲁特琴 / 竖琴一类"""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = RNG.uniform(-1, 1, p)
    buf = lowpass(np.concatenate([buf, buf]), 1500 + 4000 * bright)[:p]
    out = np.empty(n)
    decay = 0.996
    for i in range(n):
        v = buf[i % p]
        out[i] = v
        buf[i % p] = decay * 0.5 * (v + buf[(i + 1) % p])
    return out * env(n, 0.002, min(0.3, dur * 0.3))


def flute(f: float, dur: float, breath: float = 0.08) -> np.ndarray:
    """木笛：正弦 + 少量泛音 + 慢颤音 + 气声"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.5, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    noise = lowpass(RNG.normal(0, 1, n), f * 2.0) * breath
    return (tone + noise) * env(n, 0.09, min(0.35, dur * 0.4))


def pad(freqs: list, dur: float, cutoff: float = 900.0) -> np.ndarray:
    """弦垫：每个音两条微微走调的锯齿波，低通，慢起慢收"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.12):
            ff = f * 2 ** (det / 12)
            out += 2 * ((t * ff) % 1.0) - 1
    out = lowpass(out / (2 * len(freqs)), cutoff)
    return out * env(n, min(1.2, dur * 0.35), min(1.4, dur * 0.4))


def drone(f: float, dur: float) -> np.ndarray:
    """持续音：基音 + 五度 + 八度，再加上面几个泛音（手机、笔记本的小喇叭放不出 150 Hz 以下，只有基音的话在小喇叭上几乎听不见；核对配乐时量出来的），慢慢起伏"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    wob = 1.0 + 0.15 * np.sin(2 * np.pi * t / 7.0)
    x = 0.6 * np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t) + 0.45 * np.sin(2 * np.pi * f * 2 * t)
    for k, g in ((3, 0.3), (4, 0.22), (6, 0.12), (8, 0.06)):
        x += g * np.sin(2 * np.pi * f * k * t + k)
    return lowpass(x, 1100) * wob


def drum(dur: float = 0.9, f: float = 70.0, noise: float = 0.35) -> np.ndarray:
    """低鼓：下滑的正弦 + 一点皮面的噪声"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    fs = f * (1 + 1.2 * np.exp(-t * 18))
    body = 0.65 * np.sin(2 * np.pi * np.cumsum(fs) / SR) * np.exp(-t * 5.5)
    skin = lowpass(RNG.normal(0, 1, n), 3200) * np.exp(-t * 30) * noise * 1.6      # 皮面的响声多一些：小喇叭上听得出鼓点
    knock = np.sin(2 * np.pi * f * 3.1 * t) * np.exp(-t * 22) * 0.35                # 鼓槌敲下去那一下的中频
    return body + skin + knock


def brass(f: float, dur: float) -> np.ndarray:
    """低音铜管般的音色：锯齿波，起音时滤波器打开"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = 2 * ((t * f) % 1.0) - 1
    x = 0.6 * lowpass(x, 500) + 0.4 * lowpass(x, 1400) * np.exp(-t * 3)
    return x * env(n, 0.04, min(0.25, dur * 0.3))


def rustle(dur: float) -> np.ndarray:
    """芦苇沙沙声：带通噪声，一阵一阵"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = lowpass(RNG.normal(0, 1, n), 3500) - lowpass(RNG.normal(0, 1, n), 700) * 0.3
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * t / 5.3) * np.sin(2 * np.pi * t / 2.1 + 1.0)
    return x * np.clip(gust, 0, 1) ** 2


# ---------------- 混音 ----------------

class Track:
    def __init__(self, seconds: float):
        self.n = int(seconds * SR)
        self.buf = np.zeros(self.n)

    def add(self, x: np.ndarray, at: float, gain: float) -> None:
        """在 at 秒处叠加；超过结尾的部分绕回开头（循环）"""
        i = int(at * SR) % self.n
        x = x * gain
        while len(x) > 0:
            k = min(len(x), self.n - i)
            self.buf[i:i + k] += x[:k]
            x = x[k:]
            i = 0

    def finish(self, reverb: float, room: float) -> np.ndarray:
        """循环卷积混响（曲尾的余音绕回曲头），左右声道用不同的混响尾巴，归一化"""
        out = []
        for side in range(2):
            m = int(room * SR)
            t = np.arange(m) / SR
            ir = RNG.normal(0, 1, m) * np.exp(-t * 6.9 / room)
            ir = lowpass(ir, 2600)
            ir /= np.sqrt(np.sum(ir ** 2))
            irp = np.zeros(self.n)
            irp[:min(m, self.n)] = ir[:self.n]
            wet = np.fft.irfft(np.fft.rfft(self.buf) * np.fft.rfft(irp), self.n)
            out.append(self.buf * (1 - reverb) + wet * reverb * 1.6)
        st = np.stack(out, axis=1)
        st -= st.mean(axis=0)
        sp = np.fft.rfft(st, axis=0)                                        # 切掉 50 Hz 以下的闷响（哪个喇叭都放不出来，只占峰值）
        sp[np.fft.rfftfreq(len(st), 1 / SR) < 50] = 0
        st = np.fft.irfft(sp, len(st), axis=0)
        st *= 10 ** (-24 / 20) / (_audible_rms(st) + 1e-9)                # 五首听起来一样响：按 A 计权算（小喇叭上也一样；
        return 0.9 * np.tanh(st / 0.9)                                      # 原来按全频算，低音多的曲子在手机上轻了 7～11 dB）；峰值软压在 0.9 以内


def a_weight(freqs: np.ndarray) -> np.ndarray:
    """A 计权（IEC 61672）：人耳和小喇叭都对低音不敏感，按它算出来的响度更接近「听起来多响」"""
    f2 = np.maximum(freqs, 1e-3) ** 2
    ra = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2))
    return ra / 0.7943          # 1 kHz 处为 1


def _audible_rms(st: np.ndarray) -> float:
    """A 计权后的均方根（听起来多响；原来按全频算，低音多的曲子在手机上轻了 7～11 dB）"""
    w = a_weight(np.fft.rfftfreq(len(st), 1 / SR))[:, None]       # 左右声道各算各的（两边不相关，混成单声道会互相抵掉）
    aw = np.fft.irfft(np.fft.rfft(st, axis=0) * w, len(st), axis=0)
    return float(np.sqrt(np.mean(aw ** 2)))


# ---------------- 曲子 ----------------

def town() -> np.ndarray:
    """D 多利亚，3 拍，80 拍每分：拨弦琶音 + 木笛，32 小节"""
    beat = 60 / 80
    bar = beat * 3
    chords = [["D3", "A3", "D4", "F4"], ["C3", "G3", "C4", "E4"], ["D3", "A3", "D4", "F4"], ["G2", "D3", "G3", "B3"],
              ["F3", "C4", "F4", "A4"], ["C3", "G3", "C4", "E4"], ["G2", "D3", "G3", "B3"], ["A2", "E3", "A3", "C4"]]
    tr = Track(bar * 32)
    for b in range(32):
        ch = chords[b % 8]
        t0 = b * bar
        tr.add(pluck(hz(ch[0]), bar * 1.2, 0.3), t0, 0.5)
        for k, nt in enumerate([ch[1], ch[2], ch[3], ch[2], ch[1], ch[2]]):
            tr.add(pluck(hz(nt), beat * 1.6, 0.5), t0 + k * beat / 2, 0.28)
    melody = [  # (小节起点内的拍, 音, 拍数)
        [(0, "A4", 1.5), (1.5, "G4", 0.5), (2, "F4", 1)], [(0, "E4", 2), (2, "D4", 1)], [(0, "F4", 1), (1, "G4", 1), (2, "A4", 1)], [(0, "B4", 3)],
        [(0, "C5", 1.5), (1.5, "A4", 0.5), (2, "F4", 1)], [(0, "G4", 2), (2, "E4", 1)], [(0, "D4", 1), (1, "E4", 1), (2, "F4", 1)], [(0, "E4", 3)],
        [(0, "A4", 1), (1, "D5", 2)], [(0, "C5", 1), (1, "B4", 1), (2, "G4", 1)], [(0, "A4", 1.5), (1.5, "F4", 1.5)], [(0, "G4", 1), (1, "B4", 2)],
        [(0, "A4", 2), (2, "G4", 1)], [(0, "E4", 1.5), (1.5, "G4", 1.5)], [(0, "F4", 1), (1, "E4", 1), (2, "D4", 1)], [(0, "D4", 3)],
    ]
    for rep in range(2):
        for i, bar_notes in enumerate(melody):
            b = 16 * rep + i
            if rep == 0 and i < 4:
                continue                 # 开头四小节只有拨弦（进场时不吵）
            for (st, nt, ln) in bar_notes:
                tr.add(flute(hz(nt), ln * beat * 1.05), b * bar + st * beat, 0.32)
    return tr.finish(0.35, 2.2)


def night() -> np.ndarray:
    """A 爱奥利亚，4 拍，60 拍每分：A 的持续音 + 弦垫 Am–F–G–Em + 稀疏的低音拨弦，16 小节"""
    beat = 1.0
    bar = beat * 4
    tr = Track(bar * 16)
    tr.add(drone(hz("A1"), bar * 16), 0, 0.16)
    chords = [["A2", "C3", "E3"], ["F2", "A2", "C3"], ["G2", "B2", "D3"], ["E2", "G2", "B2"]]
    for b in range(16):
        ch = chords[b % 4]
        tr.add(pad([hz(n) for n in ch], bar * 1.05, 700), b * bar, 0.55)
    figure = [(0, "E3"), (1.5, "A3"), (3, "C4")]
    for b in range(0, 16):
        if b % 4 == 3:
            continue
        for st, nt in figure:
            tr.add(pluck(hz(nt), 2.4, 0.25), b * bar + st * beat, 0.22)
    phrase = [(0, "E4", 2), (2, "D4", 1), (3, "C4", 1), (4, "B3", 3), (8, "C4", 1.5), (9.5, "D4", 0.5), (10, "E4", 2), (12, "A3", 4)]
    for start in (16, 48):
        for st, nt, ln in phrase:
            tr.add(flute(hz(nt), ln * beat, 0.12), start + st, 0.22)
    return tr.finish(0.5, 3.2)


def marsh() -> np.ndarray:
    """E 弗里吉亚，56 拍每分：空五度持续音 + 芦苇沙沙声 + 带气声的木笛片段，16 小节"""
    beat = 60 / 56
    bar = beat * 4
    tr = Track(bar * 16)
    tr.add(drone(hz("E2"), bar * 16), 0, 0.22)
    tr.add(rustle(bar * 16), 0, 0.08)
    pads = [["E3", "B3"], ["F3", "C4"], ["E3", "B3"], ["D3", "A3"]]
    for b in range(0, 16, 2):
        tr.add(pad([hz(n) for n in pads[(b // 2) % 4]], bar * 2.1, 600), b * bar, 0.3)
    frags = [
        (2, [(0, "B4", 1.5), (1.5, "C5", 0.5), (2, "B4", 3)]),
        (5, [(0, "G4", 1), (1, "F4", 1), (2, "E4", 4)]),
        (9, [(0, "E5", 2), (2, "D5", 1), (3, "C5", 1), (4, "B4", 4)]),
        (13, [(0, "F4", 1), (1, "G4", 1), (2, "A4", 1), (3, "G4", 1), (4, "F4", 2), (6, "E4", 3)]),
    ]
    for b, notes in frags:
        for st, nt, ln in notes:
            tr.add(flute(hz(nt), ln * beat, 0.22), b * bar + st * beat, 0.26)
    for b in range(16):                                     # 远处的低音拨弦，像有人在水边拨了一下
        if b % 3 == 1:
            tr.add(pluck(hz("E2"), 3.0, 0.15), b * bar + beat * 2, 0.25)
    return tr.finish(0.55, 3.6)


def keep() -> np.ndarray:
    """D 小调，64 拍每分：弦垫 Dm–Bb–Gm–A + 每小节第一拍的低鼓 + 拨弦低音，16 小节"""
    beat = 60 / 64
    bar = beat * 4
    tr = Track(bar * 16)
    chords = [["D3", "F3", "A3"], ["Bb2", "D3", "F3"], ["G2", "Bb2", "D3"], ["A2", "C#3", "E3"]]
    bass = ["D2", "Bb1", "G1", "A1"]
    for b in range(16):
        k = b % 4
        tr.add(pad([hz(n) for n in chords[k]], bar * 1.02, 800), b * bar, 0.5)
        tr.add(drum(1.2, 62), b * bar, 0.45)
        if b % 2 == 1:
            tr.add(drum(0.6, 80, 0.2), b * bar + beat * 2.5, 0.2)
        tr.add(pluck(hz(bass[k]), bar * 0.9, 0.2), b * bar, 0.45)
        tr.add(pluck(hz(bass[k]) * 2, beat * 1.5, 0.3), b * bar + beat * 2, 0.25)
    line = [(0, "A4", 2), (2, "G4", 1), (3, "F4", 1), (4, "D4", 3), (7, "E4", 1), (8, "F4", 2), (10, "E4", 1), (11, "D4", 1), (12, "C#4", 4),
            (16, "D4", 1), (17, "F4", 1), (18, "A4", 2), (20, "Bb4", 3), (23, "A4", 1), (24, "G4", 2), (26, "F4", 1), (27, "E4", 1), (28, "D4", 4)]
    for start_bar in (4, 12):
        for st, nt, ln in line:
            if st >= 16 and start_bar == 12:
                break
            tr.add(flute(hz(nt), ln * beat, 0.06), start_bar * bar + st * beat, 0.26)
    return tr.finish(0.4, 2.6)


def battle() -> np.ndarray:
    """G 小调，100 拍每分：战鼓 + 低音铜管固定音型 + 弦垫，16 小节"""
    beat = 60 / 100
    bar = beat * 4
    tr = Track(bar * 16)
    ost = ["G2", "G2", "Bb2", "A2", "G2", "G2", "D3", "C3"]
    chords = [["G2", "Bb2", "D3"], ["Eb2", "G2", "Bb2"], ["C3", "Eb3", "G3"], ["D3", "F#3", "A3"]]
    for b in range(16):
        t0 = b * bar
        tr.add(pad([hz(n) for n in chords[(b // 2) % 4]], bar * 1.02, 1100), t0, 0.35)
        for k in range(8):
            tr.add(brass(hz(ost[k]), beat * 0.45), t0 + k * beat / 2, 0.3)
        for k, (st, f, g) in enumerate([(0, 58, 0.6), (1, 90, 0.3), (1.5, 90, 0.25), (2, 58, 0.55), (3, 90, 0.3), (3.5, 110, 0.25)]):
            tr.add(drum(0.7, f, 0.45), t0 + st * beat, g)
    return tr.finish(0.25, 1.8)


PIECES = {"town": town, "night": night, "marsh": marsh, "keep": keep, "battle": battle}


def encode(st: np.ndarray, path: str) -> None:
    pcm = (np.clip(st, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        name = tmp.name
    with wave.open(name, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", name, "-c:a", "libvorbis", "-q:a", "1", "-fflags", "+bitexact", "-flags:a", "+bitexact", path], check=True)
    os.unlink(name)


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "music")
    os.makedirs(out, exist_ok=True)
    for name, fn in PIECES.items():
        st = fn()
        path = os.path.join(out, name + ".ogg")
        encode(st, path)
        print("%s  %.1f 秒  %d KB" % (name, len(st) / SR, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
