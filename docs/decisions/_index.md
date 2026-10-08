# decisions/

Decision records: a decision was *taken* (or, more often here, *not taken*) for a reason that needs to outlive the conversation. Each one holds until something changes — its **Revisit if** section names what would. Read the record before re-suggesting the change it covers. Revisiting one is welcome when its conditions are met, or when new work makes a better case. Update the record, or add a superseding one, in the same PR.

- [0001-defer-cycle-protocol-seams.md](0001-defer-cycle-protocol-seams.md) — keep concrete cycle collaborators + `skip*ForTesting` flags instead of extracting `Transcriber` / `AudioCapture` / `HotkeyInput` protocols; revisit when a second adapter appears or skip flags spread further.
- [0002-log-redaction-over-debug-flag.md](0002-log-redaction-over-debug-flag.md) — drop the `DICTATION_VERBOSE_LOGS` build flag; log error strings public but path-redacted via `LogRedaction` so field bug reports stay readable without leaking the account name; revisit if a value beyond paths needs conditional logging (prefer a runtime toggle).
