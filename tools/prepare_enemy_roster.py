"""Freeze the authorized enemy roster, visual briefs, prompts and change boundary."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/enemy-roster-20261115"
OUT = ROOT / "output/imagegen/enemy-roster-20261115"

# Each entry has an authored silhouette and two separately painted animation props.
# Families control material-appropriate movement, never enemy identity or rules.
BRIEFS = {
    "N02": ("ink", "A squat navy glass ink-bottle imp with a cream envelope collar, expressive ink eyes, tiny brass feet and two folded paper wings; a distinctive round bottle silhouette", "an ornate dark fountain-pen nib with a small cream feather", "a single curled cream envelope flap"),
    "N03": ("machine", "A green vintage computer terminal crab with bracket-shaped claws and four short cable legs, a glowing face on its screen, keys across its belly", "a green bracket-shaped mechanical pincer", "a loose brass keyboard key with an engraved abstract mark"),
    "N04": ("liquid", "A turquoise conical-flask snail, round glass shell filled with amber liquid, cork horns, a thick rolled laboratory worksheet as its soft foot, curious eyes", "a curved copper pipette arm with a glass bulb", "a floating small amber glass droplet"),
    "Q01": ("paper", "A folded ivory pop-quiz paper bat, angular broad paper wings, a round brass stopwatch face, sharp brows and a small eraser tail", "a long red wooden pencil with a blunt eraser end", "a triangular folded ivory paper dart"),
    "B01": ("stone", "A towering calculus textbook golem with stone-grey book covers, brass protractor horns, graph-paper chest and broad compass feet, stern two luminous amber eyes", "a brass drawing compass opened like a claw", "a floating faceted cream geometric cube"),
    "E01": ("paper", "A three-headed exam-book cerberus, three bound test-book heads with visibly different angry eyes, one broad dark red binder body, sturdy paper-fold paws", "a broad red grading pencil shaped like a lance", "a curled ivory answer-sheet banner"),
    "E02": ("machine", "A drafting-board beetle with a tall teal blueprint carapace, copper caliper mandibles, ruler legs and one round inspection lens", "an articulated brass caliper claw", "a small rolled teal technical blueprint"),
    "E03": ("paper", "A stapled three-folder hydra with three curved necks made of folded folders, rust-orange binder-clip jaws, one shared low round body of project sheets", "a large bronze binder clip shaped as a claw", "three connected cream sticky notes folded into a short ribbon"),
    "E04_1": ("stone", "A geometric drafting owl assembled from ivory polyhedra and teal drafting tools, cubical belly, pointed set-square brows and compass legs", "a slim brass drafting compass", "an ivory faceted tetrahedron"),
    "E04_2": ("machine", "A dark teal server centipede, stacked small terminal segments, copper cable legs and a rectangular expressive monitor head, one antenna ending in a keycap", "a hooked copper cable mandible", "a single teal mechanical keyboard key"),
    "E04_3": ("paper", "A bound-manuscript moth with two broad layered ivory page wings, dark green book-spine abdomen, red bookmark antennae and watchful ink eyes", "a curved red bookmark ribbon", "a single fan of three ivory manuscript pages"),
    "E05": ("stone", "A bronze laurel tortoise carrying a small stepped stack of green achievement books, calm severe eyes and a medal-like shell center, four sturdy plated feet", "a curved gold laurel branch", "a small bronze star-shaped achievement medal"),
    "E06": ("liquid", "A round-table interview octopus, dark navy velvet body with a pale theatre-mask face, a tie-like strip and four short tentacles ending in tiny microphones", "a small bronze tabletop microphone on a curved flexible stalk", "a blank cream interview name badge with a teal clip"),
    "E07": ("paper", "A patched hourglass phoenix, amber hourglass torso, rusty red paper feathers with repair stitches, a bent pencil beak and ash-grey folded talons", "a long patched russet paper feather", "a cracked brass hourglass ring"),
    "Q0A_1": ("paper", "A branching mind-map tree golem made of ivory cards and brown wooden index tabs, three branch arms and a teal root knot with two alert eyes", "a forked wooden pointer branch", "three blank ivory index cards connected by a short teal ribbon"),
    "Q0A_2": ("paper", "A scroll archivist snail, huge spiral parchment shell held by dark blue straps, a square brass spectacles face, stubby folded-paper feet", "a curled wide ivory parchment scroll", "a dark blue wax-seal stamp"),
    "Q0A_3": ("machine", "A black-and-teal terminal spider with a single square screen body, bright amber eye slits and six copper circuit legs, a compact agile low silhouette", "a copper circuit-board leg ending in a fine probe", "a small amber hexagonal circuit chip"),
    "Q0A_3_1": ("machine", "A magnifying-glass moth, oversized round inspection lens face with teal frame, two translucent ivory checklist wings and spring-like copper feelers", "a small silver inspection probe", "a cream paper check tile with one simple green tick"),
    "Q0B_1": ("stone", "A small lectern-shield knight without a human body, a mahogany wooden podium face, a cream presentation-board shield and bronze pointer lance, short mechanical feet", "a slim brass laser-pointer lance with a red tip", "a curved ivory presentation-board shield"),
    "Q0B_2": ("paper", "A red-seal paperwork boar with layered ivory document armor, curled scroll tusks, a round dark red wax-seal snout and short stout hooves", "a broad russet wax-seal hammer", "a curled cream document corner"),
    "Q0C": ("paper", "A four-wing dictionary owl, deep blue book-body with four distinct layered cream wings, round gold spectacles and an ink-blue quill tail", "a blue ink quill feather", "a small folded cream vocabulary card"),
    "Q0D": ("paper", "A six-wing dictionary wyvern, tall navy book-spine neck, six sweeping cream paper wing fans, gold-tipped horns and an intelligent narrow-eyed face", "a curved navy book-spine horn", "a long six-page ivory feather fan"),
    "Q0E_1": ("machine", "A walking project fortress with teal folder walls, a small brass crane on its back, four heavy drafting-tool legs and glowing eyes in a reinforced binder gate", "a brass crane hook hanging from a short chain", "a rolled ivory project blueprint"),
    "Q0E_2": ("paper", "A compact sticky-note parasite tick, squat mustard-yellow note body, black binder-clip mandibles, tiny curled paper legs and an impish squint", "a black binder-clip jaw", "a curled mustard sticky-note tab"),
    "Q0E_3": ("paper", "A two-headed flowchart eel, long cream accordion-paper body, teal branching tail and two angular note-card heads with pointed brows", "a forked teal paper arrow tail", "a curled narrow ivory flowchart ribbon"),
    "N13": ("paper", "A homework mushroom slug, rounded rolled worksheet cap with a brass paperclip stalk, a soft accordion-paper foot and sleepy ink eyes", "a bent brass paperclip feeler", "a small curled ivory worksheet strip"),
    "N14": ("stone", "A squat mathematical stone golem, grey cuboid torso with a recessed brass compass dial, triangular shoulders and broad cream set-square feet", "a floating brass set-square blade", "a small carved grey geometric pyramid"),
    "N15": ("machine", "A green circuit-board locust, angular motherboard abdomen, black cable antennae, a bright amber debug-eye and long bent copper spring legs", "a segmented green circuit-board wing", "a tiny amber diagnostic light bulb"),
    "N16": ("ink", "A candle-book firefly, a small warm ivory candle face seated in a folded green pocket book, two thin page wings and a tiny brass wick cap, drowsy but alert", "a thin ivory book-page wing", "a small amber wax droplet"),
    "N17": ("paper", "An academic reference owl with a tall cream index-card ruff, narrow navy book-spine body, brass bookmark beak and layered citation-card tail", "a long brass bookmark quill", "a fan of ivory index-card feathers"),
    "N18": ("ink", "An elegant ink-scroll serpent, long curling ivory essay-scroll body with a navy ink tail, a pen-nib snout and stern amber eyes, coiled low into an S", "a long pointed navy fountain-pen nib", "a curled thin cream manuscript ribbon"),
    "N19": ("machine", "A russet toolbox crab with teal drafting-board shell, two asymmetric metal clamp claws, four broad ruler legs and a brass hinge face", "a bronze adjustable clamp claw", "a short teal measuring-ruler segment"),
    "N20": ("paper", "A vocabulary-cube caterpillar, five uneven ivory and navy wooden dictionary cubes forming a short arched body, gold spectacles on its leading cube, small page feet", "an ivory wooden vocabulary cube with abstract engraved strokes", "a small navy bookmark tassel"),
    "N21": ("paper", "A revision hedgehog with rounded dark green book-cover body, dense upright ivory flashcard spines and a brass eraser nose, four stubby feet", "a fan of upright cream flashcards", "a round brass paper fastener"),
    "N22": ("liquid", "A microphone chameleon with deep teal skin, a curled cable tail, oversized brass microphone head grille and a cream name-badge belly, four stable short feet", "a small brass clip microphone", "a curved dark teal audio cable"),
    "N23": ("machine", "A projector heron, long copper tripod legs, a compact navy projector body, bright lens eye and two ivory slide-panel wings, one leg slightly bent but supported", "a narrow ivory projection-screen wing", "a round brass projector lens cap"),
    "N24": ("machine", "An athletic stopwatch bull, compact bronze stopwatch torso, two curved whistle horns, grey sneaker hooves and a red track-ribbon tail, powerful planted stance", "a curved brass whistle horn", "a small red track ribbon bow"),
    "N25": ("stone", "A stern teacup owl, jade ceramic teacup body and two deep brown book wings, a brass spectacles face and wooden desk-feet, calm imposing posture", "a curled jade teacup handle", "a small cream appointment card"),
    "N26": ("machine", "A narrow attendance punch-clock sentinel with navy housing, cream ticket-roll belt, brass clock eyes and two short stamp feet", "a brass punch stamp with a dark handle", "a curled cream attendance ticket"),
    "N27": ("paper", "A linked-pencil ant creature with one russet binder-clip body and three pencil-shaped antenna heads, accordion worksheet abdomen and six small wooden legs", "three small wooden pencils bound together with a teal band", "a curved ivory worksheet strip"),
    "N28": ("machine", "An early-morning alarm-clock rooster, copper twin-bell head, dark teal clock body, sharp cream paper comb and red bookmark tail feathers, two sturdy clockwork feet", "a curved copper alarm-bell hammer", "a broad red bookmark tail feather"),
    "N29": ("liquid", "A campus-network router jellyfish, pale blue translucent dome around a teal router shell, two copper antenna horns, four flowing cable tentacles and a glowing amber error-eye", "a teal router antenna with a brass tip", "a small glowing amber connection bead"),
    "N30": ("machine", "A slide-carousel squid with a dark green round projector head, brass central lens eye, six curled pointer tentacles and a small stack of ivory slide cards on top", "a brass extendable presentation pointer", "a single ivory slide frame"),
    "N31": ("machine", "A relentless desk-telephone hound, russet rotary-phone body, two receiver ears, an amber hourglass face and four cable paws, leaning forward impatiently", "a curved dark russet telephone receiver", "a coiled copper phone cord loop"),
    "N32": ("stone", "A scholarship scales griffin, bronze trophy body with a laurel collar, two navy certificate wings, golden balance-pan claws and a proud narrow-eyed face", "a small golden balance scale pan", "a bronze laurel medal on a navy ribbon"),
    "N33": ("machine", "A twin-lens plagiarism scanner spider, broad ivory scanner carapace, two jade glass lens eyes, red ruled-paper mandibles and six fine brass legs", "a jade circular scanning lens", "a curled ivory manuscript strip with dark abstract line patterns"),
    "N34": ("stone", "A library-seat hermit crab carrying a wooden reading chair and a dark green backpack shell, two bookmark claws, brass spectacles eyes and four low sturdy feet", "a wooden chair-leg claw", "a dark green cloth bookmark strap"),
    "N35": ("paper", "An internship briefcase fox with a slim dark navy leather case torso, folded ivory collar, russet tie tail and pointed bronze clasp ears, alert angular face", "a long rust-orange tie ribbon", "a small brass briefcase clasp"),
    "N36": ("machine", "An exam-registration ticket-printer toad, low round dark green printer body, two copper button eyes, cream ticket tongue and four squat mechanical feet", "a rolled ivory registration ticket", "a round brass counter button"),
    "N37": ("machine", "An online-exam webcam cyclops, one large jade glass camera eye above a navy laptop-shell body, two small keyboard wings and cable feet, no person inside", "a curved dark camera-shutter petal", "a small bronze webcam status-light housing"),
    "N38": ("paper", "A peer-review three-mask raven, one dark navy binder body, three hinged ivory theatrical masks across its face, ballot-paper wings and a bronze ballot-box tail", "a narrow ivory folded ballot wing", "a small ivory theatre mask with ink eyes"),
    "FY_B1_TASK": ("stone", "A freshman examination-gate tortoise, an enormous ivory textbook shell shaped like a campus gate, bronze mathematical arches, four green stone feet and stern amber eyes", "a broad brass protractor arch", "a floating grey geometric prism"),
    "FY_B2_TASK": ("machine", "A sophomore laboratory clockwork colossus, copper apparatus torso, turquoise flask shoulders, dark green notebook armor and heavy stable jointed feet, one glass dial face", "an articulated brass laboratory clamp", "a floating turquoise glass flask bulb"),
    "FY_B3_TASK": ("paper", "A research-archive hydra, three long ivory scroll necks with dark green book-cover crests, one broad mahogany archive-chest body and heavy folded-page feet", "a long curled ivory archival scroll", "a brass archive key with a dark green tassel"),
    "FY_B4_TASK": ("stone", "A graduation-defense lectern dragon, majestic mahogany podium torso with an ivory carved mask face, dark navy academic-cloak paper wings, bronze laurel horns and stable book feet, emphatically nonhuman", "a long bronze presentation-pointer spear", "a curled navy academic-cloak feather"),
    "FY_ROUTE_job_TASK": ("stone", "A corporate briefcase armored lion, charcoal-blue leather briefcase body, a mane of brass contract clasps, ivory tie-shaped chest plate and heavy bronze paws, confident golden eyes", "a bronze contract-seal claw", "a folded ivory employment-contract ribbon"),
    "FY_ROUTE_exam_TASK": ("paper", "A postgraduate exam pagoda crane spirit, tall tiered navy dictionary torso, wide ivory examination-paper wings, jade spectacles face and long bronze compass legs, elegant alert stance", "a long ivory examination-paper feather", "a floating jade octagonal study crystal"),
    "FY_ROUTE_research_TASK": ("stone", "A research-laurel microscope stag, bronze microscope torso, branching green laurel antlers, an amber objective-lens face and four stable ivory manuscript hooves", "a curved bronze microscope focusing arm", "a green laurel branch bearing a small brass medal"),
    "FY_ROUTE_abroad_TASK": ("paper", "An overseas compass-globe albatross, teal globe body wrapped in a brass compass ring, sweeping ivory passport-page wings and a navy travel-case tail, long copper beak and sturdy landing feet", "a long ivory passport-page wing feather", "a small brass compass needle in a teal ring"),
}

STYLE = """Style/medium: polished hand-painted 2D game character illustration, delicate dark teal ink outlines, painterly faceted shading, fine readable material details, restrained cream/teal/navy/copper/russet palette, warm soft light from upper left. Campus fantasy task-monster design, expressive and formidable, readable silhouette at small battle size, consistent with detailed illustrated campus heroes. No photographic rendering, no 3D plastic, no flat UI icon.
Asset type: animation-ready cutout sprite component sheet on an absolutely uniform solid vivid magenta (#ff00ff) background. Magenta is ONLY the background; no magenta, pink or violet in any subject, no cast shadow, no floor, no scenery, no smoke or glow haze. Exactly THREE isolated painted elements with wide magenta gaps; no borders, captions, letters, numbers, text, watermark or interface.
Composition: 1024x1024 square. MAIN COMPLETE MONSTER is the largest element, entirely contained in the RIGHT area x=300..980, y=70..950, looking LEFT toward the player, with its full crown, wings, tail and planted feet visible. The monster has its own distinctive body and integrated face. In the UPPER LEFT area x=35..235, y=120..420, draw one separate attack prop. In the LOWER LEFT area x=35..235, y=620..890, draw one separate secondary accent. Those two detached objects are small animation parts painted in the same material style, never extra complete monsters. Keep the vertical magenta gutter x=240..290 completely empty. All three elements sharply edged, no anti-alias halo painted into the background. Full body uncut, balanced construction, no malformed human limbs. No content beyond the three designated regions."""


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    EV.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if (EV / "before.zip").exists():
        raise SystemExit("Task baseline already exists; do not overwrite it.")
    modified = ["agent.md", "实施计划与验收基线.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md",
                "src/ui/battle/battle_actor_view.gd", "src/ui/ui_style.gd",
                "tests/suites/test_ui_character_art.gd", "tests/run_ui_tests.gd"]
    with zipfile.ZipFile(EV / "before.zip", "x", zipfile.ZIP_DEFLATED) as archive:
        for name in modified:
            archive.write(ROOT / name, name)
    files = [ROOT / "project.godot"]
    for directory in ("src", "data", "tests", "assets/art", "tools"):
        files.extend(p for p in (ROOT / directory).rglob("*")
                     if p.suffix in (".gd", ".gdshader", ".tscn", ".json", ".png", ".py", ".ps1"))
    protected = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in files if p.is_file() and p.relative_to(ROOT).as_posix() not in modified}
    write(EV / "baseline.json", {"created_utc": datetime.now(timezone.utc).isoformat(),
          "before_files": {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in modified},
          "protected": protected, "api_successful_before": 51, "api_limit": 200})
    manifest = json.loads((ROOT / "data/four_year/manifests/campus_four_year.json").read_text(encoding="utf-8"))
    tasks = {t["id"]: t for t in json.loads((ROOT / "data/four_year/definitions/tasks.json").read_text(encoding="utf-8"))}
    labels = json.loads((ROOT / "src/ui/ui_labels.json").read_text(encoding="utf-8"))["labels"]
    assert set(manifest["enabled"]["task"]) == set(BRIEFS) | {"N01"}
    entries, jobs = [], []
    for id in manifest["enabled"]["task"]:
        t = tasks[id]
        item = {"id": id, "name": labels.get(id, t["name_key"]), "kind": t["kind"],
                "phases": [x["phase_key"] for x in t["phases"]], "requirements": ["UIR-069", "UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"]}
        if id == "N01":
            item.update(status="reuse_reviewed_native_rig", rig="res://assets/art/actor-rig-drawings/N01/rig.json", version=4)
        else:
            family, body, attack, accent = BRIEFS[id]
            prompt = f"Use case: stylized-concept\nPrimary request: unique enemy {id}, representing {item['name']}.\n{STYLE}\nMain complete monster: {body}.\nSeparate UPPER LEFT attack prop: {attack}.\nSeparate LOWER LEFT accent: {accent}.\nMake the main monster large and richly detailed while respecting the empty gutter and the exact three regions."
            prompt_path = OUT / "prompts" / f"{id}-v1.txt"
            prompt_path.parent.mkdir(exist_ok=True)
            prompt_path.write_text(prompt, encoding="utf-8")
            item.update(status="pending_generation", family=family, body=body, attack=attack, accent=accent,
                        prompt_file=prompt_path.relative_to(ROOT).as_posix(),
                        prompt_sha256=hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
                        output=f"output/imagegen/enemy-roster-20261115/{id}-v1.png", version=1,
                        image_inputs=[], reference_mode="text style brief derived from viewed Lin/Shen and N01 art; generate mode has no uploaded images")
            jobs.append({"prompt": prompt, "out": f"{id}-v1.png", "size": "1024x1024", "quality": "high"})
        entries.append(item)
    write(OUT / "roster.json", {"manifest": "data/four_year/manifests/campus_four_year.json", "total": len(entries), "new_images_planned": len(jobs), "entries": entries})
    for filename, values in (("first.jsonl", [j for j in jobs if j["out"] == "N02-v1.png"]),
                             ("remaining.jsonl", [j for j in jobs if j["out"] != "N02-v1.png"])):
        (OUT / filename).write_text("".join(json.dumps(j, ensure_ascii=False) + "\n" for j in values), encoding="utf-8")
    note = "2026-11-15当前§0.20.27：用户要求不同敌怪建模完成并上线、每种有各自形象。当前四学年manifest启用60种任务，范围现扩展为这60种的独立二维骨架/分层形象与正式战斗默认启用，包含召唤附属、四学年Boss和四条路线终敌。N01复用已核对V4，其余59种各有独立主体/攻击部件/辅件，不再让路线终敌共用毕业答辩图。按UIR-069及原动作需求，先核对清单/画风并保存来源，生成一项实际看图后继续批次，再完成同源拆件/六类动作/正式接入与逐ID渲染、真实命令和保存继续/阶段/召唤/终局验证。API累计51/200起记，原已授权费用继续有效。规则/RNG/存档schema、GameSession写口、四位已选人物、HUD/命中区和动态/倍速/终局门控保持；只用隔离存档，真实档仅作启动前后只读hash。允许修改BattleActorView/UiStyle的敌怪表现路由，新增EnemyArt注册与资源、专项验证及必要旧断言对齐；共享NativeActorRig原代码保持，完整规则/UI本轮重跑。此处“上线”指项目正式游戏默认入口生效，不等于打包发行或整版G0/G6/G8签收。详细设计见DOC_LINK，证据根artifacts/verification/enemy-roster-20261115/。当前为实施中，未生成项与失败项如实保留。"
    for name, link in (("agent.md", "docs/plans/2026-11-15-enemy-roster-design.md"),
                       ("docs/界面层契约.md", "plans/2026-11-15-enemy-roster-design.md"),
                       ("动作或者图片描述/需求台账.md", "../docs/plans/2026-11-15-enemy-roster-design.md")):
        p = ROOT / name
        raw = p.read_bytes()
        prefix = len(b"".join(raw.splitlines(keepends=True)[:2]))
        p.write_bytes(raw[:prefix] + note.replace("DOC_LINK", f"[敌怪制作与接入设计]({link})").encode("utf-8") + b"\n\n" + raw[prefix:])
    p = ROOT / "实施计划与验收基线.md"
    raw = p.read_bytes().replace("版本：v1.85".encode(), "版本：v1.86".encode(), 1)
    pos = raw.index(b"\n## 1.")
    section = "\n## 0.20.27 2026-11-15 全部敌怪独立形象与正式接入\n\n" + note.replace("DOC_LINK", "[敌怪制作与接入设计](docs/plans/2026-11-15-enemy-roster-design.md)") + "\n\n"
    p.write_bytes(raw[:pos] + section.encode("utf-8") + raw[pos:])
    design = ROOT / "docs/plans/2026-11-15-enemy-roster-design.md"
    design.write_text("""# 敌怪独立形象与正式战斗接入（2026-11-15，§0.20.27）

用户明确要求不同敌怪建模完成并上线，每种敌怪各有自己的形象。范围以当前四学年manifest的60个task ID为准，含普通、精英、召唤附属、四学年Boss和四路线终敌；历史包额外的测试任务保持回退。四名已选人物保持P01V12/P02V8/P03V10/P04V11。“上线”在本轮表示项目正常入口默认生效，完整发行出口继续独立记录。

采用已验证原生二维骨架：N01复用既有V4；其余59种新画独立主体及同源攻击/辅助部件，形象由实际任务语义分别设计，轮廓/材质/脸/道具均可辨认。普通怪、精英和Boss按纸张、墨水、机械、玻璃软体与沉重材质分别安排蓄力、接触、受击、回收和独立循环。既有动作事件与接触时点接口保持。仅换旧图并整体平移成本低但缺少部件运动；给所有敌人套N01骨架会混淆身份；这里选逐ID新画与少量可复用的材质运动链。

G6先锁定[逐ID设计与提示词](../../output/imagegen/enemy-roster-20261115/roster.json)，实际查看N01绘图与沈V10母图，第一项N02生成后看图核对分区、完整轮廓、画风与可拆件性，再完成剩余批次。批量使用bundled imagegen CLI的generate-batch和当前配置模型，逐项完整文字画风约定；没有实际上传参考图的请求明确记为文字条件生成。200张累计上限从51张起，首次59张计划，不默认生成第二版或额外表情。所有prompt、原件、hash、机器质检与实际看图结论分别登记，未知金额如实记。

G7只新增EnemyArt、敌怪资源和BattleActorView/UiStyle的只读路由。正式定义ID先精确匹配，再保留历史回退，四条路线不受旧alias合并。主体使用加权网格、两件独立部件沿原生骨骼运动；动作曲线按材质区分，禁止以完整图旋转冒充逐部件运动。稳定HUD/目标区、领域/RNG、存档、GameSession写边界、四名人物与NativeActorRig保持。

G8子项验证包括全部60ID可配置/独立图hash/六类动作与循环、每阶段重建与召唤/离场、未知ID回退、真实命令的领域/RNG/revision/事件A/B、普通主菜单/地图/战斗/保存继续、1280×800及紧凑窗口三字号、动态关闭/减少动态/倍速、终局去重和重入。逐ID完整图与代表实战连续帧必须实际看图，自动通过不能代替美术观察。完整规则/UI重新执行；真实档只读核对，所有有玩家命令的验证均为隔离SaveStore。

证据根artifacts/verification/enemy-roster-20261115/。当前状态：范围/来源核对完成，59种待生成；未声称已上线。用户最终美术判断与整版G0/G6/G8出口保留。
""", encoding="utf-8")
    print(json.dumps({"enemies": len(entries), "new_images": len(jobs), "protected_files": len(protected), "api_before": 51, "first": "N02"}))


if __name__ == "__main__":
    main()
