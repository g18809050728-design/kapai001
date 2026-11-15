"""Record the complete enemy presentation inputs with the established Godot runner."""
import hashlib
from pathlib import Path

import verify_lin_polish as base

ROOT = Path(__file__).resolve().parents[1]
base.runner.EVIDENCE = ROOT / "artifacts/verification/enemy-roster-20261115"
original = base.inputs


def inputs():
    result = original()
    paths = [p for p in (ROOT / "assets/art/enemies").rglob("*") if p.suffix in (".png", ".json")]
    paths += [ROOT / "tools" / name for name in
              ("build_enemy_roster.py", "render_enemy_roster.gd", "verify_enemy_roster.py", "run_enemy_roster.gd",
               "render_enemy_sequences.gd", "audit_enemy_roster.py", "review_enemy_roster.py",
               "run_enemy_regressions.gd")]
    for path in paths:
        if path.is_file():
            result[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


base.inputs = inputs

if __name__ == "__main__":
    raise SystemExit(base.main())
