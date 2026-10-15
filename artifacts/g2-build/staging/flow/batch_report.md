# G2 Flow Definition Batch

Status: 16 definitions ready for main-agent G2 package integration. This batch does not change the production manifest, `content_deferred.json`, or G0 scope. Event execution belongs to G4 and is not a G2 content-integration blocker.

## Batch IDs and Sources

All upstream rows are in `docs/交大四年_DDL战争_统一设计文档.md`.

| Kind | IDs | Exact upstream row(s) | Contract mapping |
|---|---|---|---|
| Task | N01, N02, N03, N04 | §9.1 lines 356-359 | `docs/内容层契约.md` §8.1 TaskDef/TaskPhaseDef; §8.2 IntentSpec; `ContentDB._validate_task`, `_validate_intent`; `BattleEngine._execute_intent_skill` |
| Task | Q01 | §9.2 line 375 | Same schema and skill mapping; `independent_answer` comes from the EncounterDef per §8.1 and is consumed in `BattleCardRules._apply_exam_substitution` |
| Task | B01 | §9.3 lines 382, 386 | TaskDef's three ordered phases and §8.1; phase transition in `BattleEngine._advance_or_remove_task` |
| Encounter | N01, N02, N03, N04 | §9.1 lines 352, 356-359, 369 | `docs/内容层契约.md` §8.1 EncounterDef; `ContentDB._validate_definition` and `_validate_enabled_references`; `BattleEngine.begin` |
| Encounter | Q01 | §9.2 line 375 | Same schema; `independent_answer` exam substitution in `BattleCardRules._apply_exam_substitution` |
| Encounter | B01 | §9.3 lines 382, 386 | Same schema; `independent_answer` and `fixed_exam_room` flags are read by BattleCardRules |
| Event | V01 | §10.2 lines 432, 436, 449 | `docs/内容层契约.md` §5, §8.1 EventDef, §8.5 Event EffectSpec; `ContentDB.EVENT_OP_FIELDS` and `_validate_event_options` |
| Event | V03 | §10.2 lines 432, 438, 449; G0 override source `docs/交大四年_DDL战争_项目计划书.md` §3.1 | Same schema; production `card_pool` must be replaced by the frozen override K14/K05/K60, not by changing the full definition |
| Event | V04 | §10.2 lines 432, 439, 449 | Same schema; costs and upgrade filtering are constrained by §5 and §8.5 |
| Event | V10 | §10.2 lines 432, 445, 449 | Same schema; fixed relic duplicate fallback is constrained by §8.5 and §10.2 |

The exact row text and source line references are also embedded in each JSON record under `source.source_row` and `source.source_lines`. The source file hash is recorded in `batch.json`.

## Schema, References, and Operation Audit

- Task rows use only registered TaskDef, TaskPhaseDef, and IntentSpec keys. Their intent operations use registered battle fields: pressure, shield, gain_status, and add_card. N03's `add_card.card` reference is X01 from the separate card batch. The isolated `test_g2_flow` ContentDB package now includes that staged X01 definition and verifies the cross-batch lookup; production-package closure remains pending until the approved production package is assembled and validated.
- Encounter rows use only registered EncounterDef fields and point to their same-ID TaskDef. All six task references are within this batch. N04 preserves the full source terms `[2,3]`; G0 authorizes the production override `[1]` from project-plan §3.1. B01 uses terms `[1]` and only the registered exam flags.
- Event rows use only EventDef, EventOption, and event EffectSpec fields. All four schemas pass. Runtime event choices and transactions are deferred to G4; this isolated flow probe does not claim to exercise them. Main-agent package integration must validate enabled event references after the V03 override.
- V03's full source card pool is K14/K24/K34. Only its G0-authorized production override changes that pool to K14/K05/K60. The staged base definition retains the full pool; K24 and K34 are not added to G0 or production scope.
- V03 `fallback_money` is 20, taken from the existing explicit-pool example in `docs/内容层契约.md` §7.9.2. The source pool remains K14/K24/K34; the integration manifest applies the approved MVP override K14/K05/K60.
- No `test_` ID is used. Staged definitions are wrapped in structured records and are not entries in any manifest.

## Self-Review Results

The staging builder verified each assigned `(kind,id)` against both the G0 baseline and current holdback, matched the source table row against its recorded line, and emitted the exact schema record envelope `{kind,id,source,behavior_refs,definition,status}`. Godot `4.7.2.stable.official.ed1daf0bf` ran `schema_probe.gd` using ContentDB's actual number normalization and per-definition validators: all 16 definitions reported `SCHEMA_OK`, exit code 0. The isolated `test_g2_flow` ContentDB package also loaded successfully, resolved all six task and six encounter definitions (including N03's X01 reference), and confirmed the test N04 override. This does not establish production-package closure, event execution behavior, or battle behavior. `gdformat --check` and Python `compileall` passed. Full command/environment/stdout/stderr/exit/hash bundle: `artifacts/g2-build/staging/flow/final_probe/`.

The first probe attempt used `JSON.parse_string()` directly, which skips ContentDB's integer normalization and produced an invalid harness-level failure for all integer fields. It was corrected to use `JSON.new().parse()` followed by the ContentDB normalizer; the corrected actual validator run passed. The failed attempt is not treated as a content failure or as validation evidence.

Integration handoff:

- Event executor and transaction behavior for V01, V03, V04, and V10 remain G4 work.
- N03's X01 reference is closed only inside the isolated test package; production-package closure still requires the complete approved package and manifest.
- The complete production package must apply and validate the frozen V03/N04 overrides, then load through ContentDB with all referenced definitions enabled.
- The historical `143321` probe overstated event closure because its manifest disabled events. That claim is withdrawn; current closure covers tasks/encounters only. Use the main-agent full-package validation for event closure.

`batch.json` lists input hashes and per-record hashes. Production manifest, G0 baseline, and deferred manifest were read-only inputs.
