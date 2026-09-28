# The Loop

- Tracking starts with the first successful deployment snapshot. `added` means
  first observed, not newly issued; launch rows set `is_initial_snapshot`.
- The source has no stable record ID. The ID hashes normalised premise name,
  address and commencement date. Key corrections can therefore appear as a
  removal plus addition.
- The eight descriptive register fields are required. The source CSV also
  publishes latitude and longitude; these remain nullable and are not geocoded.
- `exemption_variation` entered the source schema on 2026-07-30. It is tracked
  in `record_hash`; the first accepted snapshot therefore marks all continuing
  records as updated. Earlier history rows retain `NA`.
- `history` appends every accepted scheduled observation, including unchanged
  rows; run-partitioned `snapshots` and `raw` files are immutable.
- A disappearance is `expired` only when observed after the published
  conclusion date. Otherwise it is `removed_early`.
- Input validation happens before current/history writes. Rejected bytes and a
  rejected manifest row are retained for diagnosis.
- The public dashboard deploys only after a completed tracker run. Its
  generated JSON contains published register observations and accepted change
  events, never Azure credentials. The first snapshot is a baseline, not
  enforcement newly issued that week.
- Local archive preview uses sparse Internet Archive captures plus a live CSV.
  It does not backfill the tracker or infer events between capture dates.
