# Data notes

## NSW Health closure-order register

- Source CSV: <https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv>
- Register page: <https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx>
- The public register states that expired orders are excluded. Absence from a
  later snapshot does not by itself prove why an order disappeared.
- The CSV currently publishes premise name, address, council, latitude,
  longitude, closure order type, date commenced, conclusion and reason. It does
  not publish a stable ID. Coordinates are retained as published and are not
  geocoded or corrected by this project.
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
