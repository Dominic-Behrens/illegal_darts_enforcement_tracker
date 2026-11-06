# NSW tobacco closure-order database

A weekly scrape of the official NSW Health
[tobacco closure-order register](https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx).
The output is one flat CSV: **`closure-orders.csv` in the private Azure container**.
There is no dashboard or website deployment.

## Data and update rule

- Each row is an order observed on a Sydney calendar date.
- Each run scrapes the [source CSV](https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv)
  and archives its original bytes and response headers.
- Validated snapshots are appended to Azure. The combined CSV is rebuilt from
  these snapshots and replaces `closure-orders.csv` only after validation.
- For multiple scrapes on one date, the latest complete snapshot wins. Equal
  timestamps use descending run ID as a tie-break.
- The CSV has one row per `snapshot_date` and `closure_order_id`. An order
  remains in history across dates, even after it leaves the live register.
- All source fields are retained, including reason, exemption/variation and
  nullable coordinates. Dates use ISO format, timestamps use UTC, and missing
  values are empty CSV fields. Fetch time, run ID and record hash are included.
- NSW Health supplies no stable ID. `closure_order_id` hashes normalised
  premise name, address and commencement date. A correction to these fields
  can produce a new ID.
- The register excludes expired orders. Coverage begins with the earliest
  available snapshot; gaps between observations are unknown. Listed orders
  are not the same as all orders issued or all enforcement actions.

## Storage

The single combined data file is `closure-orders.csv` at the container root.
Run archives provide the recovery source:

```text
closure-orders.csv
raw/snapshot_date=YYYY-MM-DD/run_id=.../
  closure-orders.csv
  closure-orders.headers.json
snapshots/snapshot_date=YYYY-MM-DD/run_id=.../closure-orders.parquet
rejected/snapshot_date=YYYY-MM-DD/run_id=.../
```

Legacy Azure current/history/changes/manifest files are no longer used or
updated. Existing archives are retained. No credentials are written to the CSV.

## Run

GitHub Actions runs each Sunday at 18:00 UTC (Monday at 04:00 AEST or 05:00
AEDT). For a manual update, open **Actions → Update NSW closure-order tracker
→ Run workflow**. The run saves the CSV to Azure and attaches the same file
as the **closure-orders-csv** artifact. Download that artifact for a local copy.

The repository secret `AZURE_STORAGE_CONTAINER_SAS_URL` must hold the complete
container SAS URL with Read, Add, Create, Write and List permissions. Keep the
container private, record the SAS expiry in the credential-rotation system,
and never commit or log the URL. GitHub Pages is not required.

Run from the repository root in PowerShell:

```powershell
& "C:\Program Files\R\R-4.5.3\bin\x64\Rscript.exe" "tests/testthat.R"
# Set AZURE_STORAGE_CONTAINER_SAS_URL in the environment first.
& "C:\Program Files\R\R-4.5.3\bin\x64\Rscript.exe" "R/01-update-closure-orders.R"
& "C:\Program Files\R\R-4.5.3\bin\x64\Rscript.exe" "R/02-export-history.R"
```

The local CSV is `output/02-export-history/closure-orders.csv` and is ignored
by Git. Packages are loaded once with `pacman::p_load()` and declared in the
workflow.

Empty data, malformed CSV, missing or unexpected schema fields, invalid dates
or coordinates, missing key fields and duplicate generated IDs reject a scrape.
Rejected source bytes and headers are archived. Export validates all available
snapshots before replacing the CSV. Failure leaves the last good Azure CSV
unchanged. There is no fixed launch date or minimum snapshot-count requirement.
