# -*- coding: utf-8 -*-
"""按 §10 优化方案跑一次对照：控制组（旧机制＋新遭遇） vs 提案组（新机制＋新遭遇）。

用法：
    python artifacts/redesign-20261030/simulation/proposal_run.py
输出：
    results_control.json / results_proposal.json / matrix_control.md / matrix_proposal.md
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim_balance as sb

ENCS = ["N01", "N02", "N03", "N04", "Q01", "B01"]
BUILDS = [(c, b) for c in ("P01", "P02", "P03", "P04") for b in sb.BUILDS[c]]

PROPOSED_ENCOUNTERS = {
    "N01": dict(hp=[64], ddl=7, intents=[("p", 8), ("p", 10)], exam=False),
    "N02": dict(hp=[68], ddl=7, intents=[("b", 6), ("p", 10)], exam=False),
    "N03": dict(hp=[74], ddl=7, intents=[("p", 9), ("pb", 6)], exam=False),
    "N04": dict(hp=[78], ddl=7, intents=[("a", 1), ("p", 12)], exam=False),
    "Q01": dict(hp=[68], ddl=7, intents=[("p", 9), ("b", 8), ("p", 12)], exam=True),
    "B01": dict(hp=[30, 38, 38], ddl=10, intents=[("p", 9), ("b", 7), ("p", 11)], exam=True),
}

PROPOSED2_ENCOUNTERS = dict(PROPOSED_ENCOUNTERS)
PROPOSED2_ENCOUNTERS.update({
    "N01": dict(hp=[72], ddl=7, intents=[("p", 8), ("p", 10)], exam=False),
    "N02": dict(hp=[74], ddl=7, intents=[("b", 6), ("p", 10)], exam=False),
    "N03": dict(hp=[80], ddl=7, intents=[("p", 9), ("pb", 6)], exam=False),
})


def set_mode(proposal):
    sb.PROPOSAL = proposal
    sb.STATUS_CAP["侵蚀"] = 12 if proposal else 20
    sb.HP_SCALE = 1.0
    sb.ENCOUNTERS.update(PROPOSED2_ENCOUNTERS if proposal >= 2 else PROPOSED_ENCOUNTERS)


def run(mode_name, proposal, n=1500):
    set_mode(proposal)
    rows = []
    for char, build in BUILDS:
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
                rows.append({
                    "char": char, "build": build, "encounter": enc, "developed": dev,
                    "n": n, "win": wins / n,
                    "avg_turn": statistics.mean(turns) if turns else None,
                    "avg_hp": statistics.mean(hps) if hps else None,
                })
    encs = PROPOSED2_ENCOUNTERS if proposal >= 2 else PROPOSED_ENCOUNTERS
    out = {"mode": mode_name, "proposal": proposal, "trials": n,
           "encounters": {k: {"hp": v["hp"], "ddl": v["ddl"]} for k, v in encs.items()},
           "rows": rows}
    path = os.path.join(HERE, f"results_{mode_name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    lines = ["| 人物 | 构筑 | " + " | ".join(ENCS) + " | 普通均值 |",
             "|---|---|" + "---|" * 7]
    for char in ("P01", "P02", "P03", "P04"):
        for build in sb.BUILDS[char]:
            ws = [next(r["win"] for r in rows if r["char"] == char and r["build"] == build
                       and r["encounter"] == e and r["developed"]) * 100 for e in ENCS]
            lines.append(f"| {char} | {build} | " + " | ".join(f"{w:.0f}" for w in ws)
                         + f" | {statistics.mean(ws[:4]):.1f} |")
    with open(os.path.join(HERE, f"matrix_{mode_name}.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    for dev, label in ((False, "starter"), (True, "developed")):
        vals = [r["win"] for r in rows if r["developed"] == dev]
        norm = [r["win"] for r in rows if r["developed"] == dev and r["encounter"] in ENCS[:4]]
        print(f"{mode_name} {label}: all={statistics.mean(vals)*100:.1f}% normal={statistics.mean(norm)*100:.1f}%")
    return rows


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "2":
        run("proposal2", 2)
    else:
        run("control", False)
        run("proposal", 1)
        run("proposal2", 2)
