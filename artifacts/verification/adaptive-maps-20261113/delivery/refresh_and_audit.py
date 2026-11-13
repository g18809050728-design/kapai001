"""Refresh the observed snapshot and audit only newly introduced local links."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), "-c", "core.quotepath=false", *args], encoding="utf-8", stderr=subprocess.PIPE)


def links(source):
    result = set()
    for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", source):
        target = match[1].strip("<>")
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
            continue
        result.add(unquote(target.split("#", 1)[0]))
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    state_path = ROOT / "docs/baselines/current-state.json"
    before = OUT / "observed-state-before.json"
    if not before.exists():
        before.write_bytes(state_path.read_bytes())
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state["project_date"] = "2026-11-13"
    manifest_path = ROOT / state["manifest"]["path"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    state["manifest"]["sha256"] = digest(manifest_path)
    state["enabled_definition_count"] = sum(map(len, manifest["enabled"].values()))
    enabled_definitions = {}
    for kind, item in state["definitions"].items():
        path = ROOT / item["path"]
        definitions = json.loads(path.read_text(encoding="utf-8-sig"))
        item.update(sha256=digest(path), enabled_count=len(manifest["enabled"][kind]),
                    enabled_ids=manifest["enabled"][kind], definition_count_in_file=len(definitions))
        enabled_definitions[kind] = {d["id"]: d for d in definitions if d["id"] in manifest["enabled"][kind]}
    canonical_manifest = json.loads(json.dumps(manifest))
    for values in canonical_manifest["enabled"].values():
        values.sort()
    canonical = json.dumps({"manifest": canonical_manifest, "definitions": enabled_definitions}, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    state["manifest"]["content_hash"] = hashlib.sha256(canonical.encode()).hexdigest()
    if "campaign_version" not in state["annual_maps"]:
        state["legacy_annual_maps"] = state["annual_maps"]
    state["annual_maps"] = dict(unit="academic_year", count=4, campaign_version=2, map_version=1,
        generation="one_year_at_a_time_after_rewards_and_required_decisions", initial_generated_years=1,
        nodes="seed_dependent", layers=[12, 12, 14, 14], route_layers=52, relic_slots=3,
        relic_rewards=8, annual_grand_rewards=4, minimum_branch_independent_nodes=3,
        minimum_shops_per_route=1, minimum_recovery_per_route=2, minimum_year4_thesis_opportunities=2)
    for relative in list(state["source_sha256"]) + ["docs/plans/2026-11-13-adaptive-annual-maps.md", "docs/逐年随机地图实施记录_20261113.md", "动作或者图片描述/逐年随机地图需求_20261113.md"]:
        if (ROOT / relative).exists():
            state["source_sha256"][relative] = digest(ROOT / relative)
    state["card_art"]["texture_index_sha256"] = digest(ROOT / state["card_art"]["texture_index"])
    for label, relative in {"adaptive_rules": "final-rules/summary.json", "adaptive_ui": "final-ui-clean/summary.json", "adaptive_import": "final-import-clean/summary.json", "adaptive_visual": "final-visual/summary.json"}.items():
        path = OUT.parent / relative
        if path.exists():
            state["evidence"][label] = path.relative_to(ROOT).as_posix()
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    changed = set(git("diff", "--name-only", "HEAD").splitlines())
    changed.update(git("ls-files", "--others", "--exclude-standard").splitlines())
    new_links = []
    issues = []
    docs = []
    for relative in sorted(changed):
        if not relative.endswith(".md"):
            continue
        path = ROOT / relative
        if not path.is_file():
            continue
        docs.append(relative)
        old = subprocess.run(["git", "-C", str(ROOT), "show", "HEAD:" + relative], capture_output=True, encoding="utf-8")
        prior = links(old.stdout) if old.returncode == 0 else set()
        for target in sorted(links(path.read_text(encoding="utf-8-sig")) - prior):
            new_links.append({"document": relative, "target": target})
            if target and not (path.parent / target).exists():
                issues.append("Missing new link: " + relative + " -> " + target)
    global_report_path = ROOT / "artifacts/verification/four-year-20261104/doc-check/summary.json"
    global_issues = json.loads(global_report_path.read_text(encoding="utf-8")).get("issues", []) if global_report_path.exists() else []
    report = dict(utc=datetime.now(timezone.utc).isoformat(), command="python " + str(Path(__file__).relative_to(ROOT)),
        scope="new links in changed/new documents; historical missing evidence remains separate", documents=docs,
        new_links=new_links, issues=issues, historical_global_issue_count=len(global_issues),
        historical_global_issues=global_issues, exit_code=int(bool(issues)),
        observed_content_hash=state["manifest"]["content_hash"], enabled_definitions=state["enabled_definition_count"],
        input_sha256={relative: digest(ROOT / relative) for relative in docs})
    (OUT / "doc-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "git-status.txt").write_text(git("status", "--short"), encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("exit_code", "issues", "historical_global_issue_count", "observed_content_hash", "enabled_definitions")}, ensure_ascii=False))
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
