# G5 documentation handoff

Task for g5_codec: read this task if tool message arrives empty. Codecs are done; please now synchronize ONLY docs/接口文档.md and docs/数据库与实体关系设计.md to implemented G5. Read agent.md and root plan first. Main owns all other documents/code and formal verifier.

Inspect actual src/app/game_session.gd, src/storage/*.gd, DTOs and codecs. Update interface v0.5 and storage v0.2, removing current ENGINE_NOT_READY/storage-unimplemented statements (retain genuine future UI/full-version limits). Explain exact envelopes, profile completed_runs, profile/settings manifest_id markers, SaveReceipt saved_at with written_at alias, ProfileView new fields, SessionView.profile_commit_status, Dictionary or DTO settings patch, three-step partial persistence statuses, explicit backup restore preservation, missing formal with backup guard, migration explicit copy-only. Document actual behavior, not planned behavior. G5 formal verification is pending; don't claim whole-stage pass or invent run IDs. No code/test edits.

Use source/contract mapping efficiently; finish these two docs and write artifacts/g5-build/docs-status.md. No need to send questions. Prefix visible replies oh my honey.
