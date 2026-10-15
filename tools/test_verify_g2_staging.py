"""Focused tests for the read-only G2 staging acceptance audit."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_g2_staging as verifier


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class G2StagingVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        source = self.root / "docs/source.md"
        source.parent.mkdir(parents=True)
        source.write_text(
            "## 5.1 cards\n| C01 | card source |\n"
            "## 4 characters\n| E01 | entity source |\n"
            "## 9.1 tasks\n| T01 | task source |\n",
            encoding="utf-8",
        )
        definitions = {
            "card": [("C01", 2)],
            "character": [("E01", 4)],
            "task": [("T01", 6)],
        }
        deferred = {"definitions": {}, "manifest_holdback": {}}
        enabled = {}
        for kind, entries in definitions.items():
            enabled[kind] = [id_ for id_, _ in entries]
            deferred["manifest_holdback"][kind] = [id_ for id_, _ in entries]
            deferred["definitions"][kind] = [
                {"id": id_, "source": {"path": "docs/source.md", "section": f"{kind} ID {id_}"}, "blocking": ["G2"]}
                for id_, _ in entries
            ]
        write_json(self.root / "docs/baselines/g0.json", {"scope": {"enabled_by_kind": enabled}})
        write_json(self.root / "data/manifests/content_deferred.json", deferred)

        cards_dir = self.root / "artifacts/g2-build/staging/cards"
        write_json(cards_dir / "cards.json", [{"id": "C01"}])
        write_json(cards_dir / "batch.json", {
            "source_section": "统一设计文档 §5.1 卡牌行",
            "input_sha256": {"docs/source.md": digest(source)},
            "cards": [{"id": "C01", "source_line": 2}],
            "schema_and_behavior_mapping": {
                "runtime_mapping": "src/battle/card_handler.gd::play",
                "relevant_existing_tests": ["tests/test_card.gd"],
                "test_status": "not run",
            },
        })

        entities_dir = self.root / "artifacts/g2-build/staging/entities"
        entity = {
            "kind": "character", "id": "E01",
            "source": {"path": "docs/source.md", "section": "character ID E01", "line": 4, "row": "| E01 | entity source |"},
            "behavior_refs": ["src/battle/character.gd::apply"],
            "definition": {"id": "E01"}, "status": "staged_pending",
        }
        write_json(entities_dir / "definitions/character_E01.json", entity)
        (entities_dir / "batch_report.md").parent.mkdir(parents=True, exist_ok=True)
        (entities_dir / "batch_report.md").write_text(
            "- `docs/source.md`: `" + digest(source) + "`\n"
            "| character | E01 | approved | source row | pending |\n",
            encoding="utf-8",
        )
        (entities_dir / "exit_code.txt").write_text("0\n", encoding="utf-8")
        (entities_dir / "stdout.txt").write_text("SCHEMA_OK character/E01\n", encoding="utf-8")
        (entities_dir / "runtime_probe/evidence").mkdir(parents=True, exist_ok=True)
        (entities_dir / "runtime_probe/evidence/exit_code.txt").write_text("0\n", encoding="utf-8")

        flow_dir = self.root / "artifacts/g2-build/staging/flow"
        flow_record = {
            "kind": "task", "id": "T01",
            "source": {
                "path": "docs/source.md", "section": "task ID T01",
                "source_lines": [6], "source_row": "| T01 | task source |",
            },
            "behavior_refs": ["src/battle/task.gd::tick"],
            "definition": {"id": "T01"}, "status": "schema only",
        }
        record_path = flow_dir / "definitions/task_T01.json"
        write_json(record_path, flow_record)
        write_json(flow_dir / "batch.json", {
            "ids": {"task": ["T01"], "encounter": [], "event": []},
            "counts": {"task": 1, "encounter": 0, "event": 0},
            "input_sha256": {"docs/source.md": digest(source)},
            "staged_record_sha256": {"artifacts/g2-build/staging/flow/definitions/task_T01.json": digest(record_path)},
        })
        (flow_dir / "schema_probe.exit_code.txt").write_text("0\n", encoding="utf-8")
        (flow_dir / "schema_probe.stdout.txt").write_text("SCHEMA_OK task/T01\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_exact_frozen_ids_and_source_rows_are_checked(self) -> None:
        report = verifier.verify(self.root)
        self.assertEqual(report["frozen_count"], 3)
        self.assertEqual(report["registry_issues"], [])
        by_name = {batch["batch"]: batch for batch in report["batches"]}
        self.assertEqual(by_name["flow"]["observed_count"], 1)
        self.assertFalse(by_name["flow"]["accepted"])
        self.assertFalse(any(issue["code"] == "source_row_mismatch" for issue in by_name["flow"]["issues"]))
        self.assertTrue(any(issue["code"] == "schema_probe_coverage_mismatch" for issue in by_name["cards"]["issues"]))

    def test_pending_closure_and_handler_prevent_batch_acceptance(self) -> None:
        report = verifier.verify(self.root, "flow")
        flow = report["batches"][0]
        codes = {issue["code"] for issue in flow["issues"]}
        self.assertFalse(report["accepted"])
        self.assertIn("reference_closure_unverified", codes)
        self.assertIn("handler_unverified", codes)
        self.assertIn("behavior_tests_unverified", codes)
        self.assertNotIn("schema_probe_coverage_mismatch", codes)

    def test_hash_drift_and_unregistered_definition_are_reported(self) -> None:
        source = self.root / "docs/source.md"
        (self.root / "artifacts/g2-build/staging/flow/definitions/task_T01.json").write_text(
            (self.root / "artifacts/g2-build/staging/flow/definitions/task_T01.json").read_text(encoding="utf-8").replace("task source", "changed source"),
            encoding="utf-8",
        )
        record_path = self.root / "artifacts/g2-build/staging/flow/definitions/task_T01.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["id"] = "EXTRA"
        record["definition"]["id"] = "EXTRA"
        write_json(record_path, record)
        report = verifier.verify(self.root, "flow")
        codes = {issue["code"] for issue in report["batches"][0]["issues"]}
        self.assertIn("artifact_hash_mismatch", codes)
        self.assertIn("unregistered_id", codes)
        self.assertIn("missing_id", codes)

    def test_cards_without_per_record_source_row_cannot_pass(self) -> None:
        batch_path = self.root / "artifacts/g2-build/staging/cards/batch.json"
        batch = json.loads(batch_path.read_text(encoding="utf-8"))
        batch["cards"][0]["source_line"] = 4
        write_json(batch_path, batch)
        report = verifier.verify(self.root, "cards")
        codes = {issue["code"] for issue in report["batches"][0]["issues"]}
        self.assertIn("source_row_mismatch", codes)
        self.assertIn("artifact_hashes_missing", codes)
        self.assertIn("schema_probe_missing", codes)

    def test_source_line_must_be_inside_the_expected_g0_section(self) -> None:
        source = self.root / "docs/source.md"
        source.write_text(
            "## 5.1 cards\n| C01 | card source |\n"
            "## 5.1 wrong section\n| E01 | entity source |\n"
            "## 9.1 tasks\n| T01 | task source |\n",
            encoding="utf-8",
        )
        report = verifier.verify(self.root, "entities")
        codes = {issue["code"] for issue in report["batches"][0]["issues"]}
        self.assertIn("source_section_unverified", codes)

    def test_empty_behavior_refs_are_rejected(self) -> None:
        record_path = self.root / "artifacts/g2-build/staging/flow/definitions/task_T01.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["behavior_refs"] = ["", "  "]
        write_json(record_path, record)
        batch_path = self.root / "artifacts/g2-build/staging/flow/batch.json"
        batch = json.loads(batch_path.read_text(encoding="utf-8"))
        batch["staged_record_sha256"]["artifacts/g2-build/staging/flow/definitions/task_T01.json"] = digest(record_path)
        write_json(batch_path, batch)
        report = verifier.verify(self.root, "flow")
        item = report["batches"][0]["items"][0]
        self.assertIn("behavior_refs_missing", {issue["code"] for issue in item["issues"]})

    def test_per_id_attestation_keeps_verified_items_independent(self) -> None:
        source_path = self.root / "docs/source2.md"
        source_path.write_text("## 9.1 tasks\n| T02 | second task source |\n", encoding="utf-8")
        baseline_path = self.root / "docs/baselines/g0.json"
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        baseline["scope"]["enabled_by_kind"]["task"].append("T02")
        write_json(baseline_path, baseline)
        deferred_path = self.root / "data/manifests/content_deferred.json"
        deferred = json.loads(deferred_path.read_text(encoding="utf-8"))
        deferred["definitions"]["task"].append({
            "id": "T02", "source": {"path": "docs/source2.md", "section": "task ID T02"}, "blocking": ["G2"]
        })
        deferred["manifest_holdback"]["task"].append("T02")
        write_json(deferred_path, deferred)

        batch_path = self.root / "artifacts/g2-build/staging/flow/batch.json"
        record_path = self.root / "artifacts/g2-build/staging/flow/definitions/task_T02.json"
        record = json.loads((self.root / "artifacts/g2-build/staging/flow/definitions/task_T01.json").read_text(encoding="utf-8"))
        record["id"] = "T02"
        record["source"]["path"] = "docs/source2.md"
        record["source"]["section"] = "task ID T02"
        record["source"]["source_lines"] = [7]
        record["source"]["source_row"] = "| T02 | second task source |"
        record["definition"]["id"] = "T02"
        write_json(record_path, record)
        batch = json.loads(batch_path.read_text(encoding="utf-8"))
        batch["ids"]["task"].append("T02")
        batch["counts"]["task"] = 2
        batch["staged_record_sha256"]["artifacts/g2-build/staging/flow/definitions/task_T02.json"] = digest(record_path)
        batch["schema_probe"] = {"status": "passed", "ids": ["task/T01", "task/T02"]}
        batch["reference_closure"] = {
            "items": {"task/T01": {"status": "passed"}}
        }
        batch["handler_verification"] = {
            "items": {"task/T01": {"status": "passed"}}
        }
        batch["behavior_tests"] = {
            "items": {"task/T01": {"status": "passed"}}
        }
        batch["input_sha256"].update({
            "docs/baselines/g0.json": digest(self.root / "docs/baselines/g0.json"),
            "data/manifests/content_deferred.json": digest(self.root / "data/manifests/content_deferred.json"),
            "docs/source2.md": digest(self.root / "docs/source2.md"),
        })
        write_json(batch_path, batch)
        report = verifier.verify(self.root, "flow")
        items = {f"{item['kind']}/{item['id']}": item for item in report["batches"][0]["items"]}
        self.assertTrue(items["task/T01"]["accepted"])
        self.assertFalse(items["task/T02"]["accepted"])
        self.assertFalse(report["accepted"])

    def test_legacy_batch_attestation_remains_supported(self) -> None:
        batch_path = self.root / "artifacts/g2-build/staging/flow/batch.json"
        batch = json.loads(batch_path.read_text(encoding="utf-8"))
        for field in ("reference_closure", "handler_verification", "behavior_tests"):
            batch[field] = {"status": "passed", "ids": ["task/T01"]}
        batch["input_sha256"].update({
            "docs/baselines/g0.json": digest(self.root / "docs/baselines/g0.json"),
            "data/manifests/content_deferred.json": digest(self.root / "data/manifests/content_deferred.json"),
        })
        write_json(batch_path, batch)
        report = verifier.verify(self.root, "flow")
        item = report["batches"][0]["items"][0]
        self.assertTrue(item["accepted"])
        codes = {issue["code"] for issue in report["batches"][0]["issues"]}
        self.assertNotIn("reference_closure_unverified", codes)
        self.assertNotIn("handler_unverified", codes)
        self.assertNotIn("behavior_tests_unverified", codes)

    def test_input_hash_drift_marks_item_blocker(self) -> None:
        source = self.root / "docs/source.md"
        source.write_text(source.read_text(encoding="utf-8") + "\nchanged\n", encoding="utf-8")
        report = verifier.verify(self.root, "flow")
        item = report["batches"][0]["items"][0]
        self.assertFalse(item["accepted"])
        self.assertIn("input_hash_drift", {issue["code"] for issue in item["issues"]})


if __name__ == "__main__":
    unittest.main(verbosity=2)
