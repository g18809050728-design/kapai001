#!/usr/bin/env python3
"""Build elite encounter content from the two elite design drafts.

Sources:
  docs/精英敌人设计草稿.md   (Q0A, Q0B, Q0C, Q0D, Q0E)
  docs/精英敌人设计草稿2.md (E01..E07)

The script is idempotent: definitions owned by it are replaced, other
definitions keep their order and content. Run from the repository root:

    python artifacts/elite-build-20261101/build_elite_content.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFINITIONS = ROOT / "data" / "definitions"
MANIFEST = ROOT / "data" / "manifests" / "campus_mvp.json"
LABELS = ROOT / "src" / "ui" / "ui_labels.json"

LABELS_NEW = {}


def read_json(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, data):
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def upsert(rows, new_rows):
    owned = {row["id"] for row in new_rows}
    kept = [row for row in rows if row["id"] not in owned]
    return kept + new_rows


def intent(owner, index, slug, text, **extra):
    key = "task.%s.intent.%s" % (owner.lower(), slug)
    LABELS_NEW[key] = text
    payload = {"index": index, "text_key": key}
    payload.update(extra)
    return payload


def phase(key, work_max, intents, label=None, loop=None):
    payload = {"phase_key": key, "work_max": work_max, "intents": intents}
    if label is not None:
        LABELS_NEW[key] = label
    if loop is not None:
        payload["intent_loop"] = loop
    return payload


def task(task_id, name, phases, **extra):
    LABELS_NEW[task_id] = name
    payload = {
        "id": task_id,
        "name_key": "task.%s.name" % task_id.lower(),
        "kind": "elite",
        "phases": phases,
    }
    payload.update(extra)
    return payload


def encounter(encounter_id, name, members, base_ddl, terms, exam_flags,
              initial_members=None, absorb_cooperation=None):
    LABELS_NEW[encounter_id] = name
    payload = {
        "id": encounter_id,
        "name_key": "encounter.%s.name" % encounter_id.lower(),
        "kind": "elite",
        "members": members,
        "base_ddl": base_ddl,
        "terms": terms,
        "exam_flags": exam_flags,
    }
    if initial_members is not None:
        payload["initial_members"] = initial_members
    if absorb_cooperation is not None:
        payload["absorb_cooperation"] = absorb_cooperation
    return payload


TASKS = [
    # --- 精英敌人设计草稿2 §2：第一学期精英候选 -----------------------------
    task("E01", "期中考试", [
        phase("choice_questions", 16, [
            intent("E01", 0, "choice_a_pressure5", "施加压力", pressure=5),
            intent(
                "E01", 1, "choice_b_anxiety1", "我方获得 1 层焦虑", shield=6,
                gain_status={"status": "anxiety", "stacks": 1, "target": "player"},
            ),
        ], "选择题"),
        phase("fill_blank", 22, [
            intent("E01", 0, "fill_a_pressure7", "施加压力", pressure=7),
            intent(
                "E01", 1, "fill_b_procrastination1", "我方获得 1 层拖延", shield=5,
                gain_status={"status": "procrastination", "stacks": 1, "target": "player"},
            ),
        ], "填空题"),
        phase("essay_questions", 28, [
            intent("E01", 0, "essay_a_pressure9", "施加压力", pressure=9),
            intent("E01", 1, "essay_b_shield6_pressure4", "施加压力", shield=6, pressure=4),
        ], "大题"),
    ]),
    task("E02", "课程设计中期检查", [
        phase("demo", 24, [
            intent("E02", 0, "demo_a_shield8", "获得屏障", shield=8),
            intent("E02", 1, "demo_b_pressure5", "施加压力", pressure=5),
        ], "演示"),
        phase("interrogation", 30, [
            intent("E02", 0, "interrogation_a_pressure7", "施加压力", pressure=7),
            intent(
                "E02", 1, "interrogation_b_x01", "弃牌堆加入 1 张分心消息", shield=4, pressure=4,
                add_card={"card": "X01", "count": 1, "zone": "discard"},
            ),
        ], "质询"),
    ]),
    task("E03", "小组项目冲刺", [
        phase("split", 26, [
            intent(
                "E03", 0, "split_a_shield6_pressure4", "存活单位越多压力越高", shield=6, pressure=4,
                pressure_per_unit=1, pressure_per_unit_cap=3,
            ),
            intent(
                "E03", 1, "split_b_pressure8", "存活单位越多压力越高", pressure=8,
                pressure_per_unit=1, pressure_per_unit_cap=3,
            ),
        ], "分工"),
        phase("integrate", 34, [
            intent(
                "E03", 0, "integrate_a_pressure6", "存活单位越多压力越高", pressure=6,
                pressure_per_unit=1, pressure_per_unit_cap=3,
            ),
            intent(
                "E03", 1, "integrate_b_shield4_pressure6", "存活单位越多压力越高", shield=4,
                pressure=6, pressure_per_unit=1, pressure_per_unit_cap=3,
            ),
        ], "整合"),
    ]),
    # --- 精英敌人设计草稿2 §3：后续学期候选 --------------------------------
    task("E04_1", "建模", [
        phase("modeling", 18, [
            intent("E04_1", 0, "modeling_a_pressure3", "施加压力", pressure=3),
            intent("E04_1", 1, "modeling_b_shield5", "获得屏障", shield=5),
        ]),
    ]),
    task("E04_2", "编程", [
        phase("coding", 20, [
            intent("E04_2", 0, "coding_a_shield4", "获得屏障", shield=4),
            intent("E04_2", 1, "coding_b_pressure4", "施加压力", pressure=4),
        ]),
    ]),
    task("E04_3", "论文", [
        phase("paper", 22, [
            intent(
                "E04_3", 0, "paper_a_procrastination1", "我方获得 1 层拖延", pressure=2,
                gain_status={"status": "procrastination", "stacks": 1, "target": "player"},
            ),
            intent("E04_3", 1, "paper_b_shield3_pressure2", "施加压力", shield=3, pressure=2),
        ]),
    ]),
    task("E05", "保研夏令营", [
        phase("materials_review", 24, [
            intent("E05", 0, "materials_a_pressure7", "施加压力", pressure=7),
            intent(
                "E05", 1, "materials_b_anxiety1", "我方获得 1 层焦虑", shield=6,
                gain_status={"status": "anxiety", "stacks": 1, "target": "player"},
            ),
        ], "材料审核"),
        phase("written_test", 22, [
            intent("E05", 0, "written_a_pressure9", "施加压力", pressure=9),
            intent(
                "E05", 1, "written_b_procrastination1", "我方获得 1 层拖延", shield=8,
                gain_status={"status": "procrastination", "stacks": 1, "target": "player"},
            ),
        ], "笔试"),
        phase("interview_round", 26, [
            intent("E05", 0, "interview_a_pressure10", "施加压力", pressure=10),
            intent("E05", 1, "interview_b_pressure7_twice", "两段压力", pressure=7, pressure_times=2),
        ], "面试"),
    ]),
    task("E06", "实习群面", [
        phase("self_intro", 24, [
            intent(
                "E06", 0, "intro_a_x02", "手牌加入 1 张面试题", pressure=6,
                add_card={"card": "X02", "count": 1, "zone": "hand"},
            ),
            intent("E06", 1, "intro_b_shield4_pressure4", "施加压力", shield=4, pressure=4),
        ], "自我介绍"),
        phase("followup", 32, [
            intent(
                "E06", 0, "followup_a_x02", "手牌加入 1 张面试题", pressure=8,
                add_card={"card": "X02", "count": 1, "zone": "hand"},
            ),
            intent("E06", 1, "followup_b_pressure5_twice", "两段压力", pressure=5, pressure_times=2),
        ], "追问"),
    ]),
    task("E07", "补考", [
        phase("retake_written", 18, [
            intent("E07", 0, "written_a_pressure8", "施加压力", pressure=8),
            intent(
                "E07", 1, "written_b_anxiety1", "我方获得 1 层焦虑", shield=5,
                gain_status={"status": "anxiety", "stacks": 1, "target": "player"},
            ),
        ], "补考笔试"),
        phase("score_review", 12, [
            intent("E07", 0, "review_a_pressure9", "施加压力", pressure=9),
            intent("E07", 1, "review_b_shield4_pressure4", "施加压力", shield=4, pressure=4),
        ], "成绩复核"),
        phase("retake_defense", 16, [
            intent("E07", 0, "defense_a_pressure10", "施加压力", pressure=10),
            intent(
                "E07", 1, "defense_b_drowsiness1", "我方获得 1 层困倦", pressure=6,
                gain_status={"status": "drowsiness", "stacks": 1, "target": "player"},
            ),
        ], "补考答辩"),
    ]),
    # --- 精英敌人设计草稿 Q0A：小组大作业 ----------------------------------
    task("Q0A_1", "需求分析", [
        phase("requirements", 27, [
            intent("Q0A_1", 0, "a_pressure6", "施加压力", pressure=6),
            intent("Q0A_1", 1, "b_shield7", "获得屏障", shield=7),
        ]),
    ]),
    task("Q0A_2", "文档编写", [
        phase("documentation", 29, [
            intent("Q0A_2", 0, "a_pressure5", "施加压力", pressure=5),
            intent("Q0A_2", 1, "b_pressure6", "施加压力", pressure=6),
        ]),
    ]),
    task("Q0A_3", "代码开发", [
        phase("coding", 25, [
            intent("Q0A_3", 0, "a_shield7", "获得屏障", shield=7),
            intent("Q0A_3", 1, "b_pressure9", "施加压力", pressure=9),
            intent(
                "Q0A_3", 2, "c_summon_test_run", "召唤测试运行",
                summon_tasks=[{"task": "Q0A_3_1", "count": 1}],
            ),
        ]),
    ]),
    task("Q0A_3_1", "测试运行", [
        phase("test_run", 10, [
            intent("Q0A_3_1", 0, "a_shield3", "获得屏障", shield=3),
            intent("Q0A_3_1", 1, "b_pressure7_self_destruct", "施加压力并自爆", pressure=7,
                   self_destruct=True),
        ]),
    ], victory_required=False),
    # --- 精英敌人设计草稿 Q0B：作业答辩 ------------------------------------
    task("Q0B_1", "答辩作业", [
        phase("defense", 15, [
            intent("Q0B_1", 0, "a_shield5_restore5", "获得屏障并恢复 5 点未完成量", shield=5,
                   work_restore=5),
            intent("Q0B_1", 1, "b_shield2_pressure2", "施加压力", shield=2, pressure=2),
        ]),
    ]),
    task("Q0B_2", "作业答辩", [
        phase("paperwork", 45, [
            intent("Q0B_2", 0, "a_pressure6", "施加压力", pressure=6),
            intent("Q0B_2", 1, "b_shield3_pressure2", "施加压力", shield=3, pressure=2),
            intent(
                "Q0B_2", 2, "c_transform_defense", "转换为答辩作业，剩余 DDL +1",
                transform_task={"task": "Q0B_1"}, ddl_bonus=1,
            ),
        ]),
    ]),
    # --- 精英敌人设计草稿 Q0C / Q0D：英语四、六级 --------------------------
    task("Q0C", "英语四级", [
        phase("independent_answer", 50, [
            intent("Q0C", 0, "a_pressure9_first_round", "仅第一回合施加高压", pressure=9),
            intent(
                "Q0C", 1, "b_shield2_pressure4_brainstorm1", "自身获得 1 层绞尽脑汁",
                shield=2, pressure=4,
                gain_status={"status": "brainstorm", "stacks": 1, "target": "task"},
            ),
        ], loop="clamp"),
    ]),
    task("Q0D", "英语六级", [
        phase("independent_answer", 70, [
            intent("Q0D", 0, "a_pressure13_first_round", "仅第一回合施加高压", pressure=13),
            intent(
                "Q0D", 1, "b_shield4_pressure6_brainstorm2", "自身获得 2 层绞尽脑汁",
                shield=4, pressure=6,
                gain_status={"status": "brainstorm", "stacks": 2, "target": "task"},
            ),
        ], loop="clamp"),
    ]),
    # --- 精英敌人设计草稿 Q0E：大项目与额外需求 ----------------------------
    task("Q0E_1", "大项目", [
        phase("big_project", 50, [
            intent(
                "Q0E_1", 0, "a_pressure4_summon_extra", "召唤两个额外需求", pressure=4,
                summon_tasks=[{"task": "Q0E_2", "count": 1}, {"task": "Q0E_3", "count": 1}],
            ),
            intent("Q0E_1", 1, "b_shield2_pressure4", "施加压力", shield=2, pressure=4),
        ], loop="clamp"),
    ]),
    task("Q0E_2", "额外需求1", [
        phase("extra_requirement_1", 15, [
            intent("Q0E_2", 0, "a_shield8", "获得屏障", shield=8),
            intent(
                "Q0E_2", 1, "b_pressure3_brainstorm1", "自身获得 1 层绞尽脑汁", pressure=3,
                gain_status={"status": "brainstorm", "stacks": 1, "target": "task"},
            ),
        ]),
    ], victory_required=False),
    task("Q0E_3", "额外需求2", [
        phase("extra_requirement_2", 17, [
            intent("Q0E_3", 0, "a_shield8", "获得屏障", shield=8),
            intent(
                "Q0E_3", 1, "b_pressure2_shield1_confusion2", "自身获得 2 层迷惑", pressure=2,
                shield=1,
                gain_status={"status": "confusion", "stacks": 2, "target": "task"},
            ),
        ]),
    ], victory_required=False),
]

ENCOUNTERS = [
    encounter("E01", "期中考试", ["E01"], 9, [1, 2, 3], ["independent_answer"]),
    encounter("E02", "课程设计中期检查", ["E02"], 8, [1, 2, 3, 4], ["independent_answer"]),
    encounter("E03", "小组项目冲刺", ["E03"], 9, [1, 2, 3, 4], []),
    encounter("E04", "数学建模竞赛", ["E04_1", "E04_2", "E04_3"], 7, [2, 3, 4],
              ["independent_answer"]),
    encounter("E05", "保研夏令营", ["E05"], 10, [3, 4, 5],
              ["independent_answer", "fixed_exam_room"]),
    encounter("E06", "实习群面", ["E06"], 8, [2, 3, 4], ["independent_answer"]),
    encounter("E07", "补考", ["E07"], 6, [4, 5, 6], ["independent_answer"]),
    encounter("Q0A", "小组大作业", ["Q0A_1", "Q0A_2", "Q0A_3", "Q0A_3_1"], 8,
              [2, 3, 4, 5], [],
              initial_members=["Q0A_1", "Q0A_2", "Q0A_3"],
              absorb_cooperation={"draw_per_card": 1, "focus_per_card": 1}),
    encounter("Q0B", "作业答辩", ["Q0B_1", "Q0B_2"], 8, [1, 2, 3, 4], [],
              initial_members=["Q0B_2"]),
    # 2026-11-02 首期试玩：作业答辩与英语四级提前进第一学期精英池（草稿原为 2~4/2~6）。
    encounter("Q0C", "英语四级", ["Q0C"], 10, [1, 2, 3, 4, 5, 6], ["independent_answer"]),
    encounter("Q0D", "英语六级", ["Q0D"], 8, [2, 3, 4, 5, 6], ["independent_answer"]),
    encounter("Q0E", "大项目", ["Q0E_1", "Q0E_2", "Q0E_3"], 10, [2, 3, 4], [],
              initial_members=["Q0E_1"]),
]

STATUSES = [
    {
        "id": "brainstorm",
        "name_key": "status.brainstorm.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "brainstorm",
    },
    {
        "id": "confusion",
        "name_key": "status.confusion.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "confusion",
    },
]

STATUS_RULES = {
    "brainstorm": {"cap": 3, "pressure_per_stack": 1},
    "confusion": {"cap": 3, "shield_per_stack": 1},
}

BURDEN_CARD = {
    "id": "X02",
    "name_key": "card.X02.name",
    "type": "strategy",
    "rarity": None,
    "tags": ["special", "temporary"],
    "cost": 0,
    "target": "self",
    "exhaust": False,
    "unplayable": True,
    "effects": [],
}

EXTRA_LABELS = {
    "brainstorm": "绞尽脑汁",
    "confusion": "迷惑",
    "X02": "面试题",
}


def main():
    task_rows = upsert(read_json(DEFINITIONS / "tasks.json"), TASKS)
    encounter_rows = upsert(read_json(DEFINITIONS / "encounters.json"), ENCOUNTERS)
    status_rows = upsert(read_json(DEFINITIONS / "statuses.json"), STATUSES)
    card_rows = upsert(read_json(DEFINITIONS / "cards.json"), [BURDEN_CARD])

    rulesets = read_json(DEFINITIONS / "rulesets.json")
    numeric = rulesets[0]["statuses"]
    for status_id, rule in STATUS_RULES.items():
        numeric[status_id] = rule

    manifest = read_json(MANIFEST)
    enabled = manifest["enabled"]
    for kind, rows in (
        ("card", [BURDEN_CARD["id"]]),
        ("task", [row["id"] for row in TASKS]),
        ("encounter", [row["id"] for row in ENCOUNTERS]),
        ("status", [row["id"] for row in STATUSES]),
    ):
        existing = enabled[kind]
        merged = existing + [item for item in rows if item not in existing]
        enabled[kind] = merged

    labels_document = read_json(LABELS)
    labels = labels_document["labels"]
    for key, value in LABELS_NEW.items():
        labels[key] = value
    for key, value in EXTRA_LABELS.items():
        labels[key] = value

    write_json(DEFINITIONS / "tasks.json", task_rows)
    write_json(DEFINITIONS / "encounters.json", encounter_rows)
    write_json(DEFINITIONS / "statuses.json", status_rows)
    write_json(DEFINITIONS / "cards.json", card_rows)
    write_json(DEFINITIONS / "rulesets.json", rulesets)
    write_json(MANIFEST, manifest)
    write_json(LABELS, labels_document)

    summary = {
        "tasks": len(TASKS),
        "encounters": len(ENCOUNTERS),
        "statuses": len(STATUSES),
        "cards": 1,
        "labels": len(LABELS_NEW) + len(EXTRA_LABELS),
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
