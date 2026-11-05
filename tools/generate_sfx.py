#!/usr/bin/env python3
"""Deterministic quiet paper/wood SFX with rounded envelopes and no harsh sweeps."""
from __future__ import annotations

import json
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/sfx"
SEED = 20261105

# name, seconds, peak, filtered paper gain, (onset, note, weight) voices
SPECS = (
    ("ui_hover", .06, .025, .06, ((0, 330, 1),)),
    ("ui_click", .10, .065, .20, ((0, 262, 1),)),
    ("ui_back", .12, .060, .14, ((0, 220, 1),)),
    ("detail_open", .16, .055, .28, ((.02, 330, .7),)),
    ("error", .22, .090, .05, ((0, 220, 1), (.09, 196, .7))),
    ("choice", .24, .085, .10, ((0, 330, 1), (.08, 392, .7))),
    ("card_draw", .16, .055, .85, ((.02, 294, .15),)),
    ("card_play", .18, .115, .25, ((0, 196, 1), (.01, 392, .2))),
    ("card_discard", .16, .050, 1.0, ((0, 165, .1),)),
    ("card_exhaust", .22, .065, 1.0, ((0, 147, .12),)),
    ("status", .15, .045, .08, ((0, 349, .7),)),
    ("task_hit", .18, .105, .35, ((0, 147, 1),)),
    ("task_done", .34, .130, .08, ((0, 262, 1), (.09, 330, .8), (.18, 392, .6))),
    ("ddl", .18, .065, .20, ((0, 294, .8),)),
    ("paper", .20, .060, .90, ((.04, 330, .12),)),
    ("chapter", .20, .065, .70, ((.02, 247, .2),)),
    ("victory", .72, .170, .02, ((0, 262, 1), (.14, 330, .9), (.28, 392, .8), (.42, 523, .6))),
    ("defeat", .64, .135, .05, ((0, 262, .7), (.17, 220, .8), (.34, 175, .9))),
)


def lowpass(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    value = 0.0
    result = []
    for sample in samples:
        value += alpha * (sample - value)
        result.append(value)
    return result


def synthesize(name, duration, peak, paper_gain, voices):
    rng = random.Random(f"{SEED}:{name}")
    count = round(RATE * duration)
    noise = lowpass(lowpass([rng.uniform(-1, 1) for _ in range(count)], 1200), 1200)
    samples = [0.0] * count
    for index in range(count):
        t = index / RATE
        envelope = (1 - math.exp(-t / .009)) * math.exp(-t / (duration * .22))
        samples[index] = noise[index] * paper_gain * envelope
        for onset, frequency, weight in voices:
            elapsed = t - onset
            if elapsed < 0:
                continue
            attack = 1 - math.exp(-elapsed / .006)
            decay = math.exp(-elapsed / (.075 if duration < .4 else .105))
            tone = math.sin(2 * math.pi * frequency * elapsed)
            tone += .12 * math.sin(4 * math.pi * frequency * elapsed)
            samples[index] += weight * tone * attack * decay
    samples = lowpass(lowpass(samples, 1800), 1800)
    mean = sum(samples) / count
    for index in range(count):
        edge = min(1.0, index / (RATE * .006), (count - 1 - index) / (RATE * .025))
        samples[index] = (samples[index] - mean) * max(0, edge)
    highest = max(abs(x) for x in samples)
    gain = peak / highest if highest else 1.0
    return [round(x * gain * 32767) for x in samples]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {"version": "soft-paper-wood-v2", "seed": SEED, "sample_rate": RATE, "clips": []}
    for spec in SPECS:
        name, duration, peak, _, _ = spec
        samples = synthesize(*spec)
        with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(struct.pack(f"<{len(samples)}h", *samples))
        manifest["clips"].append({"name": name, "duration": duration, "peak_target": peak})
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(SPECS)} quiet clips in {OUT}")


if __name__ == "__main__":
    main()
