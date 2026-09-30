# Fan-control safety target

This is the mutation boundary, not UI convenience code. `FanControlArbiter` owns manual/agent transactions; `FanControlExclusiveLock` prevents competing writers; `FanControlJournalStore` anchors durable ownership to a secure directory identity; `LocalFanHelperClient` performs allowlisted SMC operations via `PrivilegedFanControlHardware`.

Preserve the complete expected fan set, fresh telemetry, confirmed readback, restore priority and durable recovery state. An unreadable journal is a blocked/recovery condition, not permission to forget ownership. Do not clear a journal or claim Auto restoration merely because an API returned success. Read root `AGENTS.md` and relevant tests before touching this target; no real hardware writes are appropriate for routine documentation or test discovery.
