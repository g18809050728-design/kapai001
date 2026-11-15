"""Run the retained real-Godot verifier with exact P03 version10 inputs."""
import hashlib
import json
import os
from pathlib import Path
import sys

import verify_actor_rig_pilot as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / os.environ.get("CAMPUS_ACTOR_EVIDENCE", "artifacts/verification/actor-rebuild-20261115")


def main():
    paths = [p for folder in ("assets/art/actor-rebuild", "assets/art/actor-posture", "assets/art/actor-proportions", "assets/art/actor-party")
             for p in (ROOT / folder).rglob("*") if p.suffix in (".json", ".png")]
    paths += [p for name in ("build_actor_rebuild.py", "run_actor_rebuild_pilot.gd", "render_actor_rebuild_probe.gd",
                             "verify_actor_rebuild.py", "run_actor_party_pilot.gd", "start_actor_party.ps1")
              if (p := ROOT / "tools" / name).is_file()]
    digest = lambda: {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    before = digest()
    result = runner.main()
    after = digest()
    record = (runner.EVIDENCE / sys.argv[1]).with_suffix(".run.json")
    data = json.loads(record.read_text(encoding="utf-8"))
    data["inputs"].update(after)
    data["rebuild_inputs_before"] = before
    data["rebuild_inputs_changed_during_run"] = [p for p, sha in before.items() if after.get(p) != sha]
    record.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result or bool(data["rebuild_inputs_changed_during_run"])


if __name__ == "__main__":
    raise SystemExit(main())
