#!/usr/bin/env python3
"""Generate license-free placeholder SFX for the local prototype."""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/sfx"

random.seed(20261104)


def envelope(i: int, n: int, attack: float = 0.008, release: float = 0.04) -> float:
    t = i / RATE
    dur = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, max(0.0, (dur - t) / release)) if release > 0 else 1.0
    return a * r


def tone(freq: float, t: float) -> float:
    return math.sin(2.0 * math.pi * freq * t)


def lowpass(samples: list[float], alpha: float) -> list[float]:
    out = []
    value = 0.0
    for sample in samples:
        value += alpha * (sample - value)
        out.append(value)
    return out


def write(name: str, samples: list[float]) -> None:
    peak = max(1e-6, max(abs(x) for x in samples))
    scale = min(0.6 / peak, 1.0)
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x * scale)) * 32767)) for x in samples)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)


def make(name: str, dur: float, fn) -> None:
    n = int(RATE * dur)
    samples = []
    for i in range(n):
        t = i / RATE
        samples.append(fn(t, i, n) * envelope(i, n))
    write(name, samples)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    make("ui_hover", 0.05, lambda t, i, n: 0.12 * tone(1250, t))
    make("ui_click", 0.07, lambda t, i, n: 0.20 * tone(520, t) + 0.08 * random.uniform(-1, 1))
    make("ui_back", 0.09, lambda t, i, n: 0.18 * tone(700 - 300 * t / 0.09, t))
    make(
        "detail_open",
        0.18,
        lambda t, i, n: 0.10 * tone(880, t) + 0.06 * random.uniform(-1, 1),
    )
    paper = lowpass([random.uniform(-1, 1) for _ in range(int(RATE * 0.14))], 0.18)
    make("card_draw", 0.12, lambda t, i, n: 0.22 * paper[min(i, len(paper) - 1)])
    make(
        "card_play",
        0.16,
        lambda t, i, n: 0.18 * tone(220, t) + 0.10 * random.uniform(-1, 1),
    )
    make("card_discard", 0.10, lambda t, i, n: 0.18 * random.uniform(-1, 1) * (1 - t / 0.1))
    make(
        "card_exhaust",
        0.25,
        lambda t, i, n: 0.20 * tone(400 - 200 * t / 0.25, t) + 0.08 * random.uniform(-1, 1),
    )
    make("status", 0.12, lambda t, i, n: 0.16 * tone(880 - 220 * t / 0.12, t))
    make(
        "task_hit",
        0.14,
        lambda t, i, n: 0.22 * tone(120, t) + 0.10 * random.uniform(-1, 1),
    )
    make(
        "task_done",
        0.28,
        lambda t, i, n: 0.14 * (tone(523, t) + tone(659, t) + tone(784, t)),
    )
    make("ddl", 0.12, lambda t, i, n: 0.16 * tone(1000, t) if int(t * 12) % 2 == 0 else 0.0)
    make("paper", 0.20, lambda t, i, n: 0.12 * tone(660, t) + 0.05 * random.uniform(-1, 1))
    make(
        "chapter",
        0.16,
        lambda t, i, n: 0.12 * tone(440, t) + 0.06 * random.uniform(-1, 1),
    )
    make("choice", 0.12, lambda t, i, n: 0.14 * tone(740, t))
    make(
        "victory",
        0.60,
        lambda t, i, n: 0.10 * (tone(523, t) + tone(659, t) + tone(784, t) + tone(1046, t)),
    )
    make(
        "defeat",
        0.60,
        lambda t, i, n: 0.10 * (tone(392 - 60 * t, t) + tone(311 - 40 * t, t)),
    )
    make("error", 0.15, lambda t, i, n: 0.18 * tone(160, t) if t < 0.06 or t > 0.09 else 0.0)
    print(f"generated {len(list(OUT.glob('*.wav')))} sfx in {OUT}")


if __name__ == "__main__":
    main()
