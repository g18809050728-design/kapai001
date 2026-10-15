# Store owner READY - tested 2026-10-15

g4_nodes completed SaveStore, ProfileMerge and test_save_store (latest nodes-followup.md reassigned store ownership). Main may integrate these files now. Do not assign store files to g4_rewards concurrently.

Targeted actual command: `F:/GoDot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://artifacts/g5-build/run_store_tests.gd --quit-after 120`; exit code 0. Evidence: `artifacts/g5-build/store-tests.log`. Editor import also exited 0; `store-import.log`.

Covered real filesystem save/load/previous backup, inspect corruption diagnostics, no implicit fallback, fixed slots, caller immutability, bad checksum, fail_write, truncate_temp, fail_after_backup and fail_rename; all retain old valid formal/backup. Profile tests cover exact retry, conflicting summary rejection, input immutability, derived count and unlock unions/tutorial flags. No G4 rerun. Main retains formal G5 acceptance and full session integration.

Integration caveat: GDScript `some_dictionary.new_key = ...` creates a StringName key; JSON contracts require String keys. Use `["new_key"]` for new keys in persisted dictionaries (existing String keys are safe). This was the only behavior correction needed in the test fixture.

API follows shared-api.md. SaveStore will return existing SaveReceipt with slot/revision/checksum/written_at; the docs call timestamp saved_at but current DTO only defines written_at. Main may add a saved_at alias if desired. inspect and inspect_backup return dictionary metadata.

Profile shape: unlocked_ids: Array[String], seen_content_ids: Array[String], tutorial_flags: Dictionary[String,bool], summaries_by_run_id: Dictionary[String,summary Dictionary], completed_runs: int. Exact repeat summary is idempotent; conflicting summary for same run_id is SAVE_CORRUPT. Summary consistency comparison uses SnapshotCodec.canonical_json.

Filesystem algorithm: validate caller snapshot -> write/flush tmp -> reread integrity -> copy old valid formal through verified backup temp -> preserve existing backup when old formal invalid -> replace formal -> restore valid backup on failed rename. Only fixed current_run/profile/settings slots accepted.
