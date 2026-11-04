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
SEED = 20261104


def rng_for(name: str) -> random.Random:
    return random.Random(f"{SEED}:{name}")


def sample_count(duration: float) -> int:
    return max(1, int(round(RATE * duration)))


def white(count: int, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]


def _frequency(freq, t: float) -> float:
    return float(freq(t)) if callable(freq) else float(freq)


def tone(freq, duration: float, tau: float, attack: float = 0.002, kind: str = "sine") -> list[float]:
    count = sample_count(duration)
    env = perc_env(count, attack, tau)
    out: list[float] = []
    phase = 0.0
    for index in range(count):
        t = index / RATE
        phase += 2.0 * math.pi * _frequency(freq, t) / RATE
        if kind == "triangle":
            value = (2.0 / math.pi) * math.asin(math.sin(phase))
        elif kind == "saw":
            value = 2.0 * (phase / (2.0 * math.pi) - math.floor(phase / (2.0 * math.pi) + 0.5))
        else:
            value = math.sin(phase)
        out.append(value * env[index])
    return out


def perc_env(count: int, attack: float = 0.002, tau: float = 0.05) -> list[float]:
    attack_samples = max(1, int(attack * RATE))
    return [
        (index / attack_samples) if index < attack_samples else math.exp(-(index - attack_samples) / (RATE * tau))
        for index in range(count)
    ]


def swell_env(count: int, power: float = 0.7) -> list[float]:
    return [((index + 1) / count) ** power for index in range(count)]


def lowpass(samples: list[float], alpha: float) -> list[float]:
    out: list[float] = []
    value = 0.0
    for sample in samples:
        value += alpha * (sample - value)
        out.append(value)
    return out


def highpass(samples: list[float], alpha: float) -> list[float]:
    low = lowpass(samples, alpha)
    return [sample - low[index] for index, sample in enumerate(samples)]


def _svf(samples: list[float], cutoff, q: float, mode: str) -> list[float]:
    low = 0.0
    band = 0.0
    damp = 1.0 / max(0.1, q)
    out: list[float] = []
    for index, sample in enumerate(samples):
        t = index / RATE
        freq = min(max(_frequency(cutoff, t), 30.0), RATE / 6.0)
        f = 2.0 * math.sin(math.pi * freq / RATE)
        high = sample - low - damp * band
        band += f * high
        low += f * band
        out.append(low if mode == "low" else band if mode == "band" else high)
    return out


def noise_layer(
    duration: float,
    rng: random.Random,
    cutoff=None,
    q: float = 1.0,
    tau: float = 0.05,
    attack: float = 0.002,
    mode: str = "band",
    am_hz: float = 0.0,
) -> list[float]:
    count = sample_count(duration)
    samples = white(count, rng)
    if cutoff is not None:
        samples = _svf(samples, cutoff, q, mode)
    env = perc_env(count, attack, tau)
    out: list[float] = []
    for index, sample in enumerate(samples):
        mod = 0.5 + 0.5 * math.sin(2.0 * math.pi * am_hz * index / RATE) if am_hz > 0 else 1.0
        out.append(sample * env[index] * mod)
    return out


def add(buffer: list[float], start: float, layer: list[float], gain: float = 1.0) -> None:
    offset = int(start * RATE)
    for index, sample in enumerate(layer):
        target = offset + index
        if 0 <= target < len(buffer):
            buffer[target] += sample * gain


def fade_edges(samples: list[float], fade_in: float = 0.001, fade_out: float = 0.006) -> list[float]:
    count = len(samples)
    out = samples[:]
    in_count = min(count, int(fade_in * RATE))
    out_count = min(count, int(fade_out * RATE))
    for index in range(in_count):
        out[index] *= index / in_count
    for index in range(out_count):
        out[count - 1 - index] *= index / out_count
    return out


def reverb(samples: list[float], mix: float, feedback: float = 0.32) -> list[float]:
    count = len(samples)
    wet = [0.0] * count
    for delay_ms, gain in ((29.7, 0.44), (37.1, 0.37), (41.1, 0.31)):
        delay = max(1, int(RATE * delay_ms / 1000.0))
        for index in range(delay, count):
            wet[index] += (samples[index - delay] + wet[index - delay] * feedback) * gain
    return [samples[index] + wet[index] * mix for index in range(count)]


def normalize(samples: list[float], peak: float) -> list[float]:
    current = max(abs(sample) for sample in samples)
    if current < 1e-9:
        return samples
    gain = peak / current
    return [max(-1.0, min(1.0, sample * gain)) for sample in samples]


def write(name: str, samples: list[float], rng: random.Random) -> None:
    data = bytearray()
    for sample in samples:
        dither = (rng.random() - rng.random()) / 32768.0
        value = max(-1.0, min(1.0, sample + dither))
        data += struct.pack("<h", int(value * 32767.0))
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)


def make(name: str, duration: float, builder, peak: float, wet: float = 0.0) -> None:
    rng = rng_for(name)
    buffer = [0.0] * sample_count(duration)
    builder(buffer, rng)
    dc_alpha = 1.0 - math.exp(-2.0 * math.pi * 20.0 / RATE)
    buffer = highpass(buffer, dc_alpha)
    if wet > 0.0:
        buffer = reverb(buffer, wet)
    buffer = fade_edges(buffer)
    write(name, normalize(buffer, peak), rng)


def build_ui_hover(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.06, rng, 3200, q=1.8, tau=0.011), 0.9)
    add(buffer, 0.0, tone(2450, 0.03, 0.007, attack=0.001), 0.25)


def build_ui_click(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.04, rng, 2600, q=1.1, tau=0.009, attack=0.001), 1.0)
    add(buffer, 0.0, tone(lambda t: 195.0 - 45.0 * t / 0.09, 0.09, 0.026), 0.85)
    add(buffer, 0.0, tone(820, 0.03, 0.010, attack=0.001), 0.3)


def build_ui_back(buffer: list[float], rng: random.Random) -> None:
    count = len(buffer)
    slide = _svf(white(count, rng), lambda t: 3600.0 - 2800.0 * t / 0.1, 1.2, "band")
    swell = swell_env(count, 0.8)
    add(buffer, 0.0, [slide[index] * swell[index] for index in range(count)], 0.9)
    add(buffer, 0.01, tone(lambda t: 680.0 - 260.0 * t / 0.09, 0.09, 0.05), 0.35)


def build_detail_open(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.09, rng, lambda t: 1700.0 + 2200.0 * t / 0.09, q=1.2, tau=0.035, attack=0.004), 0.75)
    add(buffer, 0.03, tone(1174.66, 0.13, 0.055), 0.4)
    add(buffer, 0.075, tone(1567.98, 0.12, 0.055), 0.32)


def build_error(buffer: list[float], rng: random.Random) -> None:
    for start, freq in ((0.0, 148.0), (0.075, 116.0)):
        add(buffer, start, tone(freq, 0.09, 0.034), 0.8)
        add(buffer, start, noise_layer(0.06, rng, 420, q=0.8, tau=0.026, mode="low"), 0.25)
    add(buffer, 0.0, tone(92, 0.16, 0.06), 0.35)


def build_choice(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.04, rng, 2500, q=1.4, tau=0.012, attack=0.001), 0.35)
    add(buffer, 0.01, tone(880, 0.10, 0.060, kind="triangle"), 0.55)
    add(buffer, 0.08, tone(1108.73, 0.13, 0.070, kind="triangle"), 0.5)


def build_card_draw(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.13, rng, lambda t: 1400.0 + 3000.0 * t / 0.13, q=1.5, tau=0.060, attack=0.005), 0.95)
    add(buffer, 0.045, tone(1318.51, 0.07, 0.024), 0.38)


def build_card_play(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.045, rng, 4200, q=1.0, tau=0.010, attack=0.001), 0.8)
    add(buffer, 0.0, tone(lambda t: 132.0 - 64.0 * t / 0.24, 0.24, 0.070), 0.95)
    add(buffer, 0.012, noise_layer(0.17, rng, lambda t: 2700.0 - 1500.0 * t / 0.17, q=1.1, tau=0.040), 0.65)
    add(buffer, 0.035, tone(523.25, 0.13, 0.075), 0.3)
    add(buffer, 0.035, tone(783.99, 0.12, 0.065), 0.16)


def build_card_discard(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.19, rng, lambda t: 3900.0 - 3000.0 * t / 0.19, q=1.2, tau=0.085, attack=0.008), 0.9)
    add(buffer, 0.0, tone(lambda t: 230.0 - 60.0 * t / 0.19, 0.14, 0.045), 0.35)


def build_card_exhaust(buffer: list[float], rng: random.Random) -> None:
    for index in range(8):
        start = 0.012 * index + rng.uniform(0.0, 0.018)
        add(buffer, start, noise_layer(0.08, rng, rng.uniform(2400.0, 5200.0), q=1.8, tau=0.018, attack=0.001), 0.45)
    add(buffer, 0.0, noise_layer(0.30, rng, 620, q=0.9, tau=0.120, attack=0.010, mode="low", am_hz=18.0), 0.5)


def build_status(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, tone(2093.0, 0.13, 0.040), 0.42)
    add(buffer, 0.0, tone(3136.0, 0.11, 0.030), 0.24)
    add(buffer, 0.005, tone(4186.0, 0.08, 0.020), 0.14)
    add(buffer, 0.0, noise_layer(0.03, rng, 5200, q=2.0, tau=0.008, attack=0.001), 0.18)


def build_task_hit(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, tone(lambda t: 112.0 - 42.0 * t / 0.26, 0.26, 0.065), 0.9)
    add(buffer, 0.0, noise_layer(0.21, rng, lambda t: 1300.0 - 700.0 * t / 0.21, q=0.9, tau=0.075, attack=0.004, mode="low"), 0.65)
    add(buffer, 0.008, noise_layer(0.15, rng, lambda t: 3000.0 + 1800.0 * t / 0.15, q=2.2, tau=0.075, attack=0.003, am_hz=28.0), 0.4)


def build_task_done(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, tone(94, 0.22, 0.050), 0.8)
    add(buffer, 0.0, noise_layer(0.04, rng, 3600, q=1.0, tau=0.012, attack=0.001), 0.55)
    add(buffer, 0.0, noise_layer(0.14, rng, 1800, q=0.9, tau=0.040, mode="low"), 0.45)
    for freq, gain in ((523.25, 0.20), (659.25, 0.18), (783.99, 0.17), (1046.50, 0.12)):
        add(buffer, 0.06, tone(freq, 0.32, 0.150), gain)


def build_ddl(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.025, rng, 3800, q=1.2, tau=0.007, attack=0.001), 0.55)
    add(buffer, 0.0, tone(1850, 0.045, 0.010, attack=0.001), 0.38)
    add(buffer, 0.004, tone(255, 0.09, 0.034), 0.34)


def build_paper(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.18, rng, lambda t: 3200.0 + 2000.0 * t / 0.18, q=2.0, tau=0.100, attack=0.005, am_hz=14.0), 0.55)
    add(buffer, 0.025, noise_layer(0.10, rng, lambda t: 1100.0 + 1900.0 * t / 0.10, q=1.3, tau=0.045), 0.65)
    add(buffer, 0.085, tone(1318.51, 0.16, 0.070), 0.3)


def build_chapter(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.13, rng, lambda t: 1000.0 + 2300.0 * t / 0.13, q=1.4, tau=0.070, attack=0.006), 0.8)
    add(buffer, 0.115, tone(106, 0.09, 0.040), 0.55)
    add(buffer, 0.135, noise_layer(0.08, rng, lambda t: 2600.0 - 1400.0 * t / 0.08, q=1.2, tau=0.030), 0.55)


def build_victory(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.22, rng, lambda t: 4200.0 - 3000.0 * t / 0.22, q=1.2, tau=0.080, attack=0.010), 0.55)
    for index, freq in enumerate((523.25, 659.25, 783.99, 1046.50)):
        add(buffer, 0.08 + index * 0.1, tone(freq, 0.40, 0.200), 0.28)
    for freq, gain in ((523.25, 0.16), (659.25, 0.14), (783.99, 0.13), (1046.50, 0.11)):
        add(buffer, 0.47, tone(freq, 0.45, 0.320), gain)


def build_defeat(buffer: list[float], rng: random.Random) -> None:
    add(buffer, 0.0, noise_layer(0.32, rng, 520, q=0.9, tau=0.140, attack=0.008, mode="low"), 0.5)
    add(buffer, 0.0, tone(lambda t: 196.0 - 35.0 * t + 1.8 * math.sin(2.0 * math.pi * 4.5 * t), 0.55, 0.240), 0.42)
    add(buffer, 0.15, tone(lambda t: 146.83 - 12.0 * t, 0.72, 0.340), 0.45)
    add(buffer, 0.08, tone(98.0, 0.72, 0.400), 0.36)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    specs = (
        ("ui_hover", 0.06, build_ui_hover, 0.16, 0.0),
        ("ui_click", 0.09, build_ui_click, 0.46, 0.0),
        ("ui_back", 0.10, build_ui_back, 0.36, 0.0),
        ("detail_open", 0.20, build_detail_open, 0.40, 0.0),
        ("error", 0.16, build_error, 0.42, 0.0),
        ("choice", 0.21, build_choice, 0.40, 0.0),
        ("card_draw", 0.16, build_card_draw, 0.44, 0.0),
        ("card_play", 0.24, build_card_play, 0.55, 0.0),
        ("card_discard", 0.20, build_card_discard, 0.42, 0.0),
        ("card_exhaust", 0.34, build_card_exhaust, 0.50, 0.0),
        ("status", 0.18, build_status, 0.34, 0.0),
        ("task_hit", 0.26, build_task_hit, 0.54, 0.0),
        ("task_done", 0.45, build_task_done, 0.54, 0.0),
        ("ddl", 0.18, build_ddl, 0.32, 0.0),
        ("paper", 0.28, build_paper, 0.45, 0.0),
        ("chapter", 0.26, build_chapter, 0.45, 0.0),
        ("victory", 0.95, build_victory, 0.58, 0.22),
        ("defeat", 0.95, build_defeat, 0.52, 0.20),
    )
    for spec in specs:
        make(*spec)
    print(f"generated {len(list(OUT.glob('*.wav')))} sfx in {OUT}")


if __name__ == "__main__":
    main()
