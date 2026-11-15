"""Reuse the retained Godot runner and additionally hash version 8 inputs."""
from pathlib import Path
import hashlib
import json
import os
import sys

import verify_actor_rig_pilot as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / os.environ.get("CAMPUS_ACTOR_EVIDENCE", "artifacts/verification/actor-proportions-20261115")


def main():
    result = runner.main()
    record = (runner.EVIDENCE / sys.argv[1]).with_suffix(".run.json")
    data = json.loads(record.read_text(encoding="utf-8"))
    paths = [p for root in ("assets/art/actor-proportions", "assets/art/actor-party")
             for p in (ROOT / root).rglob("*") if p.suffix in (".json", ".png")]
    paths += [ROOT / name for name in (
        "tools/build_actor_proportions.py", "tools/run_actor_proportions_pilot.gd",
        "tools/render_actor_proportions_probe.gd", "tools/verify_actor_proportions.py",
        "tools/run_actor_party_pilot.gd", "tools/start_actor_party.ps1")]
    data["inputs"].update({p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in paths})
    record.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
