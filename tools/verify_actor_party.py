"""Run exact Godot commands with new party resources included in evidence inputs."""
from pathlib import Path
import hashlib
import os
import verify_actor_rig_pilot as runner

ROOT = Path(__file__).resolve().parents[1]
runner.EVIDENCE = ROOT / os.environ.get("CAMPUS_ACTOR_EVIDENCE", "artifacts/verification/actor-party-20261115")


def main():
    # The existing runner retains environment, engine logs, exit code and errors.
    result = runner.main()
    import json
    import sys
    record = (runner.EVIDENCE / sys.argv[1]).with_suffix(".run.json")
    data = json.loads(record.read_text(encoding="utf-8"))
    paths = list((ROOT / "assets/art/actor-party").rglob("*.json"))
    paths += list((ROOT / "assets/art/actor-party").rglob("*.png"))
    paths += [ROOT / name for name in ("tools/build_actor_party.py", "tools/run_actor_party_pilot.gd", "tools/render_actor_party_probe.gd", "tools/start_actor_party.ps1", "tools/verify_actor_party.py")]
    data["inputs"].update({p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    record.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
