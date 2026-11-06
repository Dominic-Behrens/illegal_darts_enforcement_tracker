# The Loop

- The deliverable is one flat CSV in Azure: `closure-orders.csv`. There is no
  dashboard, website deployment or derived event table.
- One row means one order observed on one Sydney calendar date. Deduplication
  uses snapshot date plus order ID; it never collapses an order across dates.
- For multiple scrapes on one date, retain the latest whole snapshot. This
  avoids restoring orders removed by a later scrape. Equal fetch timestamps
  use descending run ID as a tie-break.
- Each scrape appends raw bytes, headers and a validated snapshot. Export
  combines these snapshots, writes the CSV and saves it to Azure. Run archives
  are the recovery source. Existing legacy Azure files remain untouched.
- Input validation happens before a snapshot is saved. Rejected source bytes
  and response headers are retained. Invalid exports do not replace the last
  good CSV.
- The source has no stable ID. The order ID hashes normalised premise name,
  address and commencement date. Key corrections can produce a new ID.
- Available validated snapshots define coverage. There is no hard-coded
  launch date or minimum date count. Missing dates are unknown observations.
- Coordinates remain nullable and are not geocoded. Earlier snapshots without
  exemption/variation retain a missing value when combined with later data.
