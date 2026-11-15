"""Build 22 named, reference-conditioned eight-scene prompts; no API calls."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/card-style-20261115'

STYLE = (
    'Shared rendering: polished hand-painted 2D campus adventure card illustration, '
    'matching the uploaded formal character drawing: refined dark contour lines, confident '
    'painted midtones, soft cel-shaded volume, restrained paper and fabric brush texture, '
    'natural adult anatomy and expressive eyes. Clear foreground silhouette, one specific '
    'readable action per picture, coherent warm key light and cool fill. Rich but controlled '
    'color, clear light-dark grouping, quietly simplified environmental depth. '
    'These are finished narrative illustrations, not flat icons, pale generic stationery '
    'vignettes, chibi, photorealism or 3D renders. Avoid dense decorative clutter.'
)

IDENTITY = {
    'P01': 'Lin Xu / 林序, same young adult Chinese man as reference: short tousled black hair, rectangular black glasses, teal-blue rolled-sleeve jacket over ivory collared shirt. Precise, practical gestures. Teal and copper-gold palette, modular mechanisms, traces and measured steps. Do not give him the green shirt of P03.',
    'P02': 'Xu Zhiwei / 许知微, same young adult Chinese woman as reference: low dark ponytail, round thin glasses, navy cardigan with muted violet edging over white collared shirt. Focused, thoughtful posture. Indigo and lavender palette, bound research notebooks, page tabs and delicate citation threads.',
    'P03': 'Shen Jianzhang / 沈见章, same young adult Chinese man as reference: short dark hair, NO glasses, olive-green rolled-sleeve overshirt with distinctive violet chest pocket over ivory T-shirt. Alert eyes, head naturally above shoulders, upright relaxed neck. Forest-green and plum palette, evidence slips, lens and ink reactions. Academic investigation, never poisoning people.',
    'P04': 'Tang Yining / 唐以宁, same young adult Chinese woman as reference: dark hair in high loose bun, cream cable-knit cardigan over sage shirt, red lanyard, blue jeans and coordination clipboard. Warm capable expression, relaxed shoulders and anatomically plausible gestures. Cream, coral and teal palette. Other adult teammates have clearly different hair/clothes and are never duplicate Tangs.',
    'C': 'Shared campus world of the four uploaded formal adults: P01 teal jacket and rectangular glasses; P02 low ponytail, round glasses, navy-violet cardigan; P03 olive overshirt, violet pocket, no glasses; P04 bun, cream cardigan, red lanyard. Preserve the identity assigned in each slot. Warm daylight, muted teal, cream and soft terracotta; the main action has priority over decorative effects.',
}

# Each line corresponds exactly to the named card in the official design catalog.
# Different camera angles and concrete props make the title legible at thumbnail size.
SCENES = {
'P01': '''
Over-shoulder close view: Lin rapidly isolates one faulty amber junction among several teal paths on a laptop; pen tip and narrowed focused gaze point to that exact node, surrounding routes recede.
Three-quarter medium scene: Lin builds a small working tabletop linkage one component at a time, first two parts complete and the next small piece in his fingertips; modest incremental progress, not a heroic leap.
Macro of Lin's teal-cuffed writing hand adding short nonverbal annotation strokes beside the missing block in a diagram; the completed comment physically bridges an unexplained gap. Pen, page and block are the focus.
Close view of Lin inspecting the input side of a laptop test rig, comparing a cable connector and one sample card before inserting either; incoming path highlighted copper, output side quiet.
Lin assembles a simple bridge model while checking its alignment with a ruler held in his other hand; newly joined part and live measurement occupy the same focal area, testing while doing.
Low tabletop view of Lin pressing successive buttons along a three-stage mechanism; only the current stage glows and the next awaits, a clear left-to-right stepwise run. His calm face appears behind it.
Overhead view: Lin compares a paper schematic and the corresponding laptop diagram side by side, fingertips on the same junction in both; complementary teal and amber marks reveal a mismatch.
Extreme prop close-up: two different modular interface plugs held by Lin's two hands are correctly oriented toward each other; their matching pins and slots align precisely, a narrow warm connection glow.
Dynamic three-quarter portrait: Lin completes an uninterrupted sweep across a linked row of small modules, a single copper light trail joining every stage; confident but natural wrist and shoulder, no extra arms.
Side view: Lin alternates checking a laptop and tapping a small timer, repeating teal-copper pulses spaced evenly across the workbench; a controlled debugging rhythm rather than frantic speed.
Quiet waist-up scene: Lin puts down his pen at a clearly paused laptop process, leans back comfortably and drinks tea beside a still timer; a bright pause point is the visual hinge.
Warm desk-level portrait: Lin explains a simple schematic to a prominent yellow rubber duck placed beside his laptop; open hand and attentive face clearly address the duck, the humorous prop unmistakable.
Macro inspection through a small magnifier: Lin's pen locates an offset seam between a translucent blueprint and a model, the two slightly misaligned edges emphasized in copper. One exact error, not random gears.
Lin takes a proven small test jig from a tidy storage tray and uses it again on a new module; old witness mark and new matching result glow alike. Three-quarter workshop composition.
Close-up of Lin carefully clipping a transparent sketch overlay in place above an unfinished model, preserving its solution path; the lower draft remains visible and the held thought stays intact.
Over-shoulder scene of Lin flipping back through a fan of earlier step sketches and tracing the successful route with his pen; the old sequence curves back toward the current work.
Lin practices the same small assembly movement on three similar test pieces arranged front to back; two finished pieces and one in progress make repetition clear, natural hands in the foreground.
Top-down still life of a well-used reusable checklist beside Lin's hand, wipe-clean check boxes and movable colored markers reset for another pass; worn clip and repeated punched holes signal reuse.
Tight three-quarter scene: Lin compares the finished mechanism against a reference gauge, both fitting exactly; final green indicator and satisfied focused eyes show actual result validation.
Reflective evening portrait: Lin places accumulated successful step cards into one durable notebook, many thin copper routes settling into one stable reusable method, shelves quiet behind him.
Overhead workbench: Lin lays out a clear ordered row of physical step tiles from tools through assembled prototype to final test; his pen sets the first tile and arrows are simple shapes, no labels.
Lin checks two prerequisite components and a charged power pack before reaching a larger machine's start button; required sockets are visibly ready, background machine still waiting.
Forceful close view of Lin using one precise probe to solve the single jammed center gear of a paper-mechanical puzzle; surrounding structure opens outward around that one breakthrough.
Lin gathers scattered requirement slips from the wide desk into one compact prioritized stack clipped beside a simple working sketch; wide-to-narrow composition makes scope convergence visible.
Close still life: Lin deliberately leaves an empty interval between two groups of planned work tiles beside a half-full hourglass, pen hovering calmly over the reserved space, copper morning light.
Lin presents a small prototype to two different adult classmates across a table; they inspect one highlighted joint and exchange clear restrained hand gestures. Review rather than lecture, Lin remains focal.
Three-quarter action scene: Lin starts a prepared array of modules with one switch; all teal paths converge into one strong copper output, no scattered side jobs, eyes fixed on the main result.
Side-lit portrait at a window: Lin works within a distinct rectangle of clear afternoon light, completed prerequisite trays behind and one active prototype ahead; a limited execution window conveyed by light and timer.
Lin retrieves an archived folder and a matching test module from a labeled-by-color shelf, then places them beside the laptop to run again; a curved route reconnects the old work to current setup.
Wide tabletop view of a complete assembled campus model undergoing final acceptance: Lin checks the last connection while several earlier components already glow consistently, one coherent finished whole.
Top-down composition of Lin's hands tidying his desk into notebook, tool and active-work zones; loose wires neatly coiled, laptop centered and ample cleared working surface.
Close-up of a large interlocking requirement board being separated by Lin into four manageable pieces; each retains its own distinct shape and one piece is ready to work on independently.
Lin freezes his current setup under a clear protective cover, leaving laptop state, placed tools and model exactly in position; his hand clips a snapshot sheet to the side, warm stillness.
Lin rehearses an entire workflow on a paper-and-cardboard dummy device with the real laptop visibly unplugged and closed; practical simulation, clear cable end, no electric glow.
Calm portrait: Lin closes the debugger lid, releases the switch and sets his pen down, a previously jagged trace settling into a straight quiet line; clear voluntary pause.
Two people exchange Lin's annotated notebook at a doorway, Lin's finger points to one folded corner and highlighted diagram while the recipient follows; hands physically contact separate safe edges.
Low tabletop view of Lin submitting two separate completed sections into adjacent trays in sequence; the first is already accepted, the second in his hand, remaining work stays on desk.
Lin carefully untangles several real cords connecting book-shaped modules, removing one redundant loop while keeping useful connections intact; a simple central knot clearly becomes open.
Macro of Lin applying a small copper repair patch across a cracked prototype joint; the original structure remains, the temporary patch visibly restores the connection, teal cuff and steady natural fingers.
Celebratory but contained portrait: Lin joins two independently built test systems and the entire linked route illuminates teal and warm gold, a small successful indicator at their shared interface.
''',
'P02': '''
Three-quarter portrait of Xu opening a fresh research notebook under a library lamp; one seed-like lavender question light rises from the blank first spread while selected source books wait nearby. A clear beginning.
Xu's round-glassed face appears between library catalog drawers as her hand pulls the one matching color-tabbed index card; an organized search path leads from drawer to nearby book stack.
Intimate overhead view: Xu extracts a small geometric observation from an open source book into her pocket notebook with a pencil; two small corresponding marks and a bookmark make reading notes specific.
Lecture-room side view: Xu quietly listens from a rear seat with her notebook open, the lecturer's different subject apparatus softly visible; her own research book lies beside the new listening notes.
Xu places an original manuscript and its clearly matching second copy into separate protective folders on opposite sides of the desk; distinct physical backup, not just two unrelated books.
Close view of two open research books connected by crossing violet citation ribbons; Xu checks matching geometric evidence in both and clips a reference slip at each end, visibly cross-referencing.
Xu shares a loosely bound draft manuscript across a library table before formal binding; curled rough page edges and unfinished tabs distinguish a usable preprint, with attentive recipients softly behind.
Focused close portrait: Xu checks the final bound manuscript page by page, neat aligned violet tabs, one last proofreading magnifier and pen. No missing sheets, calm final-version verification.
Low-angle still life of three different evidence models supporting one stable translucent conclusion shape above Xu's open book; her hand tests one support, rigorous multiple grounds for an argument.
Xu writes field observations into a small well-used research journal on a campus bench; tucked leaf, sample sketch and colored tabs suggest accumulated research notes, relaxed natural posture.
An opened book becomes a low paper doorway revealing a softly lit campus research problem beyond; Xu's pen introduces the subject at the near edge. A beginning and context, not a final solution.
Top-down research spread of Xu arranging a concise sequence of paper tools, experiment setup and arrows on an open notebook; a visibly repeatable method, precise hands and lavender step markers.
Xu studies a clear result display made of three unequal paper columns and matching colored observation tokens above an open chapter; completed measurements take center stage, no textual data.
Two contrasting violet and blue argument ribbons curve out from Xu's open book toward a shared central discussion space; Xu considers both with open palm, multiple interpretations still visible.
Overhead view of several source books opened like petals around Xu's central review notebook; matching violet tabs form a coherent synthesis ring, her pencil gathers the connections inward.
Low close view of the last page of Xu's notebook: several distinct evidence threads converge to one clean lavender seal-like geometric endpoint, her pen finishes calmly and the book is ready to close.
Xu physically swaps two tabbed chapter bundles in a ring binder while the other chapter stays fixed; clear reordered stacks and one curved movement arrow, close hand-and-page composition.
Over-shoulder scene: Xu traces the branching structure of a fold-out outline, a long bookmark marking the current section; the active branch brighter than the remaining plan, no words.
Morning library portrait of Xu at her familiar seat with the same tea, notebook and orderly book stack; repeated window shadows and a worn bookmark express a settled research habit.
Xu and two distinct adult classmates lean around a single research model in focused discussion, each contributes one colored source slip; indigo-violet threads combine above the model without crowding faces.
Xu turns away from a crossed-out old topic sketch and opens a fresh notebook toward a different research object; old work carefully retained to one side, clear pivot rather than starting with no history.
A layered stack of source books fans out behind Xu as she organizes their violet bookmarks into one comprehensive literature map on the table; the range of sources is visible, central synthesis orderly.
Xu revisits earlier completed chapter pages laid in a curved sequence, illuminating a previously faded connection with her pencil; a quiet backward look through established work, not new chapter deployment.
Tight portrait with book and notebook: Xu slowly reads a complex geometric paragraph-diagram and redraws its meaning in a simpler new arrangement, equivalent content visibly rephrased rather than copied.
Macro of Xu's open notebook with an intentional broad clean gap between dense research diagrams; a ribbon bookmark rests beside the breathing space, quiet lavender light emphasizes deliberate white space.
Xu transfers one violet citation thread from a source book to a differently arranged diagram in her own notebook, same colored evidence retained but presentation changes; close hand-and-page study.
A library copier produces a duplicate chapter bundle matching the original held by Xu; original and copy clearly side by side with identical violet tabs, paper exits naturally from a single output slot.
Xu submits a coherent slim working draft to a faculty tray while incomplete optional appendices remain safely at her desk; main structure finished, practical early usable submission, expression steady.
Overhead editorial view of Xu shortening one overlong chapter bundle and adding sheets to a short one, creating balanced section heights; paper lengths, scissors and binder communicate changed scope.
Xu builds a compact summary spread from the completed portion of her research, folding selected chapter sheets into a stable small model while remaining blanks lie behind; a clear intermediate milestone.
Xu sorts scattered observation slips into a structured index box, each slot with a distinct color tab; her notebook receives the final organized bundle, clean close foreground and quiet library depth.
Xu rests between classes at a sunlit corridor window, closes her book gently and stretches her fingers beside a tea cup; navy-violet outfit recognizable, unhurried small recovery moment.
Xu places a simple acoustic screen between a noisy blurred corridor and her calm desk, one focused lamp illuminating the notebook; distracting colored fragments remain outside the protected study area.
Macro of Xu leaving extra blank page space around a central research layout and a spare bundle of clean sheets at the notebook edge; physical safety margin, not an overflowing overloaded desk.
Side portrait of Xu alone at a board, independently rearranging geometric paper argument pieces with her pencil held at her side; a clear logical path emerges from her own reasoning.
Quiet wide library nook with Xu alone beneath a single lamp, one specialized open book and a small violet-tabbed notebook, background shelves subdued; topic-focused individual self-study.
Dynamic desk close-up: Xu urgently assembles and clips a manuscript toward a nearly empty hourglass, directional paper movement and controlled tense face show a deadline rush, anatomically sound hands.
Night-to-dawn library scene: Xu remains awake at her manuscript, warm lamp against cool first morning light and a water glass; tired but natural eyes, long sustained effort without grotesque exhaustion.
Xu gathers loose research sheets, source slips and notebooks into one complete material packet, both hands closing the stack toward its center; missing pieces visibly collected from across the desk.
Xu opens a carefully packed campus bag showing spare pens, an intact backup folder, tabbed reference book and notebook; she is ready before work begins, calm prepared smile in the upper background.
''',
'P03': '''
Sharp three-quarter portrait: Shen's pen exposes the weak central premise in an interlocked paper puzzle, one seam opens to admit a plum beam; his upright neck and direct questioning gaze are clear.
Macro through a magnifying lens: Shen circles one suspicious discrepant green node on a page with a purple ink ring, neighboring nodes remain unmarked; exact circled doubt dominates the composition.
Shen patiently checks a long row of related evidence slips against the same source book, a continuous forest-green trail links successive checks; side-on desk view communicates sustained scrutiny.
Top-down field notebook recording an observed object's changes across several successive sketch frames, Shen adds the latest evidence slip to the chain; tracking over time, no readable dates.
A forest-green ink drop spreads along the fibers of a research diagram to several neighboring nodes, Shen's steady pen guides attention; controlled evidence erosion of a problem, never poison on a person.
One small doubtful ink spot produces several secondary rings around different nearby claims on a paper model; Shen watches thoughtfully through a lens, the branching questions clearly multiplying.
Shen checks a predicted result on a scratch sheet before the main mechanism finishes, compare actual setup and advance calculation side by side; a stopped hand-sized timer reinforces ahead-of-time checking.
Close-up of Shen overlaying a transparent tracing sheet on an earlier marked diagram, old green and new plum evidence traces visibly offset; compare retained marks rather than erase history.
A narrow green evidence thread passes through the small openings of layered paper argument shields to reach their hidden center, Shen's evidence card in foreground; penetrating support, not bodily attack.
Dynamic over-shoulder portrait: Shen rapidly unfolds a layered paper mechanism under a moving magnifier beam, successive internal structures revealed along one strong diagonal, accelerated analysis with clear materials.
Shen quietly places an unopened follow-up evidence envelope behind the current argument sheet, a plum thread links its corner to an unresolved gap; a prepared next question waiting to trigger.
Tight conversational portrait: Shen raises one short counterpoint with a restrained open hand and a single hooked plum ink arc returning to the central diagram; concise rebuttal, calm face and upright neck.
Close view of Shen turning one book page to uncover a matching independent source slip beneath, the two geometric evidence shapes agree; natural two hands, page edge and corroboration are the focal point.
Side-angle desk scene: Shen's pen follows a source page line by line with a narrow reading ruler, stopping at successive small suspect diagram blocks; methodical phrase-by-phrase interrogation, not random scribbling.
Shen holds one central question card steady while distracting side branches fade around it; his gaze and pen remain anchored to the same main gap, firm focused composition.
One opened index drawer pulls a chain of related library cards into view across adjacent drawers, Shen follows the linked references with a magnifier; a clear retrieval cascade along the diagonal.
Two differently colored ink drops meet on one evidence diagram, their green and plum fronts cross and form a larger reaction boundary; Shen's separate marked source slips at the corners show cross-contamination of claims.
Shen reopens a previously closed paper question ring with a second distinct evidence card, two successive plum arcs point to the same gap; the follow-up question is visibly additional.
A collected cluster of independently checked evidence slips focuses into one bright green-plum burst that breaks apart a faulty paper argument model; Shen's calm pen directs it, no people struck or explosive fire.
Macro of one tiny ink reaction successively enlarged through two handheld study lenses, green-plum rings becoming clearly larger toward foreground; Shen's face stays natural behind, reaction amplification unmistakable.
Shen removes one unsupported paper brace from a grand argument tower, its inflated silhouette diminishes while sound supports remain; a restrained green-plum academic metaphor for weakening rhetorical force.
Close view of Shen separating successive layers of a folded paper shield to expose a fragile inner join, fingers grasp safe separate edges; dismantling defenses as argument analysis, no weapons.
Shen lifts an opaque cover from the base of a paper conclusion model, revealing every hidden supporting assumption in bright neutral light; audience silhouettes at a distance, clear transparent premises.
Gentle waist-up conversation: Shen asks a classmate about a small questionable evidence card with relaxed open palm and a mild attentive expression; soft plum question arc, no aggression or looming posture.
Two distinct paper argument models meet at the center of a debate table in a crisp green-plum collision of ink ripples; Shen and another adult face each other calmly, intellectual clash without violence.
Three differently shaped evidence slips form a stable combined triangular support beneath one conclusion model, green, plum and pale gold paths reinforce each other; Shen fits the final piece in place.
Overhead view of Shen separating a tangled mixed claim into two clearly distinct strands laid left and right, revealing their exact point of disagreement in the center; both positions remain intact.
Shen adds a larger observation lens and a still-running hourglass beside an already watched evidence model, long gentle green trace extends the viewing interval; deliberate prolonged observation, no changed subject.
Shen turns a ring-shaped study light around a many-sided evidence model, exposing previously hidden flaws on all sides; wide desk scene with sources arranged in a circle, comprehensive interrogation.
Shen advances one small supported step at a time across a diagram path, pencil checks a brace before placing the next tile; patient forward posture and a measured green pulse convey caution.
Reflective portrait of Shen untangling a scribbled thread cloud into three simple parallel idea paths above his notebook; shoulders relaxed, head above neck, breathing room returns around the face.
Shen and a classmate gently put their pens down on a debate table and clip the unresolved issue aside, both lean back calmly; a paused plum argument loop and quiet tea establish postponed debate.
Two observers see the same simple evidence model clearly after Shen removes a frosted transparent sheet between them; distorted outlines align, shared understanding and open expressions show a misunderstanding cleared.
Shen turns back to an earlier notebook page, one old overlooked sketch now lit in green beside the current evidence; close reflective view, distinct old page fold and new light.
Strong close-up: Shen points directly at the single decisive joint in a complex claim diagram, peripheral branches fall quiet; precise short gesture and crisp highlighted central point convey stating the key issue.
A still-glowing freshly revealed evidence card is immediately followed by Shen's poised pen and another question slip; warm plum-green residual reaction links directly into the next inquiry.
Shen carefully tabs an unresolved evidence packet inside a defense folder, closing it for a later answer while leaving its prominent violet bookmark visible; future response deliberately reserved.
Soft evening portrait: Shen releases a tightly knotted evidence thread from his fingers and sets the contested card down, relaxed shoulders, unclenched hand and open notebook convey letting go.
Shen revisits a laid-out investigation route and retrieves a tiny overlooked source slip from under a book, a new green connection returns it to the record; clear retrospective evidence recovery.
Top-down recipe notebook of academic ink experiments: small sealed green and plum ink bottles, dropper, evidence swatches and reaction diagrams neatly organized around Shen's notes; distinctive violet cuff pocket cue, no chemical harm.
''',
'P04': '''
Natural dorm desk scene: Tang's roommate catches a slipping stack of study material while Tang continues holding the project board; the helping hand visibly prevents a mishap, friendly relieved expressions.
Overhead view of Tang placing distinct colored task slips into separate teammate trays on a clipboard plan, clear assigned lanes and a shared starting point; red lanyard visible at the edge.
Tang and one different adult teammate each solve one separate paper problem on the same broad table, two distinct writing hands and two task sheets; equal independent contributions, calm side-by-side composition.
Tang receives a stack of color-tabbed source books from a classmate carrying a reference folder; Tang takes the upper book while the classmate supports the rest, clear useful material handoff.
Tang points to a division line between two sets of project modules on a shared board while two teammates select their own tools; visible boundaries and distinct responsibilities, warm three-quarter scene.
Tang aligns two teammates' differently paced progress tracks by shifting a central connecting tile, both contributors look toward the shared next step; coordination through one readable practical gesture.
Tang shows a partly completed campus model to teammates, completed sections warmly lit and unfinished ones still open; her clipboard and measured presentation establish a genuine intermediate progress report.
Tang and a consistent short-haired adult project partner fit complementary parts of one tabletop campus model, each has a separate tool and natural hand position; real paired project work, no duplicated Tang.
Close view of Tang and a teammate placing their completed sheets into the same submission folder together, both pages align and one clip closes them; two people combining work at the final hand-in.
Wide study-room view of Tang and three distinct teammates around one central project, everyone leans toward a different evidence sheet; coral and teal connections form a coherent shared discussion circle.
An empty teammate chair and abandoned tool leave a clear gap; Tang steps into that spot and takes up the needed tool to keep the small assembly moving, temporary replacement rather than general supervision.
Tang hands an active clipboard to the incoming teammate while the outgoing teammate sits down behind, three seats form a rotation arc; visible replacement order, relaxed realistic elbows and wrists.
Tang and one teammate walk side by side pushing a low cart of project materials through a campus corridor, equal shared effort and aligned direction; medium low-angle scene, natural weight and hands.
Close view of a notebook exchanged between outgoing and incoming teammates, Tang points to one key folded corner before releasing it; clear transfer notes with both holders' fingers anatomically separate.
Tang takes a heavy book stack from a tired teammate and guides them toward a nearby resting chair and water cup; warm considerate face, genuine load transfer and no impossible twisted wrist.
Study-room rotation: a fresh teammate reaches forward from the next seat as Tang passes them a support folder, previous helper resting in background; timely rotating assistance, one active handoff focal point.
Three different hands pass one sturdy study baton-pen in a smooth relay sequence around Tang's clipboard; each hand belongs to a visible distinct adult, small repeated coral arcs suggest a measured beat.
Top-down circular scheduling board with three evenly spaced color tokens and alternating active/rest chair symbols, Tang moves one token into a balanced empty slot; sensible shared work and rest, no textual timetable.
Tang and a replacement teammate compare the handoff notebook with the actual tools and model before one releases the clipboard; two pointing fingers verify the same important detail, mutual confirmation.
Tang's team performs complementary tasks at one table in coordinated rhythm, paper handoff, assembly and checking align along a coral-teal loop; distinct natural poses rather than identical raised arms.
Tang and a classmate explain one exam concept to each other across open books before entering the exam room, two-way gestures and a pair of matching idea lights; mutual teaching before solo assessment.
Tang studies alone as several colored team method tiles reorganize into a clear inner notebook structure, former group-work traces become her own coherent reasoning; no ghost bodies or summoned classmates.
Tang independently rehearses a familiar project at an otherwise empty study table, extra chairs visible but unused; her own two hands perform the full process with a small practice model.
Exam desk overhead: Tang selects the most familiar of three different geometric problem sheets first, pen immediately begins on that one while harder sheets wait aside; deliberate easy-first strategy.
Tang alone compares two completed drafts with a checking ruler, her own reflection only faint in a window; independent review with teal internalized method lines, no helper doing the work.
Tang spreads one shared resource packet at the center of a study table so three teammates each receive the relevant section; hands reach separate sections safely, a clear communal source.
Tang and teammates place their different finished modules into one project submission box, each contribution has a distinct shape; the assembled group deliverable is focal, natural restrained smiles.
Tang works alone on an integrated multi-part assignment, former separate colored task lanes now form one efficient connected route in her notebook; internalized division of work, not a new group meeting.
Tang and a teammate look back over a completed model and exchange a small knowing nod, their familiar colored tools side by side; quiet recalled coordination, not a high-five spectacle.
Tang alone hands a finished complete exam booklet to the invigilator's tray, classmates absent from her working area; steady posture and a warm distant trail of learned methods, unambiguous independent submission.
Tang and two teammates set their progress tokens on the same agreed line of a shared board, three different hands and one common milestone; an explicit agreement on pace.
Tang explains a solution using a simple paper model in one hand and a relaxed open-palm gesture with the other, teammate listens closely; clear communicative thinking, no impossible finger directions.
Tang and teammates revisit their completed model from above, three earlier decision points relight as they trace the process together; joint retrospective, project remains intact rather than under new construction.
Tang keeps a contrasting-color suggestion card visible at the side of the consensus board without discarding it, thoughtful expression and open discussion space; a preserved dissenting opinion.
Four distinct adult teammates, including Tang, each bring a differently shaped idea slip to a round table, equal space and lively but natural expressions; multiple voices coexist before selection.
Overhead view of Tang swapping three differently colored task bundles between work lanes, correcting an overloaded side so the arrangement balances; hands rearrange physical tasks clearly.
Tang and a teammate exchange a small urgent message slip across a short corridor at the right moment, both faces attentive, a quick coral-teal link closes their information gap.
Tang takes over one manageable portion of a tired teammate's load while another offers a water cup; mutual consideration, realistic balance of books and hands, warm friendly expressions.
Close view of Tang deliberately leaving an empty buffer interval between two batches of task tokens on the schedule board, hourglass still has sand; unfilled space protected by her resting hand.
Tang and two teammates place the last complementary piece onto a shared campus project model, three contributions meet around one warm milestone light; pride in a common finished achievement.
''',
'C': '''
Warm close campus study scene with Lin actually writing an assignment at a desk, notebook page with simple problem diagrams, pencil contacting paper and an orderly small book stack; focused daily work, no magical machine.
Medium side portrait of Shen comfortably stretching both arms upward away from his study desk, spine relaxed, shoulders and elbows naturally aligned, eyes softly closed; unmistakable human stretch, no zombie pose.
Top-down view of Xu organizing notebooks, pens and a water bottle into her open campus backpack, each object has its own compartment, both hands pack naturally; the bag itself dominates.
Quiet portrait of Tang drinking from a clear water glass at a study table, pen set down, light catching the water and relaxed shoulders; drinking and readjusting, clear cup-to-mouth anatomy.
Wide gentle late-afternoon scene of Lin and Xu walking on the campus running track beside grass and trees, natural mid-stride legs, books put away; easy restorative walk, no competitive sprint.
Top-down morning desk scene of Tang creating today's simple checkbox checklist on her clipboard, a few concrete books and tools beside it; intentional daily planning, warm fresh daylight.
Close view of Xu making a final inspection of a completed assignment before sliding it into a submission folder, last checkbox-shaped mark ready and timer near its end; completion already achieved.
Wide doorway composition of Tang finding an empty sunlit self-study room, one open seat and desk visible inside, her hand on the doorway and notebook ready; finding a usable quiet room, no readable sign.
Macro of Shen drawing a strong purple ring around the single key diagram on an open assignment page; surrounding shapes muted, pen point touching the ring, precise highlighted important point.
Lin calmly negotiates a little extra time with a teacher across a desk, open hand beside a still-running hourglass and unfinished task stack; a small additional empty time segment lit copper.
Lin removes a tangled cable and an obstructing pile from the path of his task model, cleared central route now continuous; concrete obstacle removal before work, no weapon or physical conflict.
Overhead view of Tang dividing a broad pile of assignments into three manageable trays and finishing one small batch at a time; first tray done, second active, third waiting, unmistakable batch processing.
''',
'T': '''
Xu publicly presents her complete research manuscript on a campus seminar lectern, a coherent lavender solution structure unfolds above the finished bound pages; attentive adult audience softly behind, successful publication not merely writing.
Close side view of Xu attending another subject's lecture and capturing its key geometric insight in a small temporary notebook, two distinct subject colors meet at the page edge; listening notes, no full research submission.
''',
}


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    design = json.loads((ROOT/'artifacts/redesign-20261030/campus-cards-v3.json').read_text(encoding='utf-8-sig'))
    definitions = {c['id']:c for c in json.loads((ROOT/'data/four_year/definitions/cards.json').read_text(encoding='utf-8-sig'))}
    enabled = json.loads((ROOT/'data/four_year/manifests/campus_four_year.json').read_text(encoding='utf-8'))['enabled']['card']
    names = {c['id']:c for c in design['cards']+design['tokens']}
    refs = json.loads((OUT/'references/manifest.json').read_text(encoding='utf-8'))
    config = json.loads((Path.home()/'.codex/imagegen/config.json').read_text(encoding='utf-8-sig'))
    scenes = {k:[s.strip() for s in v.splitlines() if s.strip()] for k,v in SCENES.items()}
    assert {k:len(v) for k,v in scenes.items()} == {'P01':40,'P02':40,'P03':40,'P04':40,'C':12,'T':2}
    entries = []
    counters = {k:0 for k in scenes}
    for cid in enabled:
        card = names[cid]
        group = 'T' if cid.startswith('R3-T') else card['owner']
        subject = scenes[group][counters[group]]
        counters[group] += 1
        entries.append({'card_id':cid,'name':card['name'],'owner':card['owner'],'group':card.get('group','论文衍生'),
                        'base_text':card['base'],'upgrade_text':card.get('upgraded',''),
                        'exam_text':card.get('exam',''),'definition_sha256':hashlib.sha256(json.dumps(definitions[cid],ensure_ascii=False,sort_keys=True).encode()).hexdigest(),
                        'scene':subject,'image_path':f'assets/cards/v3/{cid}.png'})
    groups = [(owner,[e for e in entries if e['owner']==owner and not e['card_id'].startswith('R3-T')]) for owner in ['P01','P02','P03','P04']]
    groups.append(('C',[e for e in entries if e['owner']=='C' or e['card_id'].startswith('R3-T')]))
    batches=[]
    for owner, cards in groups:
        for offset in range(0,len(cards),8):
            bid=f'{owner}-{offset//8+1:02d}'
            lines=[
                'Use case: illustration-story. Asset: ONE atlas containing EIGHT DIFFERENT finished campus game card illustrations.',
                'The uploaded image is an IDENTITY and PAINTED LINEWORK reference only. Draw all NEW scenes described below. Do not copy the reference layout, standing pose, full-body cutout or beige background into every scene.',
                'Exact canvas 1024x1536. Strict 2 columns x 4 rows, each cell 512x384, read left-to-right then top-to-bottom. Eight equal separate landscape 4:3 pictures. Fill all canvas: no outer margin, gutters, grid lines, panel numbers or borders. Cell boundaries at x=512 and y=384/768/1152; keep them exact.',
                STYLE,
                'Character and motif direction: '+IDENTITY[owner],
                'Vary camera framing as assigned: portraits, real hand-and-prop close-ups, overhead arrangements and room views. Each scene must visually communicate its particular Chinese card title through a literal action or specific object relationship. Titles below are semantic instructions, NOT text to render.',
                'Inside EACH cell keep all faces, important hands and decisive objects within the central 70% of width/height. 16px left/right and 12px top/bottom of EACH cell will be discarded. Outer edge background is expendable. No body, object, ribbon or shadow may cross a cell boundary. Distinct scene backgrounds, not eight detached cutout poses.',
                'Natural adult proportions, continuous upright neck and shoulders, anatomically plausible wrists, exactly two arms per person, solid object contact. Keep the formal face, hairstyle, glasses and clothing identity. Avoid repetitive standing pose, elongated legs, stiff zombie gestures and identical cloned teammates.',
                'No printed title, readable writing, letters, numbers, equations, logos, watermarks, subtitles, speech bubbles, cost symbols or card frames. Pages may contain simple nonverbal geometric sketches. UI renders the real Chinese name and rules later. No gore, weapons or poisoning people.',
            ]
            slots=[]
            for i in range(8):
                row,col=divmod(i,2)
                entry=cards[offset+i] if offset+i<len(cards) else None
                slot={'slot':i+1,'row':row+1,'column':col+1,'card_id':entry['card_id'] if entry else None,
                      'crop':[col*512+16,row*384+12,(col+1)*512-16,(row+1)*384-12]}
                slots.append(slot)
                if entry:
                    extra=' '+IDENTITY['P02'] if entry['card_id'].startswith('R3-T') else ''
                    lines.append(f"ROW {row+1}, COLUMN {col+1} — {entry['card_id']}, title meaning: 《{entry['name']}》.{extra} Draw: {entry['scene']}")
                else:
                    lines.append(f'ROW {row+1}, COLUMN {col+1}: unused slot, plain muted ivory, empty.')
            lines.append('Final verification before output: exactly 2 columns and 4 equal rows; each specific named scene in its assigned cell, no merged cells or extra scenes. Preserve the uploaded formal character identity, but illustrate the requested new actions.')
            prompt='\n'.join(lines)
            pp=OUT/'prompts'/f'{bid}.txt'
            pp.parent.mkdir(parents=True,exist_ok=True)
            if (OUT/f'{bid}.png').exists() and pp.exists() and pp.read_text(encoding='utf-8') != prompt:
                raise SystemExit(f'Cannot change existing output prompt: {bid}')
            pp.write_text(prompt,encoding='utf-8')
            batches.append({'batch_id':bid,'owner':owner,'source_file':(OUT/f'{bid}.png').relative_to(ROOT).as_posix(),
                            'prompt_file':pp.relative_to(ROOT).as_posix(),'prompt_sha256':sha(pp),
                            'operation':'edit','reference_image':refs[owner]['file'],'reference_sha256':refs[owner]['sha256'],
                            'model':config['model'],'provider':config['base_url'],'requested_size':[1024,1536],
                            'quality':'medium','n':1,'slots':slots,'human_acceptance':'pending'})
    assert len(batches)==22 and {s['card_id'] for b in batches for s in b['slots'] if s['card_id']}==set(enabled)
    write(OUT/'catalog.json',{'requirement_id':'UIR-074','count':174,'entries':entries})
    write(OUT/'layout.json',{'requirement_id':'UIR-074','columns':2,'rows':4,'crop_size':[480,360],'batches':batches})
    # This is an edit manifest, deliberately NOT fed to generate-batch which drops image inputs.
    write(OUT/'edit-jobs.json',{'execution':'bundled image_gen.py edit, one request per atlas; actual reference upload required',
                              'concurrency_limit':config.get('workflow',{}).get('batch_concurrency',2), 'jobs':batches})
    (OUT/'style-brief.txt').write_text(STYLE+'\n\n'+'\n\n'.join(k+': '+v for k,v in IDENTITY.items()),encoding='utf-8')
    print(json.dumps({'cards':len(entries),'atlases':len(batches),'first':batches[0]['prompt_file'],'api_calls':0},ensure_ascii=False))


if __name__=='__main__':
    main()
