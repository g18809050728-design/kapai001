# -*- coding: utf-8 -*-
"""第三轮组合方案（proposal 3）：单轴结果合并后的复测。

- 侵蚀输出 ×0.75（层数不变，避免连带削弱混合/诱发）
- 结果核验 10+3×取回（最多 +18）；交班确认 10+3×恢复（最多 +18）
- 复用清单：取回策略后本回合下一张工作 +3
- 团队节奏：首张合作后本回合下一张工作 +3
- 内化：独立交卷 8+2x，分工已内化 8+3
- 诱发穿透 2
- 遭遇：N01 68、N02 72、N03 78，其余同 §10.2
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim_balance as sb

ENCS = ["N01", "N02", "N03", "N04", "Q01", "B01"]
ENCOUNTERS3 = {
    "N01": dict(hp=[68], ddl=7, intents=[("p", 8), ("p", 10)], exam=False),
    "N02": dict(hp=[72], ddl=7, intents=[("b", 6), ("p", 10)], exam=False),
    "N03": dict(hp=[78], ddl=7, intents=[("p", 9), ("pb", 6)], exam=False),
    "N04": dict(hp=[78], ddl=7, intents=[("a", 1), ("p", 12)], exam=False),
    "Q01": dict(hp=[68], ddl=7, intents=[("p", 9), ("b", 8), ("p", 12)], exam=True),
    "B01": dict(hp=[30, 38, 38], ddl=10, intents=[("p", 9), ("b", 7), ("p", 11)], exam=True),
}


def main(n=1500):
    sb.PROPOSAL = 3
    sb.AXIS = ""
    sb.STATUS_CAP["侵蚀"] = 12
    sb.HP_SCALE = 1.0
    sb.ENCOUNTERS.update(ENCOUNTERS3)

    rows = []
    for char in ("P01", "P02", "P03", "P04"):
        for build in sb.BUILDS[char]:
            for enc in ENCS:
                for dev in (False, True):
                    deck = sb.build_deck(char, build, dev)
                    wins = 0
                    turns = []
                    hps = []
                    for seed in range(n):
                        b = sb.Battle(char, deck, enc, seed)
                        if b.run() == "win":
                            wins += 1
                            turns.append(b.turn)
                            hps.append(b.hp)
                    rows.append({"char": char, "build": build, "encounter": enc,
                                 "developed": dev, "win": wins / n,
                                 "avg_turn": statistics.mean(turns) if turns else None,
                                 "avg_hp": statistics.mean(hps) if hps else None})
    with open(os.path.join(HERE, "results_proposal3.json"), "w", encoding="utf-8") as f:
        json.dump({"mode": "proposal3", "proposal": 3, "trials": n,
                   "encounters": {k: v["hp"] for k, v in ENCOUNTERS3.items()},
                   "rows": rows}, f, ensure_ascii=False, indent=1)

    lines = ["| 人物 | 构筑 | " + " | ".join(ENCS) + " | 普通均值 |",
             "|---|---|" + "---|" * 7]
    for char in ("P01", "P02", "P03", "P04"):
        for build in sb.BUILDS[char]:
            ws = [next(r["win"] for r in rows if r["char"] == char and r["build"] == build
                       and r["encounter"] == e and r["developed"]) * 100 for e in ENCS]
            lines.append(f"| {char} | {build} | " + " | ".join(f"{w:.0f}" for w in ws)
                         + f" | {statistics.mean(ws[:4]):.1f} |")
    with open(os.path.join(HERE, "matrix_proposal3.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    for dev, label in ((False, "starter"), (True, "developed")):
        vals = [r["win"] for r in rows if r["developed"] == dev]
        norm = [r["win"] for r in rows if r["developed"] == dev and r["encounter"] in ENCS[:4]]
        six = [r["win"] for r in rows if r["developed"] == dev]
        print(f"{label}: normal={statistics.mean(norm)*100:.1f}% six={statistics.mean(six)*100:.1f}%")


if __name__ == "__main__":
    main()
