#!/usr/bin/env python3
"""Sync v3.1 card/character names into UI labels without touching v1 labels."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "artifacts/redesign-20261030/campus-cards-v3.json"
LABELS = ROOT / "src/ui/ui_labels.json"


def main() -> None:
    design = json.loads(DESIGN.read_text(encoding="utf-8"))
    labels_doc = json.loads(LABELS.read_text(encoding="utf-8"))
    labels = labels_doc["labels"]
    owners = design.get("owners", {})
    for owner_id in ["P01", "P02", "P03", "P04"]:
        name = owners.get(owner_id, "")
        if name:
            labels[owner_id] = name
    for card in design.get("cards", []) + design.get("tokens", []):
        name = str(card.get("name", "")).strip()
        if name:
            labels[str(card["id"])] = name
    labels.setdefault("R3-U01", "学习搭子")
    labels.setdefault("R3-U02", "旁听同学")
    labels.setdefault("R3-U03", "项目队友")
    labels.setdefault("R3-S01", "自习室")
    labels.setdefault("R3-S01+", "自习室+")
    labels.setdefault("R3-S02", "讨论室")
    labels.setdefault("R3-S02+", "讨论室+")
    labels.setdefault("erosion", "侵蚀")
    labels.setdefault("induced", "诱发")
    labels.setdefault("brittle", "脆化")
    labels.setdefault("feebleness", "乏力")
    labels.setdefault("weakness", "虚弱")
    labels.setdefault("vulnerability", "易伤")
    labels.setdefault("anxiety", "焦虑")
    LABELS.write_text(
        json.dumps(labels_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("labels=%d" % len(labels))


if __name__ == "__main__":
    main()
