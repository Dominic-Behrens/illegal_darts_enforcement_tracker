# The Loop

- Tracking starts with the first successful deployment snapshot. `added` means
  first observed, not newly issued; launch rows set `is_initial_snapshot`.
- The source has no stable record ID. The ID hashes normalised premise name,
  address and commencement date. Key corrections can therefore appear as a
  removal plus addition.
- The seven descriptive register fields are required. The source CSV also
  publishes latitude and longitude; these remain nullable and are not geocoded.
- `history` appends every accepted scheduled observation, including unchanged
  rows; run-partitioned `snapshots` and `raw` files are immutable.
- A disappearance is `expired` only when observed after the published
  conclusion date. Otherwise it is `removed_early`.
- Input validation happens before current/history writes. Rejected bytes and a
  rejected manifest row are retained for diagnosis.
