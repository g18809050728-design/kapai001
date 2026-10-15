"""Read-only acceptance audit for the isolated G2 staging batches."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
STAGING = Path("artifacts/g2-build/staging")
BATCH_KINDS = {
    "cards": {"card"},
    "entities": {"character", "relic", "unit", "scene"},
    "flow": {"task", "encounter", "event"},
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16").strip("\ufeff")
    return raw.decode("utf-8-sig")


def read_json(path: Path) -> Any:
    return json.loads(read_text(path))


def repo_path(root: Path, value: str) -> Path | None:
    candidate = Path(value)
    if candidate.is_absolute():
        return None
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def frozen_registry(root: Path) -> tuple[dict[tuple[str, str], dict[str, Any]], list[dict[str, str]]]:
    errors: list[dict[str, str]] = []
    try:
        deferred = read_json(root / "data/manifests/content_deferred.json")
        baseline = read_json(root / "docs/baselines/g0.json")
    except (OSError, json.JSONDecodeError, UnicodeError) as exc:
        return {}, [{"code": "frozen_registry_unreadable", "message": str(exc)}]

    definitions = deferred.get("definitions")
    if not isinstance(definitions, dict):
        return {}, [{"code": "frozen_registry_invalid", "message": "definitions must be an object"}]

    enabled = baseline.get("scope", {}).get("enabled_by_kind", {})
    held = deferred.get("manifest_holdback", {})
    frozen: dict[tuple[str, str], dict[str, Any]] = {}
    for kind, entries in definitions.items():
        if not isinstance(entries, list):
            errors.append({"code": "frozen_registry_invalid", "message": f"{kind}: entries must be an array"})
            continue
        seen: set[str] = set()
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
                errors.append({"code": "frozen_registry_invalid", "message": f"{kind}: invalid definition entry"})
                continue
            id_ = entry["id"]
            key = (kind, id_)
            source = entry.get("source")
            if key in frozen:
                errors.append({"code": "frozen_duplicate_id", "message": f"duplicate frozen ID {kind}/{id_}"})
            if not isinstance(source, dict) or not source.get("path") or not source.get("section"):
                errors.append({"code": "frozen_source_missing", "message": f"{kind}/{id_}: source path/section missing"})
            if "G2" not in entry.get("blocking", []):
                errors.append({"code": "frozen_blocker_missing", "message": f"{kind}/{id_}: G2 holdback is not registered"})
            kind_scope = enabled.get(kind, []) if isinstance(enabled, dict) else []
            if id_ not in kind_scope:
                errors.append({"code": "outside_g0_scope", "message": f"{kind}/{id_}: absent from G0 enabled_by_kind"})
            seen.add(id_)
            frozen[key] = entry
        declared_holdback = held.get(kind, []) if isinstance(held, dict) else []
        if set(declared_holdback) != seen:
            errors.append({"code": "holdback_id_set_mismatch", "message": f"{kind}: deferred IDs differ from manifest_holdback"})

    return frozen, errors


def source_row_matches(root: Path, item: dict[str, Any], source: dict[str, Any]) -> tuple[bool, str]:
    path_value = item.get("source_path")
    path_value = path_value or source.get("path")
    path = repo_path(root, path_value) if isinstance(path_value, str) else None
    if path is None:
        return False, "source path is missing, absolute, or outside repository"
    try:
        lines = read_text(path).splitlines()
    except (OSError, UnicodeError) as exc:
        return False, f"source file cannot be read: {exc}"

    id_ = item["id"]
    candidates = item.get("source_lines")
    if candidates is None and item.get("source_line") is not None:
        candidates = [item["source_line"]]
    if candidates is None and source.get("source_lines") is not None:
        candidates = source.get("source_lines")
    if candidates is None and source.get("line") is not None:
        candidates = [source.get("line")]
    if not isinstance(candidates, list) or not candidates:
        return False, "source line number is missing"
    source_row = item.get("source_row")
    if not isinstance(source_row, str) and isinstance(source.get("row"), str):
        source_row = source["row"]
    if not isinstance(source_row, str) and isinstance(source.get("source_row"), str):
        source_row = source["source_row"]

    for number in candidates:
        if type(number) is not int or number < 1 or number > len(lines):
            continue
        actual = lines[number - 1].strip()
        if not re.match(rf"^\|\s*{re.escape(id_)}(?:\s|\|)", actual):
            continue
        if source_row is None or actual == source_row.strip():
            return True, ""
    return False, f"no exact source table row for {id_} at recorded lines {candidates}"


def source_heading_matches(path: Path, kind: str, id_: str, line_number: int) -> tuple[bool, str]:
    lines = read_text(path).splitlines()
    headings = [(index, line.strip()) for index, line in enumerate(lines[:line_number], 1) if line.lstrip().startswith("#")]
    if not headings:
        return False, "source row has no enclosing Markdown heading"
    heading = headings[-1][1]
    match = re.match(r"#+\s*(\d+)(?:\.(\d+))?\b", heading)
    if not match:
        return False, f"source row is under an unnumbered heading: {heading}"
    section = match.group(1)
    subsection = match.group(2)
    if kind == "card":
        valid = section == "5" and subsection is not None
        if id_ == "X01":
            valid = valid and subsection == "8"
        else:
            valid = valid and subsection in {"1", "2", "3", "4", "5", "6", "7"}
    else:
        allowed = {
            "character": {"4"}, "unit": {"6"}, "scene": {"7"}, "relic": {"8"},
            "task": {"9"}, "encounter": {"9"}, "event": {"10"},
        }
        valid = section in allowed.get(kind, set())
        if kind == "task":
            valid = valid and subsection in {"1", "2", "3"}
        elif kind == "encounter":
            valid = valid and subsection in {"1", "2", "3"}
        elif kind == "event":
            valid = valid and subsection == "2"
    return (True, "") if valid else (False, f"{kind}/{id_} source row is under unexpected G0 section: {heading}")


class BatchAudit:
    def __init__(self, root: Path, name: str, frozen: dict[tuple[str, str], dict[str, Any]]) -> None:
        self.root = root
        self.name = name
        self.frozen = frozen
        self.expected = {
            key: entry for key, entry in frozen.items() if key[0] in BATCH_KINDS[name]
        }
        self.items: dict[tuple[str, str], dict[str, Any]] = {
            key: {"kind": key[0], "id": key[1], "accepted": False, "issues": []}
            for key in self.expected
        }
        self.issues: list[dict[str, str]] = []
        self.batch_dir = root / STAGING / name
        self.batch: dict[str, Any] = {}
        self.artifact_paths: dict[tuple[str, str], str] = {}

    def issue(self, code: str, message: str, key: tuple[str, str] | None = None) -> None:
        value = {"code": code, "message": message}
        self.issues.append(value)
        if key in self.items:
            self.items[key]["issues"].append(value)

    def load_batch(self) -> None:
        path = self.batch_dir / "batch.json"
        if path.exists():
            try:
                self.batch = read_json(path)
                if not isinstance(self.batch, dict):
                    self.issue("batch_metadata_invalid", "batch.json must contain an object")
                    self.batch = {}
            except (OSError, json.JSONDecodeError, UnicodeError) as exc:
                self.issue("batch_metadata_invalid", f"batch.json cannot be read: {exc}")
                self.batch = {}
        elif self.name == "entities":
            self.batch = self.entity_metadata()
        else:
            self.issue("batch_metadata_missing", "batch.json is required")

    def entity_metadata(self) -> dict[str, Any]:
        report_path = self.batch_dir / "batch_report.md"
        try:
            report = read_text(report_path)
        except (OSError, UnicodeError) as exc:
            self.issue("batch_report_missing", f"entities batch report cannot be read: {exc}")
            report = ""
        hashes = {
            path: value.lower()
            for path, value in re.findall(r"- `([^`]+)`: `([0-9a-fA-F]{64})`", report)
        }
        return {"input_sha256": hashes, "_entity_report": report}

    def load_items(self) -> list[dict[str, Any]]:
        if self.name == "cards":
            return self.load_cards()
        return self.load_envelopes()

    def load_cards(self) -> list[dict[str, Any]]:
        catalog_path = self.batch_dir / "cards.json"
        try:
            catalog = read_json(catalog_path)
        except (OSError, json.JSONDecodeError, UnicodeError) as exc:
            self.issue("artifact_unreadable", f"cards.json cannot be read: {exc}")
            return []
        if not isinstance(catalog, list):
            self.issue("artifact_invalid", "cards.json must contain an array")
            return []
        metadata = self.batch.get("cards")
        if not isinstance(metadata, list):
            self.issue("batch_ids_missing", "cards batch metadata must list every assigned ID")
            metadata = []
        by_id: dict[str, dict[str, Any]] = {}
        for entry in metadata:
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
                self.issue("batch_ids_invalid", "cards batch contains an invalid ID entry")
                continue
            id_ = entry["id"]
            key = ("card", id_)
            if id_ in by_id:
                self.issue("duplicate_id", f"duplicate card/{id_} in batch metadata", key)
            by_id[id_] = entry
        rows: list[dict[str, Any]] = []
        seen: set[str] = set()
        for definition in catalog:
            if not isinstance(definition, dict) or not isinstance(definition.get("id"), str):
                self.issue("artifact_record_invalid", "cards.json contains a record without string id")
                continue
            id_ = definition["id"]
            key = ("card", id_)
            if id_ in seen:
                self.issue("duplicate_id", f"duplicate card/{id_} in cards.json", key)
            seen.add(id_)
            metadata_entry = by_id.get(id_, {})
            rows.append({
                "kind": "card", "id": id_, "definition": definition,
                "source": {"path": self.expected.get(key, {}).get("source", {}).get("path"),
                           "section": self.expected.get(key, {}).get("source", {}).get("section")},
                "source_line": metadata_entry.get("source_line"),
                "source_path": self.expected.get(key, {}).get("source", {}).get("path"),
                "source_row": metadata_entry.get("source_row"),
                "behavior_refs": [],
                "status": self.batch.get("schema_and_behavior_mapping", {}).get("test_status", ""),
                "_catalog_path": "artifacts/g2-build/staging/cards/cards.json",
            })
            self.artifact_paths[key] = "artifacts/g2-build/staging/cards/cards.json"
            if id_ not in by_id:
                self.issue("batch_id_missing", f"card/{id_} has no source_line entry in batch.json", key)
        if set(by_id) != seen:
            for id_ in sorted(set(by_id) - seen):
                self.issue("artifact_id_missing", f"card/{id_} is listed in batch.json but absent from cards.json", ("card", id_))
        return rows

    def load_envelopes(self) -> list[dict[str, Any]]:
        definitions_dir = self.batch_dir / "definitions"
        if not definitions_dir.is_dir():
            self.issue("definitions_missing", "definitions directory is missing")
            return []
        rows: list[dict[str, Any]] = []
        for path in sorted(definitions_dir.glob("*.json")):
            try:
                record = read_json(path)
            except (OSError, json.JSONDecodeError, UnicodeError) as exc:
                self.issue("artifact_unreadable", f"{path.name} cannot be read: {exc}")
                continue
            if not isinstance(record, dict):
                self.issue("artifact_record_invalid", f"{path.name} must contain an object")
                continue
            kind, id_ = record.get("kind"), record.get("id")
            if not isinstance(kind, str) or not isinstance(id_, str):
                self.issue("artifact_record_invalid", f"{path.name} is missing string kind/id")
                continue
            key = (kind, id_)
            self.artifact_paths[key] = path.relative_to(self.root).as_posix()
            rows.append(record)
        return rows

    def check_ids(self, rows: list[dict[str, Any]]) -> None:
        observed: set[tuple[str, str]] = set()
        duplicates: set[tuple[str, str]] = set()
        for row in rows:
            key = (row.get("kind"), row.get("id"))
            if key not in self.expected:
                self.issue("unregistered_id", f"{key[0]}/{key[1]} is not assigned to the {self.name} staging batch", key)
                continue
            if key in observed:
                duplicates.add(key)
            observed.add(key)
        for key in sorted(duplicates):
            self.issue("duplicate_id", f"duplicate {key[0]}/{key[1]} in staged definition files", key)
        for key in sorted(set(self.expected) - observed):
            self.issue("missing_id", f"frozen ID {key[0]}/{key[1]} is missing from {self.name} batch", key)

        if self.name == "flow":
            declared = self.batch.get("ids")
            if not isinstance(declared, dict):
                self.issue("batch_ids_missing", "flow batch.json has no per-kind ids object")
            else:
                for kind in BATCH_KINDS[self.name]:
                    expected_ids = {id_ for item_kind, id_ in self.expected if item_kind == kind}
                    values = declared.get(kind)
                    if not isinstance(values, list) or set(values) != expected_ids:
                        self.issue("batch_id_set_mismatch", f"flow batch.json {kind} IDs do not match frozen assignment")
                        declared_ids = set(values) if isinstance(values, list) else set()
                        for id_ in sorted(expected_ids - declared_ids):
                            self.issue("batch_id_set_mismatch", f"{kind}/{id_} is absent from flow batch IDs", (kind, id_))
            counts = self.batch.get("counts")
            if not isinstance(counts, dict) or any(
                counts.get(kind) != sum(1 for item_kind, _ in self.expected if item_kind == kind)
                for kind in BATCH_KINDS[self.name]
            ):
                self.issue("batch_count_mismatch", "flow batch counts do not match frozen assignment")

        if self.name == "entities":
            report = self.batch.get("_entity_report", "")
            for kind, id_ in sorted(self.expected):
                pattern = rf"\|\s*{re.escape(kind)}\s*\|\s*{re.escape(id_)}\s*\|"
                if not re.search(pattern, report, flags=re.IGNORECASE):
                    self.issue("batch_report_id_missing", f"entities batch report does not list {kind}/{id_}", (kind, id_))

    def check_sources_and_refs(self, rows: list[dict[str, Any]]) -> None:
        for row in rows:
            kind, id_ = row.get("kind"), row.get("id")
            key = (kind, id_)
            expected = self.expected.get(key)
            if expected is None:
                continue
            source = row.get("source")
            frozen_source = expected.get("source", {})
            if not isinstance(source, dict):
                self.issue("source_metadata_missing", f"{kind}/{id_} has no source object", key)
                continue
            if source.get("path") != frozen_source.get("path"):
                self.issue("source_path_mismatch", f"{kind}/{id_} source path differs from frozen registry", key)
            if source.get("section") != frozen_source.get("section"):
                self.issue("source_section_mismatch", f"{kind}/{id_} source section differs from frozen registry", key)
            if row.get("definition", {}).get("id") != id_:
                self.issue("definition_id_mismatch", f"{kind}/{id_} definition.id does not match envelope", key)
            if self.name == "cards":
                section = self.batch.get("source_section")
                if not isinstance(section, str) or "§5." not in section:
                    self.issue("source_section_missing", f"card/{id_} batch source section does not identify the card source section", key)
            source_record = dict(source)
            matches, reason = source_row_matches(self.root, row, source_record)
            if not matches:
                self.issue("source_row_mismatch", f"{kind}/{id_}: {reason}", key)
            line_number = row.get("source_line")
            if line_number is None and isinstance(source.get("line"), int):
                line_number = source["line"]
            if line_number is None and isinstance(source.get("source_lines"), list) and source["source_lines"]:
                line_number = source["source_lines"][0]
            if line_number is None and isinstance(row.get("source_lines"), list) and row["source_lines"]:
                line_number = row["source_lines"][0]
            source_path = repo_path(self.root, source.get("path", ""))
            if source_path is None or type(line_number) is not int:
                self.issue("source_section_unverified", f"{kind}/{id_} lacks an exact source path/line for section verification", key)
            else:
                try:
                    section_matches, section_reason = source_heading_matches(source_path, kind, id_, line_number)
                except (OSError, UnicodeError) as exc:
                    section_matches, section_reason = False, f"source heading cannot be read: {exc}"
                if not section_matches:
                    self.issue("source_section_unverified", f"{kind}/{id_}: {section_reason}", key)
            refs = row.get("behavior_refs")
            if self.name == "cards":
                mapping = self.batch.get("schema_and_behavior_mapping", {})
                refs = [mapping.get("runtime_mapping"), *mapping.get("relevant_existing_tests", [])] if isinstance(mapping, dict) else []
            if not isinstance(refs, list) or not any(isinstance(ref, str) and ref.strip() for ref in refs):
                self.issue("behavior_refs_missing", f"{kind}/{id_} has no non-empty behavior reference mapping", key)

    def hash_map(self, value: Any, label: str, expected_paths: set[str] | None = None) -> None:
        if not isinstance(value, dict) or not value:
            self.issue(f"{label}_hashes_missing", f"{self.name} has no recorded {label} hashes")
            return
        observed: set[str] = set()
        for raw_path, digest in value.items():
            if not isinstance(raw_path, str) or not isinstance(digest, str) or not SHA256_RE.match(digest.lower()):
                self.issue(f"{label}_hash_invalid", f"invalid {label} hash entry: {raw_path}")
                if isinstance(raw_path, str):
                    self.block_hash_target(label, raw_path)
                continue
            path = repo_path(self.root, raw_path)
            if path is None or not path.is_file():
                self.issue(f"{label}_hash_target_missing", f"{label} hash target is missing or outside repository: {raw_path}")
                self.block_hash_target(label, raw_path)
                continue
            observed.add(raw_path.replace("\\", "/"))
            actual = sha256(path)
            if actual != digest.lower():
                self.issue(f"{label}_hash_mismatch", f"{label} hash mismatch for {raw_path}")
                self.block_hash_target(label, raw_path)
        if expected_paths is not None and observed != expected_paths:
            missing = sorted(expected_paths - observed)
            extra = sorted(observed - expected_paths)
            self.issue(f"{label}_hash_coverage_mismatch", f"{label} hash coverage differs; missing={missing}, extra={extra}")
            if label == "artifact":
                for raw_path in missing:
                    self.block_hash_target(label, raw_path)

    def block_hash_target(self, label: str, raw_path: str) -> None:
        normalized = raw_path.replace("\\", "/")
        if label == "artifact":
            affected = {key for key, path in self.artifact_paths.items() if path == normalized}
            for kind, id_ in affected:
                self.issue("artifact_hash_invalid_for_item", f"{kind}/{id_} blocked by changed artifact {normalized}", (kind, id_))
            return
        if normalized in {"docs/baselines/g0.json", "data/manifests/content_deferred.json"}:
            affected = set(self.items)
        else:
            matching_sources = {
                key for key, entry in self.expected.items()
                if entry.get("source", {}).get("path") == normalized
            }
            affected = matching_sources or set(self.items)
        for kind, id_ in affected:
            self.issue("input_hash_drift", f"{kind}/{id_} blocked by changed input {normalized}", (kind, id_))

    def input_hashes(self) -> None:
        hashes = self.batch.get("input_sha256")
        if not hashes and self.name == "entities":
            hashes = self.batch.get("input_sha256")
        self.hash_map(hashes, "input")
        normalized = {path.replace("\\", "/") for path in hashes} if isinstance(hashes, dict) else set()
        required = {
            "docs/baselines/g0.json",
            "data/manifests/content_deferred.json",
        }
        for key in self.expected:
            source = self.expected[key].get("source", {})
            if isinstance(source, dict) and isinstance(source.get("path"), str):
                required.add(source["path"])
        missing = sorted(required - normalized)
        if missing:
            self.issue("input_hash_coverage_missing", f"{self.name} input hashes omit required inputs: {missing}")
            for path in missing:
                self.block_hash_target("input", path)

    def output_hashes(self) -> None:
        recorded = self.batch.get("staged_record_sha256") or self.batch.get("artifact_sha256")
        paths = set(self.artifact_paths.values())
        if self.name == "cards" and not recorded:
            self.issue("artifact_hashes_missing", "cards batch does not record a hash for cards.json")
            for key in self.items:
                self.issue("artifact_hashes_missing", f"{key[0]}/{key[1]} has no staged artifact hash", key)
            return
        if self.name == "entities" and not recorded:
            self.issue("artifact_hashes_missing", "entities batch report does not record hashes for staged definition files")
            for key in self.items:
                self.issue("artifact_hashes_missing", f"{key[0]}/{key[1]} has no staged artifact hash", key)
            return
        self.hash_map(recorded, "artifact", paths)

    def schema_probe(self, rows: list[dict[str, Any]]) -> set[tuple[str, str]]:
        declaration = self.batch.get("schema_probe")
        if isinstance(declaration, dict):
            by_id = {row.get("id"): row.get("kind") for row in rows}
            matched: set[tuple[str, str]] = set()
            per_id = declaration.get("items") or declaration.get("by_id") or declaration.get("results")
            if isinstance(per_id, dict):
                for value, result in per_id.items():
                    if not isinstance(value, str) or not isinstance(result, dict) or result.get("status") != "passed":
                        continue
                    if "/" in value:
                        kind, id_ = value.split("/", 1)
                        matched.add((kind, id_))
                    elif value in by_id:
                        matched.add((by_id[value], value))
            if declaration.get("status") == "passed":
                ids = declaration.get("ids", [])
                if not isinstance(ids, list):
                    self.issue("schema_probe_evidence_invalid", "schema_probe.ids must be an array")
                    return matched
                for value in ids:
                    if not isinstance(value, str):
                        continue
                    if "/" in value:
                        kind, id_ = value.split("/", 1)
                        matched.add((kind, id_))
                    elif value in by_id:
                        matched.add((by_id[value], value))
            if matched:
                return matched

        if self.name == "flow":
            exit_path = self.batch_dir / "schema_probe.exit_code.txt"
            output_path = self.batch_dir / "schema_probe.stdout.txt"
        elif self.name == "entities":
            exit_path = self.batch_dir / "runtime_probe/evidence/exit_code.txt"
            output_path = self.batch_dir / "stdout.txt"
        else:
            self.issue("schema_probe_missing", "cards batch has static mapping only; no executable schema probe evidence")
            return set()
        try:
            exit_code = int(read_text(exit_path).strip())
            output = read_text(output_path)
        except (OSError, UnicodeError, ValueError) as exc:
            self.issue("schema_probe_evidence_invalid", f"schema probe evidence cannot be read: {exc}")
            return set()
        if exit_code != 0:
            self.issue("schema_probe_failed", f"{self.name} schema probe exit code is {exit_code}")
            return set()
        matched = {
            (kind, id_)
            for kind, id_ in re.findall(r"SCHEMA_OK\s+([a-z_]+)/([A-Z][A-Z0-9_]*)", output)
        }
        if not matched:
            self.issue("schema_probe_output_missing", f"{self.name} probe output contains no SCHEMA_OK records")
        return matched

    def require_attestation(self, field: str, rows: list[dict[str, Any]], code: str) -> None:
        attestation = self.batch.get(field)
        expected_ids = {f"{kind}/{id_}" for kind, id_ in self.expected}
        passed_ids: set[str] = set()
        if isinstance(attestation, dict):
            if attestation.get("status") == "passed":
                ids = attestation.get("ids")
                if isinstance(ids, list):
                    passed_ids.update(value for value in ids if isinstance(value, str))
            per_id = attestation.get("items") or attestation.get("by_id") or attestation.get("results")
            if isinstance(per_id, dict):
                passed_ids.update(
                    id_ for id_, value in per_id.items()
                    if isinstance(value, dict) and value.get("status") == "passed"
                )
        passed_ids.intersection_update(expected_ids)
        missing = expected_ids - passed_ids
        if missing:
            self.issue(code, f"{self.name} {field} attestation is missing {sorted(missing)}")
            for full_id in sorted(missing):
                kind, id_ = full_id.split("/", 1)
                self.issue(code, f"{kind}/{id_} remains unverified for {field}", (kind, id_))

    def run(self) -> dict[str, Any]:
        self.load_batch()
        rows = self.load_items()
        self.check_ids(rows)
        self.check_sources_and_refs(rows)
        self.input_hashes()
        self.output_hashes()
        schema_passed = self.schema_probe(rows)
        expected_keys = set(self.expected)
        if schema_passed != expected_keys:
            missing = sorted(expected_keys - schema_passed)
            extra = sorted(schema_passed - expected_keys)
            self.issue("schema_probe_coverage_mismatch", f"schema probe coverage differs; missing={missing}, extra={extra}")
            for key in missing:
                self.issue("schema_unverified", f"{key[0]}/{key[1]} has no successful schema probe", key)
        self.require_attestation("reference_closure", rows, "reference_closure_unverified")
        self.require_attestation("handler_verification", rows, "handler_unverified")
        self.require_attestation("behavior_tests", rows, "behavior_tests_unverified")

        for key, item in self.items.items():
            item["accepted"] = not item["issues"]
        return {
            "batch": self.name,
            "accepted": not self.issues,
            "expected_count": len(self.expected),
            "observed_count": len(rows),
            "issues": self.issues,
            "items": [self.items[key] for key in sorted(self.items)],
        }


def verify(root: Path = ROOT, batch: str | None = None) -> dict[str, Any]:
    root = root.resolve()
    frozen, registry_errors = frozen_registry(root)
    names = [batch] if batch else list(BATCH_KINDS)
    results = [BatchAudit(root, name, frozen).run() for name in names]
    assigned: set[tuple[str, str]] = set()
    for name in BATCH_KINDS:
        assigned.update(key for key in frozen if key[0] in BATCH_KINDS[name])
    if assigned != set(frozen):
        registry_errors.append({"code": "unassigned_frozen_ids", "message": "some frozen IDs are not assigned to a staging batch"})
    if not batch:
        observed = {
            (item["kind"], item["id"])
            for result in results for item in result["items"]
        }
        if observed != set(frozen):
            registry_errors.append({"code": "frozen_coverage_mismatch", "message": "all-batch staging IDs do not exactly cover frozen G2 IDs"})
    return {
        "accepted": not registry_errors and all(result["accepted"] for result in results),
        "g2_stage_gate_passed": False,
        "scope": "isolated staging batch audit only",
        "frozen_count": len(frozen),
        "registry_issues": registry_errors,
        "batches": results,
    }


def render_text(report: dict[str, Any]) -> str:
    lines = [f"G2 staging batch audit: {'ACCEPTED' if report['accepted'] else 'REJECTED'}",
             f"Frozen definitions: {report['frozen_count']}",
             "G2 stage gate: not established by this audit"]
    for batch in report["batches"]:
        lines.append(f"[{batch['batch']}] {'PASSED' if batch['accepted'] else 'REJECTED'}; observed={batch['observed_count']}/{batch['expected_count']}")
        for issue in batch["issues"]:
            lines.append(f"  {issue['code']}: {issue['message']}")
        for item in batch["items"]:
            if item["issues"]:
                reasons = "; ".join(issue["code"] for issue in item["issues"])
                lines.append(f"  {item['kind']}/{item['id']}: {reasons}")
    for issue in report["registry_issues"]:
        lines.append(f"[registry] {issue['code']}: {issue['message']}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only G2 staging acceptance audit")
    parser.add_argument("--batch", choices=sorted(BATCH_KINDS), help="audit one isolated batch; default audits all batches")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--json", action="store_true", help="print the detailed machine-readable report")
    args = parser.parse_args(argv)
    report = verify(args.root, args.batch)
    print(json.dumps(report, ensure_ascii=False, indent=2) if args.json else render_text(report))
    return 0 if report["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
