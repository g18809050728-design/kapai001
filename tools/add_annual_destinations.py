"""Add destination encounters without rewriting any historical definition."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATIONS = {
    "job": ("秋招终面", ["简历复核", "现场案例", "综合面谈"],
            [{"pressure": 12}, {"shield": 8}, {"pressure": 10}]),
    "exam": ("考研复试", ["专业笔试", "专业问答", "综合复试"],
             [{"pressure": 6}, {"pressure": 8, "shield": 8}, {"pressure": 8}]),
    "research": ("保研答辩", ["成果审阅", "研究陈述", "学术追问"],
                 [{"shield": 8}, {"pressure": 10}, {"pressure": 12}]),
    "abroad": ("留学面试", ["申请材料", "动机陈述", "跨文化面谈"],
               [{"pressure": 11, "shield": 4}, {"pressure": 11}, {"shield": 4}]),
}


def extend(definitions, manifest):
    """Shared by the historical builder and the additive update command."""
    base_encounter = next(d for d in definitions["encounters"] if d["id"] == "FY_B4")
    base_task = next(d for d in definitions["tasks"] if d["id"] == "FY_B4_TASK")
    for destination, (title, phases, timing) in DESTINATIONS.items():
        encounter_id = "FY_ROUTE_" + destination
        task_id = encounter_id + "_TASK"
        task = copy.deepcopy(base_task)
        task.update(id=task_id, name_key=title)
        for index, phase in enumerate(task["phases"]):
            phase["name_key"] = phases[index]
            phase["intents"] = [dict(index=i, text_key="、".join(
                ("催促" if key == "pressure" else "材料复核") + str(amount)
                for key, amount in effects.items()), **effects) for i, effects in enumerate(timing)]
        encounter = copy.deepcopy(base_encounter)
        encounter.update(id=encounter_id, name_key=title, members=[task_id])
        if "initial_members" in encounter:
            encounter["initial_members"] = [task_id]
        for group, kind, definition in [("tasks", "task", task), ("encounters", "encounter", encounter)]:
            definitions[group] = [d for d in definitions[group] if d["id"] != definition["id"]] + [definition]
            if definition["id"] not in manifest["enabled"][kind]:
                manifest["enabled"][kind].append(definition["id"])


def main():
    package = ROOT / "data/four_year"
    manifest_path = package / "manifests/campus_four_year.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    definitions = {name: json.loads((package / "definitions" / (name + ".json")).read_text(encoding="utf-8-sig"))
                   for name in ("tasks", "encounters")}
    extend(definitions, manifest)
    for name, data in definitions.items():
        (package / "definitions" / (name + ".json")).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
