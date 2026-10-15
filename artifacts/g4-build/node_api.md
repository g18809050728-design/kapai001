# G4 node helper API

Agent g4_nodes receives empty Payload in incoming collaboration messages; use this file for shared coordination if needed.

Already created entities: RunMap, RunNodeState, EventState, TermSettlement, RunSummary, RunStep. All child entities expose create(Dictionary), copy(), copy_for_write(), to_dictionary(). RunMap.build(run_id, term_count) returns Array[RunNodeState]. g4_run owns RunState.

Implementing src/run/run_node_service.gd as RunNodeService.new(content_db):

- enter_event(state: RunState, node: RunNodeState, rng: RandomSource) -> GameResult<EventState or null>. Returns null if no unseen legal event. On success records seen_event_ids and freezes option/effect candidates in EventState; caller stores node.context.event.
- choose_event(state: RunState, payload: Dictionary) -> GameResult<RunState>. Copies state, finds current event node, checks instance/option/targets/cost, returns the updated copy. No RNG consumption.
- take_rest(state: RunState, payload: Dictionary) -> GameResult<RunState>. Copies state and applies the rest option once.
- event_view(state: RunState, node: RunNodeState) -> Dictionary.
- rest_view(state: RunState, node: RunNodeState) -> Dictionary.

Caller RunService emits RuleEvents and handles death finalization if returned vitality is 0. Helpers do not advance battle/map except enter_event's map selection; enter_event's random rarity candidates advance reward only. Event and rest copies keep unrelated published state untouched.

## Ready 2026-10-15 15:50

Implementation is ready. Node event context key is `event` (EventState object); rest uses `used` and `option_id` directly in context. `choose_event` returns a RunState copy, and `take_rest` returns a RunState copy; caller should replace its working state with result.data.

`tests/suites/test_run_nodes.gd` passes under Godot 4.7.2; standalone runner is `artifacts/g4-build/run_node_tests.gd`, output `node-tests.log`. It covers frozen 8-node map branches, forced V03 approved candidates, map/reward no advancement for deterministic candidates, event failed-target rollback, payment+delete, repeat rejection, typed context deep copies, rest heal/upgrade/repeat/non-cooperation rejection. Root should add this suite to the full test runner.

Additional production paths passed: V01 frozen blue-card selection and white relic, V04 vitality payment plus work-card upgrade, V10 A15 grant and declared 20-money duplicate fallback; event resolution leaves all RNG streams unchanged. Relic fallback counts missing items when count > available candidates.
