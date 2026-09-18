# -*- coding: utf-8 -*-
"""
把开发文档里的「事实性声明」反向核回源码，防止文档失真。

当前校验：
  1. 卡牌表（§6.2）与 src/core/card_db.gd 一致
  2. 敌人描述与 src/core/enemy_db.gd 一致
  3. 文件清单（§6.1）中列出的路径真实存在
  4. 文档里标注的行数与实际行数一致
运行： python tools/verify_doc.py
"""
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "PVE卡牌Demo_开发文档.md")

TYPE_MAP = {
    "ATTACK": "攻击", "DEFENSE": "防御", "SKILL": "技能",
    "SCENE": "场景", "MINION": "随从",
}
TARGET_MAP = {
    "SINGLE_ENEMY": "单个敌人", "SELF": "自身", "NONE": "无",
    "SCENE_SLOT": "场景槽", "MINION_SLOT": "空随从槽",
    "OTHER_HAND": "另一张手牌", "READY_MINION": "已就绪仆从",
}

problems = []
checks = 0


def ok(msg):
    global checks
    checks += 1
    print("  [OK]   " + msg)


def bad(msg):
    global checks
    checks += 1
    problems.append(msg)
    print("  [FAIL] " + msg)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


# ── 1. 从 card_db.gd 提取卡牌 ─────────────────────────────
CARD_RE = re.compile(
    r'"name": "(?P<name>[^"]+)",\s*'
    r'"type": T\.CardType\.(?P<type>\w+),\s*'
    r'"cost": (?P<cost>\d+),\s*'
    r'"points": (?P<points>\d+),\s*'
    r'(?:"temp": true,\s*)?'
    r'"target": T\.TargetType\.(?P<target>\w+),\s*'
    r'"desc": "(?P<desc>[^"]*)",\s*'
    r'"count": (?P<count>\d+),'
)

cards_src = read(os.path.join(ROOT, "src", "core", "card_db.gd"))
src_cards = []
for m in CARD_RE.finditer(cards_src):
    src_cards.append([
        m.group("name"),
        TYPE_MAP.get(m.group("type"), m.group("type")),
        m.group("cost"),
        m.group("points"),
        TARGET_MAP.get(m.group("target"), m.group("target")),
        m.group("desc"),
        m.group("count"),
    ])

print("1. 卡牌表 vs card_db.gd")
if not src_cards:
    bad("未能从 card_db.gd 解析出任何卡牌（正则失效？）")
else:
    ok("从源码解析出 %d 种卡" % len(src_cards))

doc = read(DOC)
sec62 = doc.split("## 6.2")[1].split("## 6.3")[0]
doc_cards = []
for line in sec62.splitlines():
    if not line.strip().startswith("|"):
        continue
    cols = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cols) != 8:
        continue
    if "---" in cols[3] or cols[0] == "ID":
        continue
    doc_cards.append(cols[1:])   # 去掉 ID 列

if len(doc_cards) != len(src_cards):
    bad("卡牌数量不一致：文档 %d 种，源码 %d 种" % (len(doc_cards), len(src_cards)))
else:
    ok("卡牌数量一致：%d 种" % len(doc_cards))
    for d, s in zip(doc_cards, src_cards):
        if d != s:
            bad("卡牌不一致:\n         文档=%s\n         源码=%s" % (d, s))
    if all(d == s for d, s in zip(doc_cards, src_cards)):
        ok("每张卡的 名称/类型/费用/目标/效果/数量 全部一致")

total = sum(int(c[6]) for c in src_cards)
if total == 20:
    ok("初始牌组合计 20 张")
else:
    bad("初始牌组合计应为 20，实际 %d" % total)

# ── 2. 敌人 ───────────────────────────────────────────────
print("2. 敌人描述 vs enemy_db.gd")
enemy_src = read(os.path.join(ROOT, "src", "core", "enemy_db.gd"))
m = re.search(r'GOLEM_MAX_HP', enemy_src)
hp_doc = "35 生命" in doc
hp_src = re.search(r'"max_hp": T\.GOLEM_MAX_HP', enemy_src) is not None
if hp_doc and hp_src:
    ok("魔像 35 生命（文档与源码一致，源码用 GOLEM_MAX_HP 常量）")
else:
    bad("魔像生命描述不一致（文档 %s / 源码 %s）" % (hp_doc, hp_src))

vals = re.findall(r'"kind": T\.IntentKind\.(\w+), "value": (\d+)', enemy_src)
expected = [("ATTACK", "6"), ("DEFEND", "8"), ("ATTACK", "10")]
if vals == expected:
    ok("行为循环 攻击6 → 防御8 → 攻击10（源码 %s）" % vals)
else:
    bad("行为循环不一致：源码 %s，期望 %s" % (vals, expected))
if "攻击 6 → 获得 8 护盾 → 攻击 10" in doc:
    ok("文档中的行为循环描述存在")
else:
    bad("文档缺少行为循环描述")

# ── 3. 文件清单 ───────────────────────────────────────────
print("3. 文件清单中的路径是否存在")
sec61 = doc.split("## 6.1")[1].split("## 6.2")[0]
# §6.1 是树形结构：目录行以 / 结尾，其后的缩进行是裸文件名，需要重建完整路径
paths = []
cur_dir = ""
for line in sec61.splitlines():
    s = line.rstrip()
    if not s or s.startswith("```") or s.startswith("#"):
        continue
    mdir = re.match(r'^([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*/)(\s|$)', s)
    if mdir:
        cur_dir = mdir.group(1)
        continue
    mfile = re.match(r'^\s+([A-Za-z0-9_.]+\.(?:gd|tscn|godot|md|xlsx|py))(\s|$)', s)
    if mfile:
        name = mfile.group(1)
        # 合并写法如 battle_scene.tscn/.gd 视为 .tscn 与 .gd 两个文件
        if "/." in name:
            base, ext = name.split("/.")
            paths.append(cur_dir + base)
            paths.append(cur_dir + base.rsplit(".", 1)[0] + "." + ext)
        else:
            paths.append(cur_dir + name)
        continue
    mtop = re.match(r'^([A-Za-z0-9_.]+\.(?:godot|md|py|gd|tscn))\s', s)
    if mtop:
        paths.append(mtop.group(1))

if not paths:
    bad("未能从 §6.1 解析出任何路径")
missing = []
for p in sorted(set(paths)):
    if not os.path.exists(os.path.join(ROOT, p.replace("/", os.sep))):
        missing.append(p)
if missing:
    for p in missing:
        bad("文档列出但不存在：%s" % p)
else:
    ok("§6.1 列出的 %d 个路径全部存在" % len(set(paths)))

# ── 4. 行数 ───────────────────────────────────────────────
print("4. 文档标注的文件行数")


def count_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return len(f.readlines())


line_claims = re.findall(r'([A-Za-z0-9_]+\.(?:gd|tscn|godot))[^\n（(]*[（(](\d+)[）)]', doc)
if not line_claims:
    bad("未能从文档解析出任何行数标注")
bad_lines = 0
for fname, claimed in line_claims:
    hit = None
    for dirpath, _, files in os.walk(ROOT):
        if ".godot" in dirpath:
            continue
        if fname in files:
            hit = os.path.join(dirpath, fname)
            break
    if hit is None:
        bad("找不到文件 %s（无法校验行数）" % fname)
        bad_lines += 1
        continue
    actual = count_lines(hit)
    if actual != int(claimed):
        bad("%s 行数：文档 %s，实际 %d" % (fname, claimed, actual))
        bad_lines += 1
if bad_lines == 0 and line_claims:
    ok("%d 处行数标注全部与文件一致" % len(line_claims))

# ── 5. Markdown 中的图片引用 ──────────────────────────────
print("5. 文档中的图片引用是否可解析")
md_files = []
for base in (ROOT, os.path.join(ROOT, "docs")):
    if os.path.isdir(base):
        for fn in sorted(os.listdir(base)):
            if fn.endswith(".md"):
                md_files.append(os.path.join(base, fn))
img_re = re.compile(r'!\[[^\]]*\]\(([^)]+)\)')
total_refs = 0
missing_imgs = []
for md in md_files:
    body = open(md, encoding="utf-8").read()
    for ref in img_re.findall(body):
        if ref.startswith("http"):
            continue
        total_refs += 1
        target = os.path.join(os.path.dirname(md), ref.replace("/", os.sep))
        if not os.path.exists(target):
            missing_imgs.append("%s → %s" % (os.path.basename(md), ref))
if missing_imgs:
    for m in missing_imgs:
        bad("图片引用失效：%s" % m)
elif total_refs:
    ok("%d 处图片引用全部可解析" % total_refs)

# ── 汇总 ──────────────────────────────────────────────────
print()
print("=" * 60)
print("检查项 %d，失败 %d" % (checks, len(problems)))
for p in problems:
    print("  - " + p)
sys.exit(1 if problems else 0)
