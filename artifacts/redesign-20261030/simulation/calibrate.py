# -*- coding: utf-8 -*-
"""按遭遇校准难度：使 12 套成型构筑在该遭遇的平均胜率约 60%，再跑校准档。

用法：
    python artifacts/redesign-20261030/simulation/calibrate.py
输出：
    results_calibrated.json（覆盖）
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE if HERE in sys.path else HERE)
sys.path.insert(0, HERE)
import sim_balance as sb

ENCS = ["N01", "N02", "N03", "N04", "Q01", "B01"]
BUILDS = [(c, b) for c in ("P01", "P02", "P03", "P04") for b in sb.BUILDS[c]]
GRID = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0, 2.2, 2.5, 3.0, 3.5, 4.0]


def avg_win(enc, alpha, n=100):
    sb.HP_SCALE = alpha
    ws = []
    for char, build in BUILDS:
        deck = sb.build_deck(char, build, True)
        wins = sum(1 for seed in range(n) if sb.Battle(char, deck, enc, seed).run() == "win")
        ws.append(wins / n)
    return statistics.mean(ws)


def main():
    chosen = {}
    for enc in ENCS:
        best = None
        for alpha in GRID:
            w = avg_win(enc, alpha)
            if best is None or abs(w - 0.6) < abs(best[1] - 0.6):
                best = (alpha, w)
        chosen[enc] = best
        print(enc, "alpha=%.1f avg=%.1f%%" % (best[0], best[1] * 100))

    rows = []
    for char, build in BUILDS:
        for enc in ENCS:
            sb.HP_SCALE = chosen[enc][0]
            for dev in (False, True):
                deck = sb.build_deck(char, build, dev)
                n = 1500
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
                    "hp_scale": chosen[enc][0],
                })

    out = {
        "assumptions": {
            "calibration_target": 0.6,
            "trials": 1500,
            "chosen_scale": {k: v[0] for k, v in chosen.items()},
            "calibration_avg": {k: v[1] for k, v in chosen.items()},
        },
        "rows": rows,
    }
    with open(os.path.join(HERE, "results_calibrated.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("wrote results_calibrated.json")


if __name__ == "__main__":
    main()
