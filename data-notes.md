# Data notes

## NSW Health closure-order register

- Source CSV: <https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv>
- Register page: <https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx>
- The public register states that expired orders are excluded. Absence from a
  later snapshot does not by itself prove why an order disappeared.
- The CSV currently publishes premise name, address, council, latitude,
  longitude, closure order type, date commenced, conclusion, reason and
  exemption/variation. It does not publish a stable ID. Coordinates are retained
  as published and are not geocoded or corrected by this project.
- Three CSV headings are more verbose than the rendered register labels:
  `Short or long term closure order`, `Conclusion of closure order` and
  `Reason for closure order`. The parser maps both forms explicitly.
- Text normalisation replaces non-breaking spaces, collapses whitespace
  (including line breaks) and trims edges. Original bytes remain in `raw/`.
- Accepted date formats are `d-Mon-yy`, `d-Mon-yyyy`, `d/m/yyyy` and ISO
  `yyyy-mm-dd`. Dates are treated as published calendar dates, without inferred
  times.
- Reason text is retained as published after whitespace normalisation. No
  offence categories are derived.
- Snapshot dates use `Australia/Sydney`; fetch timestamps use UTC.
- `expired` is a tracker inference made only when the disappearance is observed
  after the published conclusion date. `removed_early` includes disappearances
  on the conclusion date and records lacking a conclusion date.
- On 2026-07-21, the live-source smoke test strictly parsed all 168 published
  rows, found no duplicate generated IDs and received HTTP 200 from the
  SharePoint metadata endpoint.
- On 2026-07-30, NSW Health added `Exemption/variation` to the CSV. All 159
  published rows had a value: 155 `No` and 4 `Yes`. Snapshots before this date
  have no value for this field.
- On 2026-09-28, the live source strictly parsed 146 published rows. The
  local preview JSON is untracked and is not the production Pages data source.
- The Internet Archive CDX index for the source CSV has 11 distinct capture
  dates from 2026-08-21 to 2026-09-25. Each archived CSV strictly parsed:
  observed row counts in date order were 154, 150, 147, 147, 147, 147, 144,
  150, 148, 143 and 146. A 2026-09-28 live download had 146 rows.
  This sparse series is a local preview only; unobserved dates are unknown.
  Archive: <https://web.archive.org/web/*/https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv>.
- GitHub Actions shows 11 successful tracker runs from 2026-07-21 UTC to
  2026-09-27 UTC; the 2026-07-26 scheduled run failed. A 2026-09-28 export
  from mutable `history` contained only 146 rows, all dated 2026-09-28.
  The earlier immutable run partitions have not yet been enumerated because
  the SAS then in use returned `AuthorizationPermissionMismatch` on
  List. Do not treat the mutable table or its saved changes as full history.

- On 2026-11-06, retry run 42135297376 passed tests and completed the Azure
  ingestion writes with the rotated Actions SAS. Dashboard export listed and
  read the available snapshot partitions, then failed the check for at least
  11 observation dates starting 2026-07-22. Exact available/missing dates and
  whether the SAS targets the original container remain unverified. Pages
  deployment was skipped. Run: <https://github.com/Dominic-Behrens/illegal_darts_enforcement_tracker/actions/runs/42135297376>.

- Read-only diagnostic run 42157549227 on 2026-11-06 enumerated and validated
  19 snapshot partitions over 18 dates: 2026-07-21, 2026-07-22, 2026-07-30,
  2026-08-03, 2026-08-10, 2026-08-17, 2026-08-24, 2026-08-31, 2026-09-07,
  2026-09-14, 2026-09-21, 2026-09-28, 2026-10-05, 2026-10-12, 2026-10-19,
  2026-10-26, 2026-11-02 and 2026-11-06. The fixed minimum-date equality
  check rejected the additional 21 July snapshot; this was not evidence of
  missing history. Run: <https://github.com/Dominic-Behrens/illegal_darts_enforcement_tracker/actions/runs/42157549227>.

- Simplified pipeline run 42158128605 on 2026-11-06 passed all 41 tests,
  saved 126 orders to Azure, and exported 2,647 observations over 18 dates
  (2026-07-21 to 2026-11-06). The downloaded dashboard-data artifact has no
  duplicate snapshot-date/order-ID keys and 126 rows on the latest date.
  Data ingestion/export succeeded; the later configure-pages step failed
  with HTTP 404 because the repository has no configured Pages site.
  Run: <https://github.com/Dominic-Behrens/illegal_darts_enforcement_tracker/actions/runs/42158128605>.

- Database-only run 42159784038 on 2026-11-06 succeeded end to end: 41 tests
  passed, 126 current orders were archived, and Azure `closure-orders.csv`
  was written. The downloaded CSV contains 2,647 rows, 18 dates from
  2026-07-21 to 2026-11-06, and no duplicate date/order-ID keys. It retains
  reason, exemption/variation and observation metadata. Latest-date count is
  126. The same file is available as the `closure-orders-csv` Actions artifact.
  Run: <https://github.com/Dominic-Behrens/illegal_darts_enforcement_tracker/actions/runs/42159784038>.
