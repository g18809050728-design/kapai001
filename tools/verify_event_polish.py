"""Exact-input Godot runner for event art and remaining button refinement."""
import hashlib
from pathlib import Path
import verify_character_integration as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / 'artifacts/verification/event-polish-20261115'
original_inputs = runner.inputs


def inputs():
    result = original_inputs()
    for folder in ['assets/art/events', 'assets/art/enemies']:
        for p in (ROOT / folder).rglob('*'):
            if p.is_file() and p.suffix in ['.png', '.json']:
                result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ['event_polish_fixtures.gd', 'capture_event_polish.gd', 'verify_event_polish.py',
                 'build_event_polish.py', 'run_event_polish.gd']:
        p = ROOT / 'tools' / name
        if p.is_file():
            result[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


runner.inputs = inputs

if __name__ == '__main__':
    raise SystemExit(runner.main())
