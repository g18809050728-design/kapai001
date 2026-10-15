"""Audit the frozen document baseline; never substitute for Godot tests."""
from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import platform
import re
import sys
from urllib.parse import unquote

REQUIREMENTS = {
    "ARCH-001", "CNT-001", "RNG-001", "CMD-001", "CMD-002", "CMD-003",
    "BAT-001", "RUN-001", "SAVE-001", "SAVE-002", "UI-001", "UI-DOC-001",
    "EXT-001", "PERF-001",
}
DESIGN = "docs/交大四年_DDL战争_统一设计文档.md"
RULES = "docs/交大四年_DDL战争_游戏规则书.md"
PLAN = "docs/交大四年_DDL战争_项目计划书.md"
CONTENT = "docs/内容层契约.md"
SOURCES = {
    "SRC-PLAN": (PLAN, "v1.1"), "SRC-RULES": (RULES, "v0.4"),
    "SRC-DESIGN": (DESIGN, "v1.1"),
    "SRC-IDEA": ("docs/交大四年_DDL战争_完整设计思路.md", "v0.1"),
}
EXPECTED_IDS = {
    "character": ["P01", "P04"],
    "card": [f"K{i:02}" for i in [*range(1, 9), 10, *range(12, 17), 19,
              *range(43, 47), *range(51, 54), 59, 60]] + ["X01"],
    "relic": ["A01", "A04", "A05", "A07", "A08", "A11", "A15", "A18"],
    "task": ["N01", "N02", "N03", "N04", "Q01", "B01"],
    "encounter": ["N01", "N02", "N03", "N04", "Q01", "B01"],
    "unit": ["F01", "F02", "F03", "F04"], "scene": ["L01", "L02", "L03"],
    "event": ["V01", "V03", "V04", "V10"],
    "status": ["inspiration", "compile", "anxiety", "procrastination",
               "drowsiness", "extra_requirements", "guard"],
    "ruleset": ["campus_v1"],
}
REMOVED = ["类与方法设计.md", "常量与规则配置.md", "战斗界面契约.md"]
FULL_CASES = {"T11", "T13", "T14", "T15", "RB-11"}
LAYER_KINDS = [["normal"], ["event", "normal"], ["shop"],
               ["normal", "elite"], ["rest"], ["boss"]]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table_rows(text: str) -> list[list[str]]:
    return [[cell.strip() for cell in line.strip().strip("|").split("|")]
            for line in text.splitlines() if line.startswith("| ")]


class Audit:
    def __init__(self, root: Path):
        self.root = root
        self.errors: list[str] = []
        self.blockers: list[str] = []
        self.checks = 0
        self.inputs: dict[str, str] = {}
        self.cache: dict[str, str] = {}

    def check(self, valid: bool, message: str) -> None:
        self.checks += 1
        if not valid:
            self.errors.append(message)

    def read(self, path: str) -> str:
        if path not in self.cache:
            resolved = (self.root / path).resolve()
            resolved.relative_to(self.root)
            self.inputs[path] = sha256(resolved)
            self.cache[path] = resolved.read_text(encoding="utf-8-sig")
        return self.cache[path]

    def path_exists(self, path: str) -> bool:
        try:
            resolved = (self.root / path).resolve()
            resolved.relative_to(self.root)
            return resolved.is_file()
        except (ValueError, TypeError):
            return False

    def check_source_ref(self, ref: dict, context: str) -> None:
        self.check(self.path_exists(ref.get("path", "")) and bool(ref.get("section")),
                   f"{context}: missing source path/section")

    def links(self) -> None:
        paths = [self.root / "README.md", self.root / "AGENTS.md", self.root / "agent.md",
                 self.root / "实施计划与验收基线.md"]
        paths += sorted((self.root / "docs").rglob("*.md"))
        paths += sorted((self.root / "动作或者图片描述").rglob("*.md"))
        for path in paths:
            relative = path.relative_to(self.root).as_posix()
            text = self.read(relative)
            fence = None
            for number, line in enumerate(text.splitlines(), 1):
                start = re.match(r"^\s*(`{3,}|~{3,})", line)
                if start:
                    marker = start[1][0]
                    if fence is None:
                        fence = marker
                    elif fence == marker:
                        fence = None
                    continue
                if fence:
                    continue
                # Inline file links; anchor destinations are not section-validated.
                for match in re.finditer(r"\[[^\]]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", line):
                    target = match[1].strip("<>")
                    if re.match(r"^[A-Za-z][A-Za-z\d+.-]*:", target) or target.startswith("#"):
                        continue
                    target = unquote(target.split("#", 1)[0])
                    resolved = (path.parent / target).resolve()
                    try:
                        resolved.relative_to(self.root)
                        valid = resolved.is_file()
                    except ValueError:
                        valid = False
                    self.check(valid, f"LINK {relative}:{number}: {target}")
        for name in REMOVED:
            self.check(not (self.root / "docs" / name).exists(), f"MERGE duplicate still exists: {name}")

    def sources(self, baseline: dict) -> None:
        entries = baseline["sources"]
        self.check(len(entries) == 4 and {x["id"] for x in entries} == set(SOURCES),
                   "SOURCE expected exactly four upstream sources")
        for entry in entries:
            expected = SOURCES.get(entry["id"])
            self.check(expected == (entry.get("path"), entry.get("version")),
                       f"SOURCE {entry['id']}: path/version mismatch")
            text = self.read(entry["path"])
            self.check(f"版本：{entry['version']}" in text, f"SOURCE {entry['id']}: version header")
            self.check(entry.get("adopted_sha256") == self.inputs[entry["path"]],
                       f"SOURCE {entry['id']}: adopted SHA-256 mismatch")
            self.check(entry.get("adopted_date") == baseline["confirmed_date"],
                       f"SOURCE {entry['id']}: adoption date mismatch")
            approved = entry.get("approved_sha256")
            self.check(approved is None or bool(re.fullmatch(r"[0-9a-f]{64}", approved)),
                       f"SOURCE {entry['id']}: malformed approval hash")

    def scope(self, baseline: dict) -> None:
        scope = baseline["scope"]
        self.check(scope["production_manifest_id"] == "campus_mvp" and
                   scope["scope_version"] == "campus_mvp.v1", "SCOPE manifest/version")
        enabled = scope["enabled_by_kind"]
        self.check(set(enabled) == set(EXPECTED_IDS), "SCOPE kind set")
        for kind, expected in EXPECTED_IDS.items():
            actual = enabled.get(kind, [])
            self.check(len(actual) == len(set(actual)) and set(actual) == set(expected),
                       f"SCOPE {kind}: exact ID set mismatch")
            for id_ in actual:
                if kind in {"status", "ruleset"}:
                    self.check(id_ in self.read(CONTENT), f"SCOPE {kind}/{id_}: no schema source")
                else:
                    self.check(bool(re.search(r"^\|\s*" + re.escape(id_) + r"(?:\s|\|)",
                                              self.read(DESIGN), re.M)),
                               f"SCOPE {kind}/{id_}: no upstream definition row")
        self.check(scope["formal_card_count"] == 24 and scope["special_card_ids"] == ["X01"],
                   "SCOPE formal/special count")
        self.check(scope["term_count"] == 1 and scope["difficulty_ids"] == ["normal"] and
                   set(scope["disabled_features"]) == {"career", "legacy", "graduation_choice"}
                   and scope["holdback"] == [], "SCOPE term/difficulty/features/holdback")
        self.check_source_ref(scope["source"], "SCOPE")
        overrides = scope["overrides"]
        self.check(len(overrides) == 2, "SCOPE exactly two overrides")
        for id_, kind, value, full, selector in [
            ("V03", "event", ["K14", "K05", "K60"], ["K14", "K24", "K34"],
             "options[option_id=consult].effects[op=gain_card].card_pool"),
            ("N04", "encounter", [1], [2, 3], "terms"),
        ]:
            matches = [x for x in overrides if x["id"] == id_ and x["kind"] == kind]
            self.check(len(matches) == 1, f"OVERRIDE {id_}: missing/duplicate")
            if matches:
                entry = matches[0]
                self.check(entry["value"] == value and entry["full_value"] == full and
                           entry["selector"] == selector and entry["scope_version"] == "campus_mvp.v1"
                           and entry["source"] == {"path": PLAN, "section": "§3.1"},
                           f"OVERRIDE {id_}: values/source/version")
        self.map(scope)

    def map(self, scope: dict) -> None:
        topology = scope["map_topology"]
        nodes = topology["nodes"]
        self.check((topology["term_count"], topology["layers"], topology["node_count"],
                    topology["route_length"]) == (1, 6, 8, 6), "MAP dimensions")
        self.check(len(nodes) == 8 and len({n["id"] for n in nodes}) == 8, "MAP unique nodes")
        layers = [[f"t1l{i}_{kind}" for kind in kinds]
                  for i, kinds in enumerate(LAYER_KINDS, 1)]
        index = {n["id"]: n for n in nodes}
        self.check(set(index) == {id_ for layer in layers for id_ in layer}, "MAP template node set")
        for i, layer in enumerate(layers, 1):
            for id_ in layer:
                if id_ not in index:
                    continue
                node = index[id_]
                expected_next = layers[i] if i < 6 else []
                self.check(node["layer"] == i and node["kind"] == id_.split("_", 1)[1] and
                           node["next_ids"] == expected_next,
                           f"MAP {id_}: kind/layer/adjacent-layer edges")
        expected_routes = {(layers[0][0], second, layers[2][0], fourth, layers[4][0], layers[5][0])
                           for second in layers[1] for fourth in layers[3]}
        routes = scope["representative_routes"]
        self.check(len(routes) == 4 and len({r["id"] for r in routes}) == 4 and
                   {tuple(r["node_ids"]) for r in routes} == expected_routes,
                   "MAP four representative routes")
        for route in routes:
            self.check(route["characters"] == ["P01", "P04"] and
                       route["seeds"] == ["42", "20261014"], f"MAP {route['id']}: characters/seeds")

    def trace(self, baseline: dict) -> None:
        plan = self.read("实施计划与验收基线.md")
        trace = self.read(baseline["traceability_document"])
        section = plan.split("## 3. 可验证需求", 1)[1].split("## 4.", 1)[0]
        ids = [r[0] for r in table_rows(section) if r[0] in REQUIREMENTS]
        self.check(len(ids) == 14 and set(ids) == REQUIREMENTS, "TRACE plan requirements")
        self.check(len(baseline["requirement_ids"]) == 14 and
                   set(baseline["requirement_ids"]) == REQUIREMENTS, "TRACE registered requirements")
        ids = [r[0] for r in table_rows(trace) if r[0] in REQUIREMENTS]
        self.check(len(ids) == 14 and set(ids) == REQUIREMENTS, "TRACE all requirements once")
        rows = [r for r in table_rows(trace) if re.fullmatch(r"G0-RULE-\d{3}", r[0])]
        self.check(len(rows) == 12 and {r[0] for r in rows} ==
                   {f"G0-RULE-{i:03}" for i in range(1, 13)} and
                   all(len(r) == 4 and all(r) for r in rows), "TRACE 12 frozen rule rows")
        expected = {}
        for path, pattern in [(DESIGN, r"T\d{2}"), (RULES, r"RB-\d{2}")]:
            for row in table_rows(self.read(path)):
                if len(row) == 3 and re.fullmatch(pattern, row[0]):
                    expected[row[0]] = (path, row[1], row[2])
        cases = baseline["scope"]["rule_cases"]
        expected_ids = {f"T{i:02}" for i in range(1, 21)} | {f"RB-{i:02}" for i in range(1, 15)}
        self.check(set(expected) == expected_ids and len(cases) == 34 and
                   {c["id"] for c in cases} == expected_ids, "TRACE T01-T20/RB-01-RB-14 coverage")
        for case in cases:
            self.check((case["source"]["path"], case["input"], case["expected"]) == expected.get(case["id"]),
                       f"TRACE {case['id']}: exact upstream input/expected")
            self.check_source_ref(case["source"], case["id"])
            full = case["id"] in FULL_CASES
            self.check(case["fixture_scope"] == ("test_full_" if full else "test_mvp_") and
                       case["execution_status"] == "not_run", f"TRACE {case['id']}: fixture/evidence status")
        ledger = self.read(baseline["ui_ledger"])
        expected_ui = {f"VIS-{i:03}" for i in range(1, 14)} | {f"ACT-{i:03}" for i in range(1, 4)}
        ui_rows = [r for r in table_rows(ledger) if r[0] in expected_ui]
        self.check(len(ui_rows) == 16 and {r[0] for r in ui_rows} == expected_ui and
                   all(len(r) == 5 and "界面层契约.md" in r[1] and all(r) for r in ui_rows),
                   "UI 16 ledger IDs with sources/triggers/status")

    def bindings(self, baseline: dict) -> None:
        bindings = baseline["scope"]["numeric_bindings"]
        self.check(len(bindings) == 57 and len({b["config_key"] for b in bindings}) == 57,
                   "BINDING numeric key coverage/uniqueness")
        content = self.read(CONTENT)
        rows = {r[0]: r[1] for r in table_rows(content) if len(r) >= 2}
        for binding in bindings:
            key, value = binding["config_key"], binding["expected"]
            self.check_source_ref(binding["upstream"], f"BINDING {key} upstream")
            self.check_source_ref(binding["contract"], f"BINDING {key} contract")
            self.check(binding["contract"]["path"] == CONTENT and
                       binding["execution_status"] == "not_run", f"BINDING {key} source/status")
            parts = key.split(".")
            if type(value) is int:
                if parts[0] == "statuses":
                    row = next((v for k, v in rows.items()
                                if (parts[1] in k.split("/", 1)[0].split(",") and "/player" in k)
                                or k == parts[1] + "/task"), "")
                    valid = re.search(r"(?<![A-Za-z0-9_])" + re.escape(parts[-1]) + "=" + str(value) + r"\b", row)
                else:
                    row = rows.get(parts[0], "")
                    valid = re.search(r"\b" + re.escape(parts[-1]) + ":int=" + str(value) + r"\b", row)
                self.check(bool(valid), f"BINDING {key}: value absent/different in content contract")
            elif key == "run.common_starter_cards":
                self.check(value == ["K01"] * 4 + ["K02"] * 4 + ["K03", "K04"],
                           "BINDING common starter cards: expected 4/4/1/1")
                for path in [CONTENT, RULES, DESIGN]:
                    self.check("K01×4、K02×4、K03×1、K04×1" in self.read(path),
                               f"BINDING starter source mismatch: {path}")
            elif parts[0] == "rewards" and "weights" in parts[1]:
                weights = {"normal": [60, 30, 9, 1], "elite": [20, 45, 30, 5],
                           "term": [50, 50, 0, 0], "general": [50, 35, 13, 2]}
                target = ([0, 30, 50, 20] if parts[1] == "card_rarity_weights" else [20, 40, 35, 5]) if parts[2] == "boss" else weights[parts[2]]
                self.check(value == dict(zip(["white", "blue", "purple", "gold"], target)),
                           f"BINDING {key}: weights")
            else:
                token = {"battle.cooperation_exam_relax": "cooperation_exam_relax:int数组=[5,7]",
                         "battle.scene_exam_relax": "scene_exam_relax:int数组=[2,4]",
                         "rewards.normal_money_by_term": "normal_money_by_term:int数组（15,15,20,20,25,25,30,30的前term_count项）",
                         "difficulty_overrides.normal": "normal=72/0/100"}.get(key)
                if token:
                    expected = {"battle.cooperation_exam_relax": [5, 7], "battle.scene_exam_relax": [2, 4],
                                "rewards.normal_money_by_term": [15],
                                "difficulty_overrides.normal": {"starting_vitality": 72, "ddl_offset": 0, "pressure_percent": 100}}[key]
                    self.check(token in content and value == expected, f"BINDING {key}: array/object")
                elif parts[0] == "shop" and isinstance(value, dict):
                    token = parts[1] + ":{" + ",".join(f"{k}:{'int=' if 'stock' in key else ''}{v}" for k, v in value.items()) + "}"
                    self.check(token in rows.get("shop", ""), f"BINDING {key}: shop object")
                else:
                    self.check(False, f"BINDING {key}: unhandled shape")
        expected_encounters = {
            "N01": ([24], 8, ["pressure5", "pressure7"], []),
            "N02": ([28], 8, ["shield5", "pressure8"], []),
            "N03": ([30], 8, ["pressure6", "X01→discard+pressure4"], []),
            "N04": ([32], 8, ["anxiety1", "pressure9"], []),
            "Q01": ([38], 6, ["pressure7", "shield6", "pressure10"], ["independent_answer"]),
            "B01": ([20, 25, 25], 10, ["pressure7", "shield5", "pressure9"], ["independent_answer", "fixed_exam_room"]),
        }
        encounters = baseline["scope"]["encounter_bindings"]
        self.check(len(encounters) == 6 and {e["id"] for e in encounters} == set(expected_encounters),
                   "BINDING encounter coverage")
        for entry in encounters:
            actual = (entry["work_max_by_phase"], entry["base_ddl"], entry["intent_cycle_each_phase"], entry["exam_flags"])
            self.check(actual == expected_encounters.get(entry["id"]), f"BINDING encounter {entry['id']}")
            self.check_source_ref(entry["source"], entry["id"])
        apis = baseline["scope"]["public_api_baseline"]
        self.check(set(apis) == {"session", "battle", "run", "storage", "content_and_random", "json_schema"},
                   "API module coverage")
        for path in apis.values():
            self.check(self.path_exists(path), f"API missing contract: {path}")
        for method in ["start_run", "continue_run", "get_view", "preview_action", "submit",
                       "save_current", "save_and_exit", "get_profile", "update_settings",
                       "inspect_saves", "get_setup_options", "restore_backup"]:
            self.check(bool(re.search(r"^\| " + method + r"\(", self.read(apis["session"]), re.M)),
                       f"API GameSession.{method}: missing signature row")

    def readiness(self, baseline: dict) -> None:
        self.check(baseline["schema_version"] == 2 and baseline["stage"] == "G0", "BASELINE schema/stage")
        self.check(baseline["status"] == "frozen_document_baseline", "BASELINE document status")
        self.check(baseline["confirmed_date"] == "2026-10-14", "BASELINE confirmation date")
        decisions = baseline["decisions"]
        self.check(len(decisions) == 11 and {d["id"] for d in decisions} ==
                   {f"DEC-{i:03}" for i in range(1, 12)}, "DECISION coverage")
        for entry in decisions + baseline["rule_decisions"]:
            self.check("owner" not in entry, f"DATE {entry['id']}: owner field is not required/managed")
            closed = entry.get("document_status", entry.get("status")) == "closed"
            self.check(not closed or bool(entry.get("confirmed_date")) and bool(entry.get("resolution")),
                       f"DECISION {entry['id']}: closed decision missing confirmation/resolution")
            for field in ["confirmed_date", "recorded_date", "target_date"]:
                value = entry.get(field)
                if value is not None:
                    try:
                        valid = date.fromisoformat(value).isoformat() == value
                    except (ValueError, TypeError):
                        valid = False
                    self.check(valid, f"DATE {entry['id']}: invalid {field}")
            if entry.get("document_status") != "closed" and entry.get("blocking_stage") == "G0":
                self.blockers.append(f"{entry['id']}: G0 document decision open")
        rule_decisions = baseline["rule_decisions"]
        self.check(len(rule_decisions) == 3 and {d["id"] for d in rule_decisions} ==
                   {"Q-005", "Q-006", "Q-007"}, "DECISION rule IDs")
        for entry in rule_decisions:
            if entry["status"] != "closed" and entry.get("blocking_scope") != "full":
                self.blockers.append(f"{entry['id']}: MVP rule decision open")
        review = baseline["semantic_review"]
        self.check(self.path_exists(review["record"]) and bool(review["date"]), "REVIEW record/date")
        if review["status"] != "completed" or review["open_mvp_findings"]:
            self.blockers.append("Semantic review is incomplete or has open MVP findings")
        # Later implementation and full-only Q-007 are deliberately not G0 blockers.

    def run(self) -> None:
        try:
            baseline = json.loads(self.read("docs/baselines/g0.json"))
            self.links()
            self.sources(baseline)
            self.scope(baseline)
            self.trace(baseline)
            self.bindings(baseline)
            self.readiness(baseline)
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            self.errors.append(f"BASELINE_STRUCTURE {type(error).__name__}: {error}")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--documents-only", action="store_true")
    parser.add_argument("--run-id", help="New evidence directory name; existing runs are never overwritten")
    args = parser.parse_args()
    root = args.root.resolve()
    started = datetime.now().astimezone()
    run_id = args.run_id or "g0-" + started.strftime("%Y%m%d-%H%M%S-%f")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
        parser.error("run-id must contain only ASCII letters, digits, hyphens and underscores")
    output = root / "artifacts" / "verification" / run_id
    output.mkdir(parents=True, exist_ok=False)
    environment = {"python": sys.version, "executable": sys.executable, "os": platform.platform(),
                   "cwd": str(Path.cwd()), "root": str(root), "started": started.isoformat(),
                   "godot": "not invoked; document audit only"}
    command = {"argv": [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
               "cwd": str(Path.cwd()), "mode": "documents_only" if args.documents_only else "g0_readiness"}
    audit = Audit(root)
    audit.inputs["tools/verify_g0.py"] = sha256(Path(__file__).resolve())
    audit.run()
    code = 1 if audit.errors else (2 if audit.blockers and not args.documents_only else 0)
    report = {"run_id": run_id, "mode": command["mode"], "checks": audit.checks,
              "errors": audit.errors, "g0_blockers": audit.blockers, "exit_code": code,
              "documents_passed": not audit.errors,
              "g0_ready": None if args.documents_only else not audit.errors and not audit.blockers,
              "limits": "Document assertions and registered semantic review only; no Godot, game JSON or UI tests."}
    lines = [f"Mode: {command['mode']}", f"Checks: {audit.checks}",
             f"Document errors: {len(audit.errors)}", f"G0 blockers: {len(audit.blockers)}"]
    lines += ["ERROR " + message for message in audit.errors]
    lines += ["BLOCKER " + message for message in audit.blockers]
    lines += [f"Exit code: {code}", f"Evidence: {output}", report["limits"]]
    stdout = "\n".join(lines) + "\n"
    for name, value in [("command.json", command), ("environment.json", environment),
                        ("inputs.json", audit.inputs), ("report.json", report)]:
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "stdout.txt").write_text(stdout, encoding="utf-8")
    (output / "exit_code.txt").write_text(str(code) + "\n", encoding="utf-8")
    (output / "report.md").write_text(
        "# G0文档核查报告\n\n日期：" + started.isoformat() + "\n\n```text\n" + stdout + "```\n\n"
        "输入字节hash见[inputs.json](inputs.json)，命令和环境见[command.json](command.json)、"
        "[environment.json](environment.json)；原始输出见[stdout.txt](stdout.txt)，"
        "[结构化结果](report.json)与[退出码](exit_code.txt)一并保留。\n", encoding="utf-8")
    print(stdout, end="")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
