#!/usr/bin/env python3
"""Summarize the elite playtest run into evidence files.

    python artifacts/playtest-20261102/summarize.py artifacts/verification/playtest-firstterm-20261102
"""

import json
import pathlib
import platform
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
GODOT = r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
FIRST_TERM = ["Q01", "E01", "E02", "E03", "Q0B", "Q0C"]


def main():
    evidence = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
        ROOT / "artifacts" / "verification" / "playtest-firstterm-20261102"
    )
    raw = (evidence / "playtest-all.stdout.txt").read_text(encoding="utf-8")
    match = re.search(r"PLAYTEST_RESULT=(\{.*\})", raw, re.S)
    if match is None:
        print("PLAYTEST_RESULT not found")
        return 1
    data = json.loads(match.group(1))
    (evidence / "playtest-all-summary.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    rows = data["summary"]
    lines = [
        "# 第一学期精英试玩汇总（%s）" % evidence.name,
        "",
        "引擎：`%s`；人物：%s；seed 数：%s；总场次：%d；异常：%d。"
        % (
            GODOT,
            "/".join(data["characters"]),
            data["seeds"],
            sum(int(row["runs"]) for row in rows),
            len(data["errors"]),
        ),
        "",
        "测法：真实生产内容 + `RunService` 起始牌组/饰品，机器人按"
        "“先挡伤害 → 再打作业 → 其它”出牌，**无节点奖励与升级**，是难度下限。",
        "",
        "## 第一学期精英池",
        "",
        "| 精英 | P01 胜率 | P01 回合 | P04 胜率 | P04 回合 |",
        "|---|---:|---:|---:|---:|",
    ]
    by_key = {(row["character"], row["encounter"]): row for row in rows}
    for encounter_id in FIRST_TERM:
        p01 = by_key.get(("P01", encounter_id), {})
        p04 = by_key.get(("P04", encounter_id), {})
        lines.append(
            "| %s | %.0f%% | %.1f | %.0f%% | %.1f |"
            % (
                encounter_id,
                float(p01.get("win_rate", 0.0)) * 100,
                float(p01.get("avg_rounds", 0.0)),
                float(p04.get("win_rate", 0.0)) * 100,
                float(p04.get("avg_rounds", 0.0)),
            )
        )
    lines += [
        "",
        "## 其余精英（未进第一学期）",
        "",
        "| 精英 | P01 胜率 | P04 胜率 |",
        "|---|---:|---:|",
    ]
    for encounter_id in [row["encounter"] for row in rows if row["character"] == "P01"]:
        if encounter_id in FIRST_TERM:
            continue
        p01 = by_key.get(("P01", encounter_id), {})
        p04 = by_key.get(("P04", encounter_id), {})
        lines.append(
            "| %s | %.0f%% | %.0f%% |"
            % (
                encounter_id,
                float(p01.get("win_rate", 0.0)) * 100,
                float(p04.get("win_rate", 0.0)) * 100,
            )
        )
    lines += [
        "",
        "## 边界",
        "",
        "- 机器人下限测量，不等同于平衡验收；不带节点奖励、升级与更多饰品。",
        "- 第一名人物 P01 的 E01 胜率 83%，P04 仅 4%：独立作答废掉 P04 起手的两张合作牌。",
        "- Q0A/Q0D 近似必败（4%/0%），已排除出第一学期。",
        "- Q0B/Q0C 两人物 100% 胜、剩余 DDL 4+，明显偏易，建议下次平衡调整。",
        "",
        "结论与建议见 [精英敌人实现记录](../../../docs/精英敌人实现记录_20261101.md)§7。",
        "",
    ]
    (evidence / "summary.md").write_text("\n".join(lines), encoding="utf-8")
    (evidence / "command.json").write_text(
        json.dumps(
            {
                "command": [
                    GODOT,
                    "--headless",
                    "--path",
                    str(ROOT),
                    "--script",
                    "res://artifacts/playtest-20261102/playtest_elites.gd",
                ],
                "script": "artifacts/playtest-20261102/playtest_elites.gd",
                "seeds": data["seeds"],
                "characters": data["characters"],
                "elites": data["elites"],
                "battles": sum(int(row["runs"]) for row in rows),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (evidence / "environment.json").write_text(
        json.dumps(
            {
                "os": platform.platform(),
                "python": platform.python_version(),
                "godot": GODOT,
                "godot_version": "4.7.2.stable",
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("wrote evidence to", evidence)
    return 0


if __name__ == "__main__":
    sys.exit(main())
