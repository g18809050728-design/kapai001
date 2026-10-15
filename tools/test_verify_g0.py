"""Exercise the document gate against real corrupted copies, not game rules."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    root = Path(__file__).resolve().parents[1]
    script = root / "tools" / "verify_g0.py"
    run_id = "g0-negative-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    evidence = root / "artifacts" / "verification" / run_id
    evidence.mkdir(parents=True, exist_ok=False)
    temporary = Path(tempfile.mkdtemp(prefix="ddl-g0-audit-"))
    cases = [
        ("control", 0, None, "Current documents; full-only Q-007 and G1 implementation do not block G0"),
        ("bad_link", 1, "LINK", "Append an inline missing file link to README"),
        ("source_drift", 1, "SHA-256", "Append a byte to the adopted project plan without updating its hash"),
        ("extra_content", 1, "exact ID set", "Add full-only A24 to the MVP enabled relic IDs"),
        ("bad_map_edge", 1, "adjacent-layer", "Replace the layer-1 next IDs with a direct boss edge"),
        ("missing_case", 1, "coverage", "Remove T01 from registered rule cases"),
        ("numeric_drift", 1, "value absent/different", "Change the registered draw_per_round from 5 to 6"),
        ("open_mvp_rule", 2, "MVP rule decision open", "Reopen Q-005 as an unresolved MVP rule"),
        ("documents_only", 0, None, "Same unresolved Q-005, but explicitly request only document checks"),
    ]
    results = []
    for name, expected, diagnostic, mutation in cases:
        fixture = temporary / name
        fixture.mkdir()
        for dirname in ["docs", "动作或者图片描述", "tools"]:
            if (root / dirname).is_dir():
                shutil.copytree(root / dirname, fixture / dirname)
        for filename in ["README.md", "AGENTS.md", "agent.md", "实施计划与验收基线.md"]:
            shutil.copy2(root / filename, fixture / filename)
        # Copy only linked evidence files, not the entire history of artifacts.
        for document in fixture.rglob("*.md"):
            original = root / document.relative_to(fixture)
            for match in re.finditer(r"\[[^\]]*\]\((<[^>]+>|[^\s)]+)", document.read_text(encoding="utf-8-sig")):
                target = (original.parent / match[1].strip("<>").split("#", 1)[0]).resolve()
                try:
                    relative = target.relative_to(root / "artifacts")
                except ValueError:
                    continue
                if target.is_file():
                    destination = fixture / "artifacts" / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(target, destination)
        baseline_path = fixture / "docs" / "baselines" / "g0.json"
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        if name == "bad_link":
            with (fixture / "README.md").open("a", encoding="utf-8") as output:
                output.write("\n[missing](missing-document.md)\n")
        elif name == "source_drift":
            path = fixture / baseline["sources"][0]["path"]
            path.write_bytes(path.read_bytes() + b"\n")
        elif name == "extra_content":
            baseline["scope"]["enabled_by_kind"]["relic"].append("A24")
        elif name == "bad_map_edge":
            baseline["scope"]["map_topology"]["nodes"][0]["next_ids"] = ["t1l6_boss"]
        elif name == "missing_case":
            baseline["scope"]["rule_cases"] = [x for x in baseline["scope"]["rule_cases"] if x["id"] != "T01"]
        elif name == "numeric_drift":
            next(x for x in baseline["scope"]["numeric_bindings"] if x["config_key"] == "battle.draw_per_round")["expected"] = 6
        elif name in {"open_mvp_rule", "documents_only"}:
            decision = baseline["rule_decisions"][0]
            decision.update(status="open", confirmed_date=None, resolution=None,
                            blocking_scope="campus_mvp", blocking_stage="G0")
        baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        command = [sys.executable, str(script), "--root", str(fixture), "--run-id", "test-" + name]
        if name == "documents_only":
            command.append("--documents-only")
        completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=30)
        fixture_report = fixture / "artifacts" / "verification" / ("test-" + name)
        shutil.copytree(fixture_report, evidence / name)
        (evidence / name / "process_stdout.txt").write_text(completed.stdout, encoding="utf-8")
        (evidence / name / "process_stderr.txt").write_text(completed.stderr, encoding="utf-8")
        passed = completed.returncode == expected and (diagnostic is None or diagnostic in completed.stdout)
        results.append(dict(name=name, mutation=mutation, expected_exit=expected,
                            actual_exit=completed.returncode, diagnostic=diagnostic, passed=passed,
                            baseline_sha256=hashlib.sha256(baseline_path.read_bytes()).hexdigest()))
    report = dict(cases=results,passed=sum(r["passed"] for r in results),total=len(results),
                  command=[sys.executable,str(Path(__file__).resolve())],
                  harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  verifier_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),
                  python=sys.version,temporary_fixture_root=str(temporary),
                  scope="Document checker regression only; no gameplay or Godot tests")
    (evidence / "report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    output = f"Document checker regression: {report['passed']}/{report['total']} passed\nEvidence: {evidence}\n"
    (evidence / "stdout.txt").write_text(output,encoding="utf-8")
    code = 0 if report["passed"] == report["total"] else 1
    (evidence / "exit_code.txt").write_text(str(code)+"\n",encoding="utf-8")
    print(output,end="")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
