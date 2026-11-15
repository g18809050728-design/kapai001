"""Exact-input Godot runs for this art-only batch, including all consumed card PNGs."""
import hashlib
from pathlib import Path
import verify_character_integration as runner

ROOT=Path(__file__).resolve().parents[1]
runner.EVIDENCE=ROOT/'artifacts/verification/card-style-20261115'
original_inputs=runner.inputs


def inputs():
    result=original_inputs()
    for directory in ['assets/cards','assets/art/enemies','assets/art/events']:
        for p in (ROOT/directory).rglob('*'):
            if p.is_file() and p.suffix in ['.png','.json']:
                result[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ['verify_card_style.py','capture_card_style.gd']:
        p=ROOT/'tools'/name
        if p.is_file(): result[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    p=ROOT/'docs/art/card-art-assets-v3.json'
    result[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    return result


runner.inputs=inputs
if __name__=='__main__':
    raise SystemExit(runner.main())
