# Codec status
Owner: /root/g5_codec (replacement for idle g4_nodes)
Implemented src/run/run_codec.gd and src/battle/battle_codec.gd; RunState.validate(relic_slots=...) and BattleState.validate(unit_slots=...) added. Public API follows shared-api.md. decode accepts plain JSON integer-valued floats via normalization; no mutation of caller.
RunCodec encode_summary(summary)->Dictionary; decode_summary(data)->GameResult(RunSummary).
Typed EventState/ShopState/RewardOffer/TermSettlement are reconstructed explicitly; candidate lists not rerolled. All domain validation precedes typed constructors.
## Complete: focused codec checks passed

Owned files only: src/run/run_codec.gd, src/battle/battle_codec.gd, src/run/run_state.gd, src/battle/battle_state.gd, tests/suites/test_save_codec.gd. All five were formatted with gdformat; final targeted rerun passed.

Command: `F:\GoDot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script artifacts/g5-build/run_codec_tests.gd`.
Godot 4.7.2.stable.official.ed1daf0bf, exit code 0, no SCRIPT ERROR or ERROR, **271 checks; failures=[]**.
Raw output: `artifacts/g5-build/codec-test-final.log`.
Independent entry: `artifacts/g5-build/run_codec_tests.gd`; main still owns formal `tests/run_tests.gd` suite registration.

Real run_flow fixture seed=42 traversed normal/event/shop/elite/rest/boss with BattleEngine. JSON stringify/parse roundtrips covered initial map, active/finished battles, frozen scene results, player/unit/task status holders, frozen rewards including partially resolved offers, events, sold shop stock, used rest and terminal summary. Restored nested objects retain EventState/ShopState/RewardOffer types and are detached. Malformed schemas/content/topology/resources/instances/zones/cursors/intent snapshots/stale holders/pending resolution are refused without input changes.

Quality fixes in final pass: strict four career tracks with same fallback cap=3 as RunNodeService; known ending draft schema; settlement claimed `chosen_id` accepted and checked against candidates; event frozen effect candidate completeness; skipped-only-if-skippable; completed event/rest marker checks; two-way active battle/node agreement; StatusDef target category; required noncard source registry entries. Cards are intentionally not required in source_registry because current BattleEngine does not register them.

## Main integration follow-up

1. SessionState.validate must treat `origin_card_id=""` as a temporary card without a permanent origin. The earlier `origin != null` check rejects legitimate temporary cards; use nonempty check. Not changed by codec owner.
2. Potential preexisting engine issue: `_advance_or_remove_task` removes old task IDs without removing statuses held by those task IDs. Domain codec correctly requires live holders. Main should reproduce with extra_requirements on a completing/phase-changing task and scope the engine fix + regression if confirmed. Not changed by codec owner, and not claimed fixed.

This verifies codec scope only; whole G5 acceptance remains with main and storage/session suites.
