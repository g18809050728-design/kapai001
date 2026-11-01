# -*- coding: utf-8 -*-
"""v3.1 设计阶段对战/构筑抽象模拟。

不是游戏实现，也不是 G0/G3/G8 验收证据。用于比较四名角色三套构筑在
六种任务原型上的相对表现。模型假设见 README.md 与运行输出的 assumptions。
"""
import json
import math
import os
import random
import re
import statistics
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DATA = json.load(open(os.path.join(ROOT, "artifacts", "redesign-20261030", "campus-cards-v3.json"), encoding="utf-8"))
CARD = {c["id"]: c for c in DATA["cards"]}
CARD.update({t["id"]: t for t in DATA.get("tokens", [])})

HP_SCALE = float(os.environ.get("SIM_HP_SCALE", "3.0"))
PROPOSAL = int(os.environ.get("SIM_PROPOSAL", "0"))
AXIS = os.environ.get("SIM_AXIS", "")

STATUS_CAP = {"侵蚀": 12 if PROPOSAL else 20, "诱发": 3, "易伤": 3, "虚弱": 3, "脆化": 3, "乏力": 4}
STATUS_NAMES = tuple(STATUS_CAP)
MANUAL_BONUS = {"R3-P01-19", "R3-P01-27", "R3-P01-30", "R3-P04-09",
                "R3-P04-13", "R3-P04-27", "R3-P04-28", "R3-P02-35"}


def parse(c):
    t = c["base"]
    p = {
        "cost": c["cost"],
        "type": c["type"],
        "dmg": 0,
        "block": 0,
        "draw": 0,
        "heal": 0,
        "st": [],
        "exhaust": "耗尽" in t,
        "barrier": 0,
        "bonus": 0,
        "bonus_cond": None,
    }
    m = re.search(r"完成(\d+)", t)
    if m:
        p["dmg"] = int(m.group(1))
    m = re.search(r"获得(\d+)放松", t)
    if m:
        p["block"] = int(m.group(1))
    m = re.search(r"抽(\d+)", t)
    if m:
        p["draw"] = int(m.group(1))
    m = re.search(r"恢复(\d+)精力", t)
    if m:
        p["heal"] = int(m.group(1))
    m = re.search(r"移除[^。]*?至多(\d+)屏障", t)
    if m:
        p["barrier"] = int(m.group(1))
    for n, name in re.findall(r"(\d+)(侵蚀|易伤|虚弱|乏力|脆化|诱发)", t):
        p["st"].append((name, int(n)))
    m = re.search(r"额外完成(\d+)", t)
    if m:
        p["bonus"] = int(m.group(1))
        for key, cond in [
            ("连携时", "combo"),
            ("至少2张策略", "s2"),
            ("至少3张策略", "s3"),
            ("协同≥3", "syn3"),
            ("有伙伴在场或处于独立作答", "ally_or_exam"),
            ("无伙伴在场", "no_ally"),
            ("至少2种", "st2"),
            ("至少3种", "st3"),
            ("此前打过合作牌", "coop"),
            ("此前召入过伙伴", "summoned"),
            ("此前恢复过伙伴精力", "healed"),
            ("DDL≤3", "late"),
            ("固定考场", "exam"),
        ]:
            if key in t:
                p["bonus_cond"] = cond
                break
        if p["bonus_cond"] is None:
            p["bonus_cond"] = "always"
    m = re.search(r"完成(\d+)\+(\d+)n", t)
    if m:
        p["dmg"] = int(m.group(1))
        p["bonus"] = int(m.group(2))
        p["bonus_cond"] = "n"
    return p


PROFILE = {cid: parse(c) for cid, c in CARD.items()}

SPECIAL = {
    "R3-T201": "publish",
    "R3-P02-01": "open_paper",
    "R3-P02-11": "chapter", "R3-P02-12": "chapter", "R3-P02-13": "chapter",
    "R3-P02-14": "chapter", "R3-P02-15": "chapter", "R3-P02-16": "chapter",
    "R3-P02-20": "extra_chapter", "R3-P02-30": "withdraw_chapters",
    "R3-P02-06": "citation", "R3-P02-07": "progress", "R3-P02-08": "mod5",
    "R3-P02-09": "mod12", "R3-P02-21": "reset_name", "R3-P02-22": "amplify",
    "R3-P02-26": "cite_to_mod", "R3-P02-28": "publish_discount",
    "R3-P02-29": "discard2_mod", "R3-P02-39": "fetch_open", "R3-P02-04": "note",
    "R3-P02-27": "copy_chapter",
    "R3-P03-05": "spread", "R3-P03-07": "trigger_erosion", "R3-P03-09": "double_erosion",
    "R3-P03-18": "extra_trigger",
    "R3-P04-01": "summon_u01", "R3-P04-04": "summon_u02", "R3-P04-08": "summon_u03",
    "R3-P04-10": "summon_u01_group", "R3-P04-11": "summon_u02_short",
    "R3-P04-21": "summon_u01", "R3-P04-26": "summon_u02_short",
    "R3-P04-06": "extra_ally", "R3-P04-12": "heal_ally2", "R3-P04-15": "withdraw_ally",
    "R3-P04-16": "heal_ally1_draw", "R3-P04-18": "heal_all", "R3-P04-25": "spend_block",
    "R3-P04-29": "spend_draw", "R3-P04-30": "spend_all_dmg", "R3-P04-32": "spend_dmg",
    "R3-P04-40": "spend_all_aoe",
    "R3-P01-16": "recycle_strategy", "R3-P01-29": "recycle_work",
    "R3-P01-25": "discount",
}

ABILITIES = {
    "R3-C-06": "c06",
    "R3-P01-10": "p01_10", "R3-P01-18": "p01_18", "R3-P01-20": "p01_20", "R3-P01-28": "p01_28",
    "R3-P02-10": "p02_10", "R3-P02-19": "p02_19", "R3-P02-40": "p02_40",
    "R3-P03-04": "p03_04", "R3-P03-10": "p03_10", "R3-P03-19": "p03_19",
    "R3-P03-20": "p03_20", "R3-P03-30": "p03_30",
    "R3-P04-17": "p04_17", "R3-P04-20": "p04_20", "R3-P04-22": "p04_22",
}

SCENES = {"R3-C-08": ("block", 3), "R3-P02-36": ("draw", 1)}

STARTER = ["R3-C-01"] * 4 + ["R3-C-02"] * 4 + ["R3-C-03", "R3-C-04"]
SIGNATURE = {"P01": ["R3-P01-01", "R3-P01-02"], "P02": ["R3-P02-01", "R3-P02-11"],
             "P03": ["R3-P03-01", "R3-P03-21"], "P04": ["R3-P04-01", "R3-P04-02"]}

BUILDS = {
    "P01": {
        "连携速攻": ["R3-P01-05", "R3-P01-06", "R3-P01-08", "R3-P01-09", "R3-P01-21", "R3-P01-22",
                 "R3-P01-23", "R3-P01-25", "R3-C-01", "R3-C-03", "R3-C-10", "R3-C-12"],
        "复用引擎": ["R3-P01-11", "R3-P01-12", "R3-P01-13", "R3-P01-14", "R3-P01-15", "R3-P01-16",
                 "R3-P01-18", "R3-P01-19", "R3-P01-20", "R3-P01-26", "R3-C-02", "R3-C-03"],
        "集中爆发": ["R3-P01-21", "R3-P01-22", "R3-P01-23", "R3-P01-24", "R3-P01-25", "R3-P01-26",
                 "R3-P01-27", "R3-P01-28", "R3-P01-29", "R3-P01-30", "R3-C-06", "R3-C-01"],
    },
    "P02": {
        "发表一波": ["R3-P02-02", "R3-P02-03", "R3-P02-06", "R3-P02-07", "R3-P02-08", "R3-P02-09",
                 "R3-P02-10", "R3-P02-22", "R3-P02-25", "R3-P02-26", "R3-P02-28", "R3-C-03"],
        "章节持续": ["R3-P02-11", "R3-P02-12", "R3-P02-13", "R3-P02-14", "R3-P02-15", "R3-P02-16",
                 "R3-P02-17", "R3-P02-18", "R3-P02-19", "R3-P02-20", "R3-C-02", "R3-C-03"],
        "混合路线": ["R3-P02-02", "R3-P02-06", "R3-P02-07", "R3-P02-08", "R3-P02-11", "R3-P02-12",
                 "R3-P02-13", "R3-P02-26", "R3-P02-27", "R3-P02-28", "R3-C-09", "R3-C-03"],
    },
    "P03": {
        "侵蚀增殖": ["R3-P03-02", "R3-P03-03", "R3-P03-04", "R3-P03-05", "R3-P03-06", "R3-P03-07",
                 "R3-P03-08", "R3-P03-09", "R3-P03-10", "R3-P03-31", "R3-C-02", "R3-C-03"],
        "诱发连打": ["R3-P03-11", "R3-P03-12", "R3-P03-13", "R3-P03-14", "R3-P03-15", "R3-P03-16",
                 "R3-P03-17", "R3-P03-18", "R3-P03-19", "R3-P03-20", "R3-C-03", "R3-C-01"],
        "混合抑制": ["R3-P03-21", "R3-P03-22", "R3-P03-23", "R3-P03-24", "R3-P03-25", "R3-P03-26",
                 "R3-P03-27", "R3-P03-28", "R3-P03-29", "R3-P03-30", "R3-C-09", "R3-C-10"],
    },
    "P04": {
        "分工推进": ["R3-P04-03", "R3-P04-04", "R3-P04-05", "R3-P04-06", "R3-P04-07", "R3-P04-08",
                 "R3-P04-09", "R3-P04-10", "R3-P04-21", "R3-C-12", "R3-C-02", "R3-C-03"],
        "接力轮换": ["R3-P04-11", "R3-P04-12", "R3-P04-13", "R3-P04-14", "R3-P04-15", "R3-P04-16",
                 "R3-P04-17", "R3-P04-18", "R3-P04-19", "R3-P04-20", "R3-C-02", "R3-C-03"],
        "备考内化": ["R3-P04-22", "R3-P04-23", "R3-P04-24", "R3-P04-25", "R3-P04-26", "R3-P04-27",
                 "R3-P04-28", "R3-P04-29", "R3-P04-30", "R3-P04-21", "R3-C-09", "R3-C-10"],
    },
}

ENCOUNTERS = {
    "N01": dict(hp=[24], ddl=8, intents=[("p", 5), ("p", 7)], exam=False),
    "N02": dict(hp=[28], ddl=8, intents=[("b", 5), ("p", 8)], exam=False),
    "N03": dict(hp=[30], ddl=8, intents=[("p", 6), ("pb", 4)], exam=False),
    "N04": dict(hp=[32], ddl=8, intents=[("a", 1), ("p", 9)], exam=False),
    "Q01": dict(hp=[38], ddl=6, intents=[("p", 7), ("b", 6), ("p", 10)], exam=True),
    "B01": dict(hp=[20, 25, 25], ddl=10, intents=[("p", 7), ("b", 5), ("p", 9)], exam=True),
}


class Battle:
    def __init__(self, char, deck, enc, seed):
        self.rng = random.Random(seed)
        self.char = char
        self.enc = ENCOUNTERS[enc]
        self.exam = self.enc["exam"]
        self.hp_scale = HP_SCALE
        self.deck = list(deck)
        self.rng.shuffle(self.deck)
        self.drawpile = self.deck
        self.hand = []
        self.discard = []
        self.exhaust_pile = []
        self.hp = 72
        self.maxhp = 72
        self.energy = 3
        self.maxenergy = 3
        self.relax = 0
        self.turn = 1
        self.ddl = self.enc["ddl"]
        self.phase = 0
        self.scaled_hp = [max(1, round(h * HP_SCALE)) for h in self.enc["hp"]]
        self.task_hp = self.scaled_hp[0]
        self.barrier = 0
        self.st = {k: 0 for k in STATUS_NAMES}
        self.paper = {"open": False, "p": 0, "c": 0, "m": 0, "used": set()}
        self.publish = False
        self.chapters = []
        self.allies = []
        self.synergy = 0
        self.amp = 0
        self.ability = set()
        self.scene = []
        self.last_type = None
        self.last_strategy = None
        self.strategies_turn = 0
        self.strategy_uses = Counter()
        self.combo_count = 0
        self.passive_used_turn = False
        self.composite_used_turn = False
        self.coop_played_turn = False
        self.summoned_turn = False
        self.healed_turn = False
        self.played_new_name_turn = False
        self.induce_triggers = 0
        self.erosion_events = 0
        self.evidence_used_turn = False
        self.c06_used = False
        self.p01_10_used = 0
        self.p02_10_used = False
        self.p02_40_used = False
        self.p04_17_used = False
        self.p04_20_used = False
        self.combo_block_used = 0
        self.next_work_bonus = 0
        self.work_discount = 0
        self.publish_discount = False
        self.turns_taken = 0
        self.cards_played = 0
        self.cards_drawn = 0
        self.notes = []
        self.anxiety = 0
        self.status_applied_on_card = 0
        self.phase_changed_turn = False
        self.phase_turn = 0
        self.retrievals = 0
        self.heals_count = 0
        self.pending_publish_carry = 0

    # ---------- 基础操作 ----------
    def draw(self, n):
        for _ in range(n):
            if len(self.hand) >= 10:
                break
            if not self.drawpile:
                if not self.discard:
                    break
                self.drawpile = self.discard
                self.discard = []
                self.rng.shuffle(self.drawpile)
            self.hand.append(self.drawpile.pop())
            self.cards_drawn += 1

    def discard_random(self, n=1):
        for _ in range(n):
            if self.hand:
                self.discard.append(self.hand.pop(self.rng.randrange(len(self.hand))))

    def add_discard(self, cid):
        self.discard.append(cid)

    def deal(self, dmg, work=False):
        if dmg <= 0:
            return 0
        if work and self.st["易伤"] > 0:
            dmg = int(math.floor(dmg * 1.25))
        if self.barrier > 0:
            absorbed = min(self.barrier, dmg)
            self.barrier -= absorbed
            dmg -= absorbed
        self.task_hp -= dmg
        return dmg

    def deal_induce(self, dmg):
        """诱发伤害：第二轮起至少 1 点穿透屏障；第四轮起每次 +1。"""
        if dmg <= 0:
            return 0
        if PROPOSAL >= 4:
            dmg += 1
        if self.barrier > 0 and (PROPOSAL >= 2 or AXIS in ("induce", "combo")):
            pierced = min(2 if (AXIS in ("induce", "combo") or PROPOSAL >= 3) else 1, self.barrier)
            self.barrier -= pierced
            rest = max(0, dmg - pierced)
            self.task_hp -= pierced
            return pierced + self.deal(rest)
        return self.deal(dmg)

    def apply_status(self, name, n):
        if n <= 0:
            return 0
        before = self.st[name]
        other = any(self.st[k] > 0 for k in STATUS_NAMES if k != name)
        cap = STATUS_CAP[name]
        new = min(cap, before + n)
        gained = new - before
        self.st[name] = new
        if name == "侵蚀" and gained > 0:
            self.erosion_events += 1
            if "p03_19" in self.ability and self.erosion_events == 3:
                self.deal(4)
        if (self.char == "P03" and not self.composite_used_turn and before == 0 and gained > 0
                and other and self.st[name] < cap):
            self.st[name] += 1
            self.composite_used_turn = True
            if self.composite_used_turn and "p03_30" in self.ability:
                pass
        return gained

    def status_count(self):
        return sum(1 for k in STATUS_NAMES if self.st[k] > 0)

    def incoming(self):
        if self.phase >= len(self.enc["hp"]):
            return 0
        kind, val = self.enc["intents"][self.phase_turn % len(self.enc["intents"])]
        if kind in ("p", "pb"):
            return val
        return 0

    # ---------- 回合 ----------
    def start_turn(self):
        self.phase_changed_turn = False
        self.energy = self.maxenergy - self.anxiety
        self.anxiety = 0
        self.relax = 0
        self.played_new_name_turn = False
        self.coop_played_turn = False
        self.summoned_turn = False
        self.healed_turn = False
        self.c06_used = False
        self.p01_10_used = 0
        self.p02_10_used = False
        self.p02_40_used = False
        self.p04_17_used = False
        self.p04_20_used = False
        self.combo_block_used = 0
        self.composite_used_turn = False
        self.passive_used_turn = False
        self.induce_triggers = 0
        self.erosion_events = 0
        self.evidence_used_turn = False
        self.strategies_turn = 0
        self.combo_count = 0
        self.last_type = None
        self.last_strategy = None
        self.next_work_bonus = 0
        self.work_discount = 0
        self.publish_discount = False
        # 场景
        for sc in list(self.scene):
            sc[1] -= 1
            if sc[0] == "block":
                self.relax += sc[2]
            else:
                self.draw(sc[2])
            if sc[1] <= 0:
                self.scene.remove(sc)
        # 能力：追踪记录
        if "p03_04" in self.ability:
            self.apply_status("侵蚀", 1)
        if "p04_22" in self.ability and not self.allies:
            self.synergy = min(6, self.synergy + 1)
        # 章节自动
        ran = set()
        for cid in list(self.chapters):
            other = [c for c in self.chapters if c != cid and c in ran]
            if cid == "R3-P02-11":
                self.draw(1)
            elif cid == "R3-P02-12":
                self.relax += 3 + (2 if len(self.chapters) >= 2 else 0)
            elif cid == "R3-P02-13":
                self.deal(5 if PROPOSAL else 4)
            elif cid == "R3-P02-14":
                self.relax += 2
                if other:
                    self.draw(1)
            elif cid == "R3-P02-15":
                self.amp = min(5, self.amp + 1)
            elif cid == "R3-P02-16":
                self.deal((4 if PROPOSAL else 3) + 2 * min(2, len(other)))
            ran.add(cid)
        if "p02_19" in self.ability and len(self.chapters) >= 2:
            self.relax += 4
        if "p03_30" in self.ability and self.status_count() >= 3:
            self.relax += 5
            self.deal(5)
        self.maybe_advance()
        self.draw(5)

    def end_turn(self):
        # 同伴合作
        if self.allies:
            for a in list(self.allies):
                if a["hp"] <= 0:
                    self.allies.remove(a)
                    continue
                if a["name"] == "U02":
                    self.relax += 2
                self.deal(a["coop"])
                a["hp"] -= 1
                if a["hp"] <= 0:
                    self.allies.remove(a)
        # 侵蚀自然结算
        times = 2 if "p03_10" in self.ability else 1
        for i in range(times):
            if self.task_hp <= 0:
                break
            if self.st["侵蚀"] > 0:
                dmg = self.st["侵蚀"]
                if PROPOSAL >= 3:
                    dmg = int(dmg * 0.75)
                if AXIS in ("erosion", "combo") and i > 0:
                    dmg = dmg // 2
                self.deal(dmg)
                self.st["侵蚀"] -= (2 if PROPOSAL >= 2 else 1)
        # 压力
        kind, val = self.enc["intents"][(self.turn - 1) % len(self.enc["intents"])]
        if kind == "a":
            self.anxiety += val
        if kind in ("p", "pb"):
            dmg = max(0, val - self.st["乏力"])
            if self.st["虚弱"] > 0:
                dmg = int(math.floor(dmg * 0.75))
            guarded = next((a for a in self.allies if a["name"] == "U03"), None)
            if guarded:
                guarded["hp"] -= dmg
                if guarded["hp"] <= 0:
                    self.allies.remove(guarded)
            else:
                absorbed = min(self.relax, dmg)
                self.relax -= absorbed
                self.hp -= dmg - absorbed
        if kind == "b":
            self.barrier += (val // 2 if self.st["脆化"] > 0 else val)
        if kind == "pb":
            self.discard.append("X01")  # 分心消息：占手牌的负担近似
        # 计时状态窗口
        for k in ("易伤", "虚弱", "脆化"):
            if self.st[k] > 0:
                self.st[k] -= 1
        # 诱发清空
        self.st["诱发"] = 0
        # 阶段推进
        self.maybe_advance()
        if self.task_hp <= 0 and self.phase + 1 >= len(self.scaled_hp):
            return "win"
        # 轮末弃置手牌（解题发表自带保留；其余保留牌简化为弃置）
        kept = [c for c in self.hand if c == "R3-T201"]
        self.discard.extend(c for c in self.hand if c != "R3-T201")
        self.hand = kept
        self.ddl -= 1
        self.turn += 1
        self.phase_turn += 1
        self.turns_taken += 1
        if self.ddl <= 0 and self.task_hp > 0:
            return "lose"
        if self.hp <= 0:
            return "lose"
        return None

    def maybe_advance(self):
        while self.task_hp <= 0 and self.phase + 1 < len(self.scaled_hp):
            self.phase += 1
            self.task_hp = self.scaled_hp[self.phase]
            self.barrier = 0
            self.st = {k: 0 for k in STATUS_NAMES}
            self.phase_changed_turn = True
            self.phase_turn = 0

    # ---------- 出牌 ----------
    def can_play(self, cid):
        if cid == "X01":
            return False
        p = PROFILE[cid]
        if p["cost"] > self.energy:
            return False
        sp = SPECIAL.get(cid)
        if cid == "R3-T201":
            return self.paper["open"]
        if sp in ("chapter", "extra_chapter") and not self.paper["open"]:
            return False
        if sp == "open_paper" and self.paper["open"]:
            return False
        if cid == "R3-P02-39":
            return (not self.paper["open"]) and ("R3-P02-01" in self.discard)
        if sp in ("citation", "progress", "mod5", "mod12", "reset_name", "amplify",
                  "cite_to_mod", "publish_discount", "discard2_mod", "copy_chapter",
                  "withdraw_chapters") and not self.paper["open"]:
            return False
        if cid in ("R3-P03-05", "R3-P03-06", "R3-P03-07", "R3-P03-09") and self.st["侵蚀"] <= 0:
            return False
        if cid == "R3-P03-28" and not any(self.st[k] > 0 for k in ("易伤", "虚弱", "脆化")):
            return False
        if cid == "R3-P02-30" and not self.chapters:
            return False
        if cid == "R3-P02-20" and not self.chapters:
            return False
        if cid == "R3-P02-18" and not any(c in CARD and CARD[c]["type"] == "策略" and "章节" in CARD[c]["tags"] for c in self.drawpile):
            return False
        if sp and sp.startswith("summon"):
            if self.exam:
                return True  # 考试面替代
            if len(self.allies) >= 3 and cid not in ("R3-P04-11", "R3-P04-26"):
                return False
        if sp in ("extra_ally",) and not self.allies:
            return False
        if sp in ("heal_ally2", "heal_ally1_draw", "withdraw_ally", "heal_all") and not self.allies:
            return False
        if sp in ("spend_block",) and self.synergy < 1:
            return False
        if sp in ("spend_draw",) and self.synergy < 1:
            return False
        if sp in ("spend_dmg",) and self.synergy < 1:
            return False
        if sp in ("extra_ally",) and self.synergy < 1:
            return False
        return True

    def play(self, cid):
        c = CARD[cid]
        p = PROFILE[cid]
        cost = max(0, p["cost"] - (self.work_discount if p["type"] == "工作" and p["cost"] >= 2 else 0))
        if cid == "R3-T201" and self.publish_discount:
            cost = max(0, cost - 1)
        self.energy -= cost
        self.cards_played += 1
        pre_induce = self.st["诱发"]
        combo = self.last_type == "策略" and p["type"] == "工作"
        strategies_before = self.strategies_turn
        paper_snapshot = cid not in ("R3-P02-01", "R3-T201")
        # 目标是否为“新牌名”快照
        name_key = cid
        new_name = name_key not in self.paper["used"]
        # ---- 正文 ----
        dmg = p["dmg"]
        block = p["block"]
        draw = p["draw"]
        heal = p["heal"]
        if p["bonus"] and cid not in MANUAL_BONUS and self.bonus_active(p["bonus_cond"], combo, strategies_before):
            dmg += p["bonus"]
        if p["type"] == "工作":
            dmg += self.next_work_bonus
            self.next_work_bonus = 0
            if combo:
                self.combo_count += 1
        if p["type"] == "策略":
            self.strategies_turn += 1
            self.last_strategy = cid
        if p["type"] == "合作" and not self.coop_played_turn:
            self.coop_played_turn = True
            if self.char == "P04":
                self.synergy = min(6, self.synergy + 1)
                self.relax += 2
                if PROPOSAL >= 3 and "p04_20" in self.ability:
                    self.next_work_bonus += 3
        if p["type"] == "工作" and p["cost"] >= 2 and "p01_28" in self.ability:
            block += 6
        if self.combo_count == 1 and "c06" in self.ability:
            dmg += 2
        if combo and "p01_10" in self.ability and self.p01_10_used < 2:
            self.relax += 3
            self.p01_10_used += 1
        if self.amp > 0:
            if draw > 0:
                draw += self.amp
                self.amp = 0
            elif block > 0:
                block += self.amp
                self.amp = 0
            elif heal > 0:
                heal += self.amp
                self.amp = 0
        barrier_removal = p["barrier"]
        if PROPOSAL:
            if cid == "R3-P01-23":
                barrier_removal = max(barrier_removal, 4)
            elif cid == "R3-P01-27":
                barrier_removal = max(barrier_removal, 3)
            elif cid == "R3-P03-12":
                barrier_removal = max(barrier_removal, 2 if PROPOSAL >= 2 else 1)
            elif (PROPOSAL >= 2 or AXIS in ("finisher", "combo")) and cid == "R3-P01-19":
                barrier_removal = max(barrier_removal, 3)
            elif (PROPOSAL >= 2 or AXIS in ("finisher", "combo")) and cid == "R3-P04-19":
                barrier_removal = max(barrier_removal, 2)
        self.barrier = max(0, self.barrier - barrier_removal)
        sp = SPECIAL.get(cid)
        if cid in ABILITIES:
            self.ability.add(ABILITIES[cid])
        if cid in SCENES:
            kind2, v2 = SCENES[cid]
            self.scene.append([kind2, 2, v2])
        if cid == "R3-P01-21":
            self.next_work_bonus += 4
        elif cid == "R3-P01-22":
            self.next_work_bonus += 3
        elif cid == "R3-P01-24" and strategies_before >= 2:
            self.next_work_bonus += 3
        elif cid == "R3-P01-39":
            self.next_work_bonus += 2
        elif cid == "R3-P01-25":
            self.work_discount = 1
        elif cid == "R3-P01-26" and strategies_before >= 2:
            draw += 2
        if "主动弃" in c["base"]:
            self.discard_random(1)
        # 考试面：合作/伙伴牌转换
        if self.exam and self.char == "P04" and (p["type"] == "合作" or sp):
            if p["type"] == "合作" or (sp and sp.startswith("summon")):
                dmg = max(dmg, 6)
                block = max(block, 3)
                sp = None
                if not self.coop_played_turn:
                    self.coop_played_turn = True
                    self.synergy = min(6, self.synergy + 1)
                    self.relax += 2
        # 特殊牌
        if sp == "publish":
            C = min(100, max(0, self.paper["p"] * 7 + self.paper["c"] * 6 + self.paper["m"]))
            dmg = C + 10 + (20 if C >= 100 else 0)
            if PROPOSAL:
                self.pending_publish_carry = C // 2
            self.paper["p"] = 0
            self.paper["c"] = 0
            self.paper["m"] = 0
            self.paper["used"] = set()
            self.paper["open"] = False
            for ch in self.chapters:
                self.discard.append(ch)
            self.chapters = []
            self.amp = 0
        elif sp == "open_paper":
            self.paper = {"open": True, "p": 0, "c": 0, "m": 0, "used": set()}
            self.publish = True
            if "R3-T201" in self.discard:
                self.discard.remove("R3-T201")
                self.add_hand("R3-T201")
            elif "R3-T201" not in self.hand:
                self.add_hand("R3-T201")
        elif sp == "chapter":
            if cid not in self.chapters and len(self.chapters) < 3:
                self.chapters.append(cid)
        elif sp == "extra_chapter":
            if self.chapters:
                c2 = self.chapters[0]
                if c2 == "R3-P02-13":
                    dmg += 4
                elif c2 == "R3-P02-16":
                    dmg += 5
                elif c2 == "R3-P02-12":
                    block += 3
                else:
                    draw += 1
        elif sp == "withdraw_chapters":
            n = min(2, len(self.chapters))
            self.paper["m"] += 4 * n
            self.chapters = self.chapters[n:]
        elif sp == "citation":
            self.gain_citation(1, free=True)
        elif sp == "progress":
            self.gain_progress(1)
        elif sp == "mod5":
            self.paper["m"] += 5
        elif sp == "mod12":
            self.paper["m"] += 12
        elif sp == "reset_name":
            if self.paper["used"]:
                self.paper["used"].pop()
                self.paper["m"] -= 1
        elif sp == "amplify":
            self.amp = min(5, self.amp + 1)
        elif sp == "cite_to_mod":
            if self.paper["c"] > 0:
                self.paper["c"] -= 1
                self.paper["m"] += 3
        elif sp == "publish_discount":
            self.publish_discount = True
        elif sp == "discard2_mod":
            self.discard_random(2)
            draw += 2
            self.paper["m"] += 3
        elif sp == "fetch_open":
            if "R3-P02-01" in self.discard:
                self.discard.remove("R3-P02-01")
                self.hand.append("R3-P02-01")
        elif sp == "note":
            self.add_hand("R3-T202")
        elif sp == "copy_chapter":
            draw += 1
        elif sp == "spread":
            s = min(self.st["侵蚀"], 3)
            self.apply_status("侵蚀", s)
        elif sp == "trigger_erosion":
            if self.st["侵蚀"] > 0:
                dmg += self.st["侵蚀"]
        elif sp == "double_erosion":
            dmg += self.st["侵蚀"]
        elif sp and sp.startswith("summon"):
            self.summon(sp)
        elif sp == "extra_ally":
            self.synergy -= 1
            if self.allies:
                a = self.allies[0]
                dmg += a["coop"]
                a["hp"] -= 1
                self.allies = [a2 for a2 in self.allies if a2["hp"] > 0]
        elif sp == "heal_ally2":
            if self.allies:
                a = self.allies[0]
                a["hp"] = min(a["maxhp"], a["hp"] + 2)
                self.heals_count += 1
        elif sp == "heal_ally1_draw":
            if self.allies:
                a = self.allies[0]
                a["hp"] = min(a["maxhp"], a["hp"] + 1)
            draw += 1
            self.healed_turn = True
            self.heals_count += 1
        elif sp == "withdraw_ally":
            if self.allies:
                self.allies.pop(0)
            self.synergy = min(6, self.synergy + 1)
        elif sp == "heal_all":
            self.synergy -= 1
            for a in self.allies:
                a["hp"] = min(a["maxhp"], a["hp"] + 1)
            self.relax += 4
            self.healed_turn = True
            self.heals_count += 1
        elif sp == "spend_block":
            x = min(2, self.synergy)
            self.synergy -= x
            block += 5 + 3 * x
        elif sp == "spend_draw":
            self.synergy -= 1
            draw += 2
            if not self.allies:
                self.relax += 4
        elif sp == "spend_dmg":
            if self.synergy >= 1:
                self.synergy -= 1
                dmg += 4
        elif sp == "spend_all_dmg":
            x = self.synergy
            self.synergy = 0
            dmg += 3 * x
        elif sp == "spend_all_aoe":
            x = self.synergy
            self.synergy = 0
            dmg += 2 * x
        # 伙伴牌在普通面：召入后无直接伤害；工作牌加值
        if cid == "R3-P04-03" and self.allies:
            dmg += 2 * min(3, len(self.allies))
        if cid == "R3-P04-09":
            dmg += 3 * len(self.allies)
            if self.synergy >= 2:
                self.synergy -= 2
                dmg += 8
        if cid == "R3-P04-13" and (self.allies or self.exam):
            dmg += 3
        if cid == "R3-P04-19":
            if PROPOSAL >= 3:
                dmg = (12 + 3 * min(8, self.heals_count)) if PROPOSAL >= 4 else (10 + 3 * min(6, self.heals_count))
            elif AXIS in ("finisher", "combo"):
                dmg = 8 + 3 * min(8, self.heals_count)
            elif PROPOSAL >= 2:
                dmg = 8 + 3 * min(4, self.heals_count)
            elif PROPOSAL:
                dmg = 8 + 2 * min(8, self.heals_count)
            if self.healed_turn or self.exam:
                block += 5
        if cid == "R3-P04-23" and not self.allies:
            self.synergy = min(6, self.synergy + 1)
        if cid == "R3-P04-24" and self.synergy >= 3:
            draw += 1
        if cid == "R3-P04-27" and self.coop_played_turn:
            dmg += 4
        if cid == "R3-P04-28":
            dmg = (6 if PROPOSAL >= 4 else (8 if PROPOSAL >= 3 else (8 if AXIS in ("inner", "combo") else (10 if PROPOSAL >= 2 else (12 if PROPOSAL else 14)))))
            if self.synergy >= 3:
                dmg += (3 if (PROPOSAL >= 3 or AXIS in ("inner", "combo")) else (4 if PROPOSAL >= 2 else (5 if PROPOSAL else 6)))
        if cid == "R3-P02-35" and self.exam:
            dmg += 3
        if cid == "R3-P01-32" and combo:
            self.relax += 2
        if cid == "R3-P01-33" and self.passive_used_turn:
            self.relax += 2
        if cid == "R3-P01-34" and self.strategies_turn == 0:
            self.relax += 3
        if cid == "R3-P03-35" and self.status_count() == 0:
            dmg += 3
        if cid == "R3-P03-36" and self.status_count() >= 2:
            draw += 1
        if cid == "R3-P03-25":
            dmg = ((7 + 3 * min(4, self.status_count())) if PROPOSAL >= 4
                   else (5 + 2 * min(4, self.status_count())))
        if cid == "R3-P03-29":
            dmg = ((6 + 3 * min(4, self.status_count())) if PROPOSAL >= 4
                   else (4 + 2 * min(4, self.status_count())))
        if cid == "R3-P02-03" and new_name and self.paper["open"]:
            draw += 1
        if cid == "R3-P02-24" and (not new_name) and self.paper["open"]:
            draw += 1
        if cid == "R3-P01-14" and self.passive_used_turn:
            draw += 1
        if cid == "R3-P01-19":
            if PROPOSAL >= 3:
                dmg = (12 + 3 * min(8, self.retrievals)) if PROPOSAL >= 4 else (10 + 3 * min(6, self.retrievals))
            elif AXIS in ("finisher", "combo"):
                dmg = 8 + 3 * min(8, self.retrievals)
            elif PROPOSAL >= 2:
                dmg = 8 + 3 * min(5, self.retrievals)
            elif PROPOSAL:
                dmg = 8 + 2 * min(10, self.retrievals)
            elif combo and self.strategy_uses[self.last_strategy or ""] >= 2:
                dmg += 5
        if cid == "R3-P01-27" and strategies_before >= 2:
            dmg += 8
        if cid == "R3-P01-30" and strategies_before >= 3:
            dmg += 6
        if cid == "R3-P01-40" and self.passive_used_turn and strategies_before >= 3:
            dmg += 10
        if cid == "R3-P01-09":
            dmg = 10 + 3 * min(3, self.combo_count)
        # 施加状态
        for name, n in p["st"]:
            self.apply_status(name, n)
        # 本体
        self.deal(dmg, work=(p["type"] == "工作"))
        if self.pending_publish_carry and self.task_hp <= 0 and self.phase + 1 < len(self.scaled_hp):
            carry = self.pending_publish_carry
            self.maybe_advance()
            if self.phase_changed_turn:
                self.deal(carry)
        self.pending_publish_carry = 0
        self.maybe_advance()
        self.relax += block
        if heal:
            self.hp = min(self.maxhp, self.hp + heal)
        self.draw(draw)
        # 论文记账
        if paper_snapshot and self.paper["open"]:
            self.paper_account(cid)
        # 被动：林序取回
        if self.char == "P01" and combo and not self.passive_used_turn:
            if self.last_strategy and self.last_strategy in self.discard and len(self.hand) < 10:
                self.discard.remove(self.last_strategy)
                self.hand.append(self.last_strategy)
                self.passive_used_turn = True
                self.retrievals += 1
                if PROPOSAL >= 3 and "p01_18" in self.ability:
                    self.next_work_bonus += 3
        # 诱发结算
        if pre_induce > 0 and self.st["诱发"] > 0 and self.induce_triggers < 4:
            self.deal_induce(pre_induce)
            self.induce_triggers += 1
            if "p03_20" in self.ability and self.induce_triggers == 1:
                self.deal(3)
        if sp == "extra_trigger" and self.st["诱发"] > 0 and self.induce_triggers < 4:
            self.deal_induce(self.st["诱发"])
            self.induce_triggers += 1
        # 归区
        if p["exhaust"]:
            self.exhaust_pile.append(cid)
        elif sp == "chapter" and cid in self.chapters:
            pass
        else:
            self.discard.append(cid)
        self.last_type = p["type"]
        if p["type"] == "策略":
            self.strategy_uses[cid] += 1
        if sp == "publish":
            self.publish = False
        return True

    def bonus_active(self, cond, combo, strategies_before):
        if cond is None:
            return False
        if cond == "always":
            return True
        if cond == "combo":
            return combo
        if cond == "s2":
            return strategies_before >= 2
        if cond == "s3":
            return strategies_before >= 3
        if cond == "syn3":
            return self.synergy >= 3
        if cond == "ally_or_exam":
            return bool(self.allies) or self.exam
        if cond == "no_ally":
            return not self.allies
        if cond == "st2":
            return self.status_count() >= 2
        if cond == "st3":
            return self.status_count() >= 3
        if cond == "coop":
            return self.coop_played_turn
        if cond == "summoned":
            return self.summoned_turn
        if cond == "healed":
            return self.healed_turn
        if cond == "late":
            return self.ddl <= 3
        if cond == "exam":
            return self.exam
        return True

    def add_hand(self, cid):
        if len(self.hand) < 10:
            self.hand.append(cid)
        else:
            self.discard.append(cid)

    def summon(self, sp):
        if self.exam:
            return
        table = {"summon_u01": ("U01", 3, 3 if PROPOSAL else 2, False), "summon_u02": ("U02", 4, 1, False),
                 "summon_u03": ("U03", 5, 3, True), "summon_u01_group": ("U01", 3, 2, False),
                 "summon_u02_short": ("U02", 2, 1, False)}
        if sp not in table:
            return
        name, hp, coop, guard = table[sp]
        if len(self.allies) >= 3:
            self.allies.pop(0)
        self.allies.append({"name": name, "hp": hp, "maxhp": hp, "coop": coop, "guard": guard})
        self.summoned_turn = True

    def gain_progress(self, n):
        self.paper["p"] = min(10, self.paper["p"] + n)
        if "p02_10" in self.ability and not self.p02_10_used:
            self.draw(1)
            self.relax += 2
            self.p02_10_used = True

    def gain_citation(self, n, free=False):
        target = self.paper["c"] + n
        extra = {3: 1, 4: 2, 5: 3}
        if target > 5:
            return
        cost = 0 if free else sum(extra.get(i, 0) for i in range(self.paper["c"] + 1, target + 1))
        if self.energy >= cost:
            self.energy -= cost
            self.paper["c"] = target
        else:
            self.draw(1)

    def paper_account(self, cid):
        if cid in self.paper["used"]:
            self.gain_citation(1)
        else:
            self.paper["used"].add(cid)
            self.gain_progress(1)
            if "p02_40" in self.ability and not self.p02_40_used:
                self.relax += 3
                self.p02_40_used = True

    # ---------- 决策 ----------
    def score(self, cid):
        if cid == "X01":
            return 0
        p = PROFILE[cid]
        sp = SPECIAL.get(cid)
        t = CARD[cid]["type"]
        need = max(0, self.incoming() - self.relax)
        # 斩杀优先
        dmg = p["dmg"] + self.next_work_bonus
        if p["bonus"] and self.bonus_active(p["bonus_cond"], self.last_type == "策略", self.strategies_turn):
            dmg += p["bonus"]
        if cid == "R3-P01-09":
            dmg = 10 + 3 * min(3, self.combo_count)
        if cid == "R3-P03-25":
            dmg = ((7 + 3 * min(4, self.status_count())) if PROPOSAL >= 4
                   else (5 + 2 * min(4, self.status_count())))
        if cid == "R3-P03-29":
            dmg = ((6 + 3 * min(4, self.status_count())) if PROPOSAL >= 4
                   else (4 + 2 * min(4, self.status_count())))
        if cid == "R3-P04-03":
            dmg += 2 * min(3, len(self.allies))
        if cid == "R3-P04-09":
            dmg += 3 * len(self.allies) + (8 if self.synergy >= 2 else 0)
        if cid == "R3-P04-13" and (self.allies or self.exam):
            dmg += 3
        if cid == "R3-P04-27" and self.coop_played_turn:
            dmg += 4
        if cid == "R3-P04-28":
            dmg = (6 if PROPOSAL >= 4 else (8 if PROPOSAL >= 3 else (8 if AXIS in ("inner", "combo") else (10 if PROPOSAL >= 2 else (12 if PROPOSAL else 14)))))
            if self.synergy >= 3:
                dmg += (3 if (PROPOSAL >= 3 or AXIS in ("inner", "combo")) else (4 if PROPOSAL >= 2 else (5 if PROPOSAL else 6)))
        if cid == "R3-P04-32" and self.synergy >= 1:
            dmg += 4
        if cid == "R3-P03-35" and self.status_count() == 0:
            dmg += 3
        if cid == "R3-P02-35" and self.exam:
            dmg += 3
        if cid == "R3-P01-19":
            dmg = ((12 + 3 * min(8, self.retrievals)) if PROPOSAL >= 4 else (10 + 3 * min(6, self.retrievals))) if PROPOSAL >= 3 else ((8 + 3 * min(8, self.retrievals)) if AXIS in ("finisher", "combo") else ((8 + 3 * min(5, self.retrievals)) if PROPOSAL >= 2 else ((8 + 2 * min(10, self.retrievals)) if PROPOSAL else 8)))
        if cid == "R3-P04-19":
            dmg = ((12 + 3 * min(8, self.heals_count)) if PROPOSAL >= 4 else (10 + 3 * min(6, self.heals_count))) if PROPOSAL >= 3 else ((8 + 3 * min(8, self.heals_count)) if AXIS in ("finisher", "combo") else ((8 + 3 * min(4, self.heals_count)) if PROPOSAL >= 2 else ((8 + 2 * min(8, self.heals_count)) if PROPOSAL else 8)))
        if cid == "R3-P01-27" and self.strategies_turn >= 2:
            dmg += 8
        if cid == "R3-P01-30" and self.strategies_turn >= 3:
            dmg += 6
        if cid == "R3-P01-40" and self.passive_used_turn and self.strategies_turn >= 3:
            dmg += 10
        if cid == "R3-P04-30":
            dmg = ((6 + 2 * self.synergy) if PROPOSAL >= 4 else ((8 + 2 * self.synergy) if (PROPOSAL >= 2 or AXIS in ("inner", "combo")) else ((10 if PROPOSAL else 12) + 3 * self.synergy)))
        if cid == "R3-P04-40":
            dmg += 2 * self.synergy
        if cid == "R3-P03-29":
            dmg = 4 + 2 * min(4, self.status_count())
        if t == "工作" and self.last_type == "策略":
            dmg += 2
        lethal = dmg >= self.task_hp + self.barrier
        # 特殊
        if cid == "R3-T201":
            C = min(100, max(0, self.paper["p"] * 7 + self.paper["c"] * 6 + self.paper["m"]))
            if not self.paper["open"]:
                return 0
            return 1200 if (C + 10 >= self.task_hp + self.barrier or C >= 60) else 30
        if sp == "open_paper":
            return 1000 if not self.paper["open"] else 0
        if sp == "chapter":
            if cid in self.chapters:
                return 0
            return 360 if len(self.chapters) < 3 else 50
        if sp and sp.startswith("summon"):
            if self.exam:
                return 55
            return 340 if len(self.allies) < 3 else 0
        if sp == "extra_chapter":
            return 100 if self.chapters else 0
        if sp in ("citation", "progress", "mod5", "mod12", "amplify", "cite_to_mod"):
            return 130 + p["block"] + (60 if self.paper["p"] >= 7 else 0)
        if sp in ("reset_name", "discard2_mod", "publish_discount", "withdraw_chapters", "copy_chapter"):
            return 70
        if sp == "fetch_open":
            return 420
        if sp == "note":
            return 80
        if sp == "spread":
            return 65 + self.st["侵蚀"]
        if sp in ("trigger_erosion", "double_erosion"):
            return 55 + self.st["侵蚀"] * 1.5
        if sp in ("extra_ally", "spend_dmg", "spend_all_dmg", "spend_all_aoe"):
            return 70 + dmg
        if sp in ("heal_ally2", "heal_all", "heal_ally1_draw", "withdraw_ally"):
            return 55 if self.allies else 0
        if sp in ("spend_block", "spend_draw"):
            return 65
        if sp == "recycle_strategy" or sp == "recycle_work":
            return 35
        # 类型
        if t == "工作":
            s = dmg * 1.6 + (300 if lethal else 0)
        elif t == "合作":
            s = 30 + dmg
        elif t == "策略":
            s = p["block"] * 0.35 + dmg * 1.2
        elif t == "能力":
            s = 260 if self.turn <= 4 else 45
        elif t == "场景":
            s = 90 if not self.scene else 0
        else:
            s = 0
        # 抽牌价值（手牌越多越低，抽牌堆不足时也降低）
        if p["draw"]:
            mult = 2.4 if len(self.hand) < 8 else 0.6
            if not self.drawpile and not self.discard:
                mult = 0
            s += p["draw"] * mult
        # 防御价值
        if p["block"]:
            if need > 0 and self.hp < 55:
                s += min(need, p["block"]) * 1.0
            elif need > 0:
                s += min(need, p["block"]) * 0.35
            else:
                s += p["block"] * 0.08
        if p["heal"]:
            s += p["heal"] * (1.5 if self.hp < 50 else 0.3)
        # 状态价值
        for name, n in p["st"]:
            if name == "侵蚀":
                s += 8 + n * 3
            elif name == "诱发":
                s += 14
            elif name in ("易伤", "虚弱"):
                s += 5 + n * 2
            elif name == "乏力":
                s += 4 + n * 2
            else:
                s += 4
        if self.char == "P03":
            for name, n in p["st"]:
                if name == "侵蚀":
                    s += 6
                if name == "诱发":
                    s += 8
        if self.char == "P02" and self.paper["open"]:
            s += 8
        if self.char == "P04" and t == "合作":
            s += 20
        if p["cost"] == 0:
            s += 2
        if p["exhaust"]:
            s -= 1
        return s

    def playable_hand(self):
        return [(cid, self.score(cid)) for cid in self.hand if self.can_play(cid)]

    def run(self):
        while True:
            self.start_turn()
            if self.task_hp <= 0:
                return "win"
            for _ in range(40):
                opts = [(c, self.score(c)) for c in self.hand if self.can_play(c)]
                opts = [(c, s) for c, s in opts if s > 5]
                if not opts:
                    break
                cid, _ = max(opts, key=lambda x: x[1])
                self.hand.remove(cid)
                self.play(cid)
                if self.task_hp <= 0 and self.phase + 1 >= len(self.scaled_hp):
                    break
            if self.task_hp <= 0 and self.phase + 1 >= len(self.scaled_hp):
                return "win"
            res = self.end_turn()
            if res:
                return res


def build_deck(char, build_name, developed=True):
    deck = list(STARTER) + list(SIGNATURE[char])
    if developed:
        deck += BUILDS[char][build_name]
    return deck


def simulate(char, build_name, encounter, developed=True, n=3000):
    wins = 0
    turns = []
    hp_left = []
    for seed in range(n):
        b = Battle(char, build_deck(char, build_name, developed), encounter, seed)
        res = b.run()
        if res == "win":
            wins += 1
            turns.append(b.turn)
            hp_left.append(b.hp)
    return {
        "char": char, "build": build_name, "encounter": encounter, "developed": developed,
        "n": n, "win": wins / n,
        "avg_turn": statistics.mean(turns) if turns else None,
        "avg_hp": statistics.mean(hp_left) if hp_left else None,
    }


def main():
    rows = []
    for char in ("P01", "P02", "P03", "P04"):
        for build in BUILDS[char]:
            for enc in ENCOUNTERS:
                for developed in (False, True):
                    rows.append(simulate(char, build, enc, developed, n=1200))
    out = {
        "assumptions": {
            "hp_scale": HP_SCALE,
            "trials": 1200,
            "cards": len(CARD),
            "decks": 12,
            "encounters": list(ENCOUNTERS),
            "ai": "greedy score, no cross-turn planning",
            "upgrades": False,
            "multi_target": False,
            "note": "abstract design-stage prediction; not a game implementation or acceptance evidence",
        },
        "rows": rows,
    }
    with open(os.path.join(HERE, "results.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    # 控制台摘要
    print("char build enc dev win avgTurn avgHP")
    for r in rows:
        if r["developed"]:
            print(f"{r['char']} {r['build']} {r['encounter']} {int(r['developed'])} "
                  f"{r['win']*100:5.1f}% {r['avg_turn'] or 0:5.2f} {r['avg_hp'] or 0:5.1f}")


if __name__ == "__main__":
    main()
