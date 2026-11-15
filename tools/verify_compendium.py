"""Exact-input Godot runner for the in-game card and monster compendium."""
import hashlib
from pathlib import Path
import verify_character_integration as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / 'artifacts/verification/compendium-20261115'
original_inputs = runner.inputs


def inputs():
    result = original_inputs()
    for folder in ['assets/art/enemies', 'assets/art/events']:
        for p in (ROOT / folder).rglob('*'):
            if p.is_file() and p.suffix in ['.png', '.json']:
                result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ['verify_compendium.py', 'run_compendium.gd', 'capture_compendium.gd', 'compendium_lifecycle_probe.gd', 'ui_compendium_dependency_probe.gd']:
        p = ROOT / 'tools' / name
        if p.is_file():
            result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


runner.inputs = inputs

if __name__ == '__main__':
    raise SystemExit(runner.main())
