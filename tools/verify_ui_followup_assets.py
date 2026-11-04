"""Decode the new meal art and quiet WAV set; preserve metrics and original hashes."""
from __future__ import annotations

import hashlib
import json
import math
import struct
import wave
import zipfile
from io import BytesIO
from pathlib import Path

from PIL import Image
from generate_sfx import SPECS, synthesize

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/ui-followup-20261105"


def metrics(blob):
    with wave.open(BytesIO(blob)) as stream:
        params = [stream.getnchannels(), stream.getsampwidth(), stream.getframerate()]
        data = stream.readframes(stream.getnframes())
    samples = struct.unpack(f"<{len(data)//2}h", data)
    peak = max(abs(x) for x in samples) / 32768
    rms = math.sqrt(sum((x / 32768) ** 2 for x in samples) / len(samples))
    return dict(params=params, frames=len(samples), duration=len(samples)/params[2], peak=peak,
                rms=rms, clipped=sum(abs(x) >= 32767 for x in samples),
                endpoints=[samples[0], samples[-1]],
                max_sample_step=max(abs(a-b)/32768 for a,b in zip(samples,samples[1:])))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    failures = []
    clips = []
    with zipfile.ZipFile(OUT / "audio-before.zip") as old:
        for spec in SPECS:
            name = spec[0]
            path = ROOT / "assets/audio/sfx" / (name + ".wav")
            blob = path.read_bytes()
            current = metrics(blob)
            before = metrics(old.read(f"assets/audio/sfx/{name}.wav"))
            current["name"] = name
            current["sha256"] = hashlib.sha256(blob).hexdigest()
            current["previous_peak"] = before["peak"]
            current["previous_rms"] = before["rms"]
            with wave.open(str(path)) as wav:
                actual = wav.readframes(wav.getnframes())
            rebuilt = synthesize(*spec)
            current["deterministic"] = actual == struct.pack(f"<{len(rebuilt)}h", *rebuilt)
            if not (current["params"] == [1, 2, 44100] and current["clipped"] == 0
                    and current["peak"] <= .18 and current["rms"] <= .08
                    and current["endpoints"] == [0, 0] and current["deterministic"]
                    and current["peak"] < before["peak"] and current["rms"] < before["rms"]):
                failures.append(name)
            clips.append(current)
    art = ROOT / "assets/art/four-year/items/campus-meal.png"
    with Image.open(art) as image:
        image.load()
        dimensions = list(image.size)
        if dimensions != [1024, 1024]:
            failures.append("meal dimensions")
    manifest = json.loads((ROOT / "output/imagegen/campus-meal-20261105/manifest.json").read_text(encoding="utf-8"))
    for name, digest in manifest["files"].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
            failures.append("meal manifest mismatch: " + name)
    result = dict(status="passed" if not failures else "failed", clips=clips,
                  image=dict(dimensions=dimensions, sha256=hashlib.sha256(art.read_bytes()).hexdigest()),
                  failures=failures, subjective_listening="pending user acceptance")
    (OUT/"asset-verification.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(dict(status=result["status"], clips=len(clips), failures=failures)))
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
