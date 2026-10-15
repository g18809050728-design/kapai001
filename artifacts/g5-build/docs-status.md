# G5 documentation handoff

Owner: /root/g5_docs. Updated only:

- docs/接口文档.md (v0.5)
- docs/数据库与实体关系设计.md (v0.2)
- docs/G0需求追踪.md

Actual G5 APIs reconciled with current implementation: continue formal only; explicit backup restore and deferred current_run marker cleanup; ProfileView diagnostics; SessionView.profile_commit_status; SettingsPatch or Dictionary; all three missing-formal/backup preservation rules; Profile completed_runs; saved_at alias of written_at; inspect_backup; explicit migration has no disk writes and no implicit GameSession migration. Removed old G5 ENGINE_NOT_READY / files not supplied / schema not implemented claims.

No code or tests changed. No root plan, README or G5 execution record changed; main owns those.

Formal G5 verification is still pending at this handoff. Root should replace `正式证据待登记` cells in G0需求追踪.md with a link to its final G5 execution record after successful verification; update first paragraph and closing paragraph from `进入正式验收` to passed then. Interface/database states deliberately refer to root plan for formal acceptance, so they do not need a second speculative pass. Run the main G0 document checker after final root documentation updates.

No new local links were introduced. Targeted stale-claim search removed all old claims that G5 modules/files/schema are absent. Remaining ENGINE_NOT_READY text explicitly documents the retained historical constant, not current behavior; `未提供路径` describes a real migration rejection, not missing implementation.

Memory used only for stage order/UI deferral: MEMORY.md lines 27-40; rollout 01a139e5-f9cc-7923-a350-b3aacc0dd820. Current implementation was verified from on-disk source after CodeGraph; old documentation-only snapshot was not reused as a current fact.
