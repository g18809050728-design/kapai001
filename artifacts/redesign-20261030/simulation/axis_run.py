# -*- coding: utf-8 -*-
"""第三轮：单轴实验 + 组合复测（提案1 为基线，遭遇用 §10.2）。

用法：
    python artifacts/redesign-20261030/simulation/axis_run.py
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim_balance as sb

ENCS = ["N01", "N02", "N03", "N04", "Q01", "B01"]
PROPOSED = {
    "N01": dict(hp=[64], ddl=7, intents=[("p", 8), ("p", 10)], exam=False),
    "N02": dict(hp=[68], ddl=7, intents=[("b", 6), ("p", 10)], exam=False),
    "N03": dict(hp=[74], ddl=7, intents=[("p", 9), ("pb", 6)], exam=False),
    "N04": dict(hp=[78], ddl=7, intents=[("a", 1), ("p", 12)], exam=False),
    "Q01": dict(hp=[68], ddl=7, intents=[("p", 9), ("b", 8), ("p", 12)], exam=True),
    "B01": dict(hp=[30, 38, 38], ddl=10, intents=[("p", 9), ("b", 7), ("p", 11)], exam=True),
}
KEY = [("P01", "复用引擎"), ("P01", "集中爆发"), ("P02", "发表一波"),
       ("P03", "侵蚀增殖"), ("P03", "诱发连打"), ("P03", "混合抑制"),
       ("P04", "接力轮换"), ("P04", "备考内化")]
ALL = [(c, b) for c in ("P01", "P02", "P03", "P04") for b in sb.BUILDS[c]]


def set_mode(axis):
    sb.PROPOSAL = 1
    sb.AXIS = axis
    sb.STATUS_CAP["侵蚀"] = 12
    sb.HP_SCALE = 1.0
    sb.ENCOUNTERS.update(PROPOSED)


def run(mode, axis, builds, n, developed=True):
    set_mode(axis)
    rows = []
    for char, build in builds:
        for enc in ENCS:
            deck = sb.build_deck(char, build, developed)
            wins = 0
            turns = []
            for seed in range(n):
                b = sb.Battle(char, deck, enc, seed)
                if b.run() == "win":
                    wins += 1
                    turns.append(b.turn)
            rows.append({"char": char, "build": build, "encounter": enc,
                         "win": wins / n, "avg_turn": statistics.mean(turns) if turns else None})
    with open(os.path.join(HERE, f"results_axis_{mode}.json"), "w", encoding="utf-8") as f:
        json.dump({"mode": mode, "axis": axis, "trials": n, "rows": rows}, f, ensure_ascii=False, indent=1)
    return rows


def summary(rows, builds):
    out = []
    for char, build in builds:
        ws = [next(r["win"] for r in rows if r["char"] == char and r["build"] == build
                   and r["encounter"] == e) * 100 for e in ENCS]
        out.append((char, build, statistics.mean(ws[:4]), ws[-1]))
    return out


if __name__ == "__main__":
    runs = [("base", ""), ("erosion", "erosion"), ("finisher", "finisher"),
            ("inner", "inner"), ("induce", "induce")]
    for mode, axis in runs:
        rows = run(mode, axis, KEY, 800)
        print(f"== {mode} ==")
        for char, build, normal, b01 in summary(rows, KEY):
            print(f"  {char} {build:<6} normal={normal:5.1f}%  B01={b01:5.1f}%")
    rows = run("combo", "combo", ALL, 1200)
    print("== combo (all builds) ==")
    for char, build, normal, b01 in summary(rows, ALL):
        print(f"  {char} {build:<6} normal={normal:5.1f}%  B01={b01:5.1f}%")
    normal_all = [r["win"] for r in rows if r["encounter"] in ENCS[:4]]
    print(f"  normal overall {statistics.mean(normal_all)*100:.1f}%  six-enc {statistics.mean(r['win'] for r in rows)*100:.1f}%")
