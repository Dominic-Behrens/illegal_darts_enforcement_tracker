# The Loop

- Tracking starts with the first successful deployment snapshot. `added` means
  first observed, not newly issued; launch rows set `is_initial_snapshot`.
- The source has no stable record ID. The ID hashes normalised premise name,
  address and commencement date. Key corrections can therefore appear as a
  removal plus addition.
- The eight descriptive register fields are required. The source CSV also
  publishes latitude and longitude; these remain nullable and are not geocoded.
- `exemption_variation` entered the source schema on 2026-07-30. It is tracked
  in `record_hash`; earlier snapshots retain `NA`.
- Until 2026-09-28, Azure HEAD incorrectly waited for a body, returned false,
  and caused mutable `history` and `manifest` to reset each run. Immutable
  run-partitioned snapshots remain the recovery source. The corrected HEAD
  now preserves history on later runs; prior rows need reconstruction.
- A disappearance is `expired` only when observed after the published
  conclusion date. Otherwise it is `removed_early`.
- Input validation happens before current/history writes. Rejected bytes and a
  rejected manifest row are retained for diagnosis.
- The public dashboard rebuilds history and event classifications from
  immutable snapshots, never the corrupted mutable history/change tables.
  It deploys only after a complete export and never publishes Azure credentials.
  The first snapshot is a baseline, not newly issued enforcement.
- Local archive preview uses sparse Internet Archive captures plus a live CSV.
  It does not backfill the tracker or infer events between capture dates.
