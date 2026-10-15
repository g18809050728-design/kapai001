# Run service completed
Owned final files: src/run/run_state.gd and src/run/run_service.gd. Other entities are nodes agent implementations.
APIs: create(request Variant, profile Variant = {}), preview(state,draft), apply(state,action,rng_states Dictionary), settle_battle(state,outcome Dictionary,rng_states Dictionary), make_view(state)->Dictionary, rewards(), transactions(), eligible_endings().
create requires explicit manifest_id matching catalog; creates unique run_id with Crypto; init revision caller=0. Snapshots are full Dictionaries.
Verified: editor import exit 0; artifacts/g4-build/run_smoke.gd exit 0 (production catalog direct service route normal->event->shop->elite->rest->boss, 6 completed nodes, rewards claimed, final summary, no boss reward). Does not claim actual battle win; smoke injects service outcomes deliberately.
MVP final reason=first_term_completed; terminal RunSummary returned in RunStep, RunState only outcome. All RunService paths preserve battle stream. gdformat applied to RunState/RunService.
Potential limitations outside MVP: full 8-term career/ending rules not implemented; only generic direction reward settlement exists. Do not claim full game. Profile unlock filtering only if profile.unlocked_ids is nonempty.
Main agent can now integrate GameSession + G4 fixtures / evidence. Parent owns formal tests/docs.
