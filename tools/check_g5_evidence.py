"""Extract and independently check the evidence from a real G5 headless run."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def main(directory: Path) -> None:
    stdout = (directory / "headless_tests.stdout.txt").read_text(encoding="utf-8-sig")
    evidence = {}
    for label, filename in [
        ("CODEC", "codec.json"), ("STORE", "store.json"),
        ("SNAPSHOT", "snapshot.json"), ("SESSION", "session.json"),
        ("CONTINUATION", "continuations.json"),
    ]:
        prefix = f"G5_{label}_EVIDENCE="
        lines = [line[len(prefix):] for line in stdout.splitlines() if line.startswith(prefix)]
        require(len(lines) == 1, f"Expected exactly one {prefix} line")
        evidence[label] = json.loads(lines[0])
        (directory / filename).write_text(lines[0] + "\n", encoding="utf-8")

    for label in ("CODEC", "SNAPSHOT"):
        item = evidence[label]
        require(item["checks"] > 0 and item["failures"] == [], f"{label} failed or did not run")
    require(evidence["STORE"]["passed"] is True, "Filesystem/profile suite failed")
    require(set(evidence["STORE"]["hooks"]) == {
        "fail_write", "truncate_temp", "fail_after_backup", "fail_rename"
    }, "Missing file replacement failure boundary")
    session = evidence["SESSION"]
    require(session["failures"] == [], "Public session suite failed")
    faults = session["faults"]
    require(len(faults) == 6 and {(x["autosave"], x["boundary"]) for x in faults} == {
        (mode, boundary) for mode in (False, True) for boundary in (1, 2, 3)
    }, "Expected three commit failures in both autosave modes")
    continuations = evidence["CONTINUATION"]
    require(len(continuations) == 2 and {x["autosave"] for x in continuations} == {False, True},
            "Both autosave modes must finish a semester")
    for item in continuations:
        initial = item["initial"]
        require(item["initial_hash"] == initial["checksum"], "Wrong initial snapshot identity")
        control, resumed = item["control_final"], item["resumed_final"]
        require(canonical(control) == canonical(resumed), "Interrupted and control snapshots differ")
        require(set(control["random_state"]["streams"]) == {"map", "reward", "event", "battle"},
                "Four independent streams required")
        for snapshot in (initial, control, resumed):
            body = {k: v for k, v in snapshot.items() if k != "checksum"}
            checksum = hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()
            require(checksum == snapshot["checksum"], "Independent checksum mismatch")
        payload = control["payload"]
        require(payload["run"]["outcome"] == "won" and len(payload["run"]["node_path"]) == 6,
                "Semester was not completed")
        require(payload["terminal_summary"] is not None and payload["profile_merge_pending"] is False,
                "Terminal commit was not finalized")
    require(session["seed"] == "42" and len(session["commands"]) > 0 and len(session["roundtrips"]) > 0,
            "Missing reproducible commands or stable roundtrips")
    summary = {
        "codec_checks": evidence["CODEC"]["checks"],
        "snapshot_checks": evidence["SNAPSHOT"]["checks"],
        "codec_boundaries": len(evidence["CODEC"]["boundaries"]),
        "continuation_modes": 2, "commit_failure_cases": len(faults),
        "stable_roundtrips": len(session["roundtrips"]),
        "recorded_commands": len(session["commands"]),
        "independent_checksums": "passed", "failures": [],
    }
    (directory / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main(Path(sys.argv[1]))
    except (ValueError, KeyError, TypeError, OSError, IndexError) as exc:
        print(f"G5 evidence invalid: {exc}", file=sys.stderr)
        sys.exit(1)
