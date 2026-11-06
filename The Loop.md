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
- Each scrape appends raw bytes, headers and one validated snapshot. Mutable
  current/history/changes/manifest tables are no longer used or updated;
  existing Azure files remain untouched.
- Export keeps the latest whole snapshot per Sydney date, with descending run
  ID as the tie-break for equal timestamps. It combines daily snapshots and
  derives changes. Deduplication never collapses an order across dates.
- Available validated snapshots define coverage. No hard-coded launch date or
  minimum date count is required. The earliest retained date is a baseline.
- A disappearance is `expired` only when observed after the published
  conclusion date. Otherwise it is `removed_early`.
- Input validation happens before a snapshot is saved. Rejected bytes and
  response headers are retained for diagnosis.
- The public dashboard rebuilds history and event classifications from
  immutable snapshots, never the corrupted mutable history/change tables.
  It deploys only after a complete export and never publishes Azure credentials.
  The first snapshot is a baseline, not newly issued enforcement.
- Local archive preview uses sparse Internet Archive captures plus a live CSV.
  It does not backfill the tracker or infer events between capture dates.
