"""Exact-input runs for the continuous, eight-item compendium."""
from pathlib import Path
import hashlib
import verify_character_integration as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / 'artifacts/verification/compendium-scroll-20261115'
original_inputs = runner.inputs


def inputs():
    result = original_inputs()
    for folder in ['assets/cards', 'assets/art/enemies', 'assets/art/events']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and p.suffix in ['.png', '.json']:
                result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ['verify_compendium_scroll.py', 'run_compendium.gd', 'compendium_lifecycle_probe.gd']:
        p = ROOT/'tools'/name
        result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


runner.inputs = inputs
if __name__ == '__main__':
    raise SystemExit(runner.main())
