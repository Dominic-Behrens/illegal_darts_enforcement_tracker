# NSW tobacco closure-order tracker

This project takes a daily snapshot of every row in the official NSW Health
[tobacco closure-order register](https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx).
The register excludes expired orders, so the tracker preserves observations
from its first successful run onward; it does not reconstruct earlier history.

The GitHub Action runs at 18:00 UTC each day (04:00 AEST or 05:00 AEDT the
following calendar day in NSW) and can also be started manually. It downloads
the [source CSV](https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv),
archives its original bytes and response headers, obtains SharePoint file
metadata, validates and normalises the data, and writes Parquet outputs to a
private Azure Blob container.

## Azure layout

```text
raw/snapshot_date=YYYY-MM-DD/run_id=.../
  closure-orders.csv
  closure-orders.headers.json
  closure-orders.metadata.json
snapshots/snapshot_date=YYYY-MM-DD/run_id=.../closure-orders.parquet
changes/snapshot_date=YYYY-MM-DD/run_id=.../changes.parquet
rejected/snapshot_date=YYYY-MM-DD/run_id=.../
current/closure-orders.parquet
history/closure-orders.parquet
manifest/runs.parquet
```

Run-scoped files are immutable because each run ID contains its UTC timestamp
and source hash. `current` is the latest accepted snapshot. `history` contains
every row from every accepted daily snapshot, including unchanged rows.
`manifest/runs.parquet` records source identifiers, headers, hashes, sizes, row
and change counts, warnings, and completion or rejection status.

Changes are classified as:

- `added`: first observed by this tracker (all launch rows are initial adds);
- `updated`: the stable key is unchanged but another published field changed;
- `expired`: a row disappeared after its published conclusion date;
- `removed_early`: a row disappeared on or before its conclusion date, or no
  conclusion date was published; and
- `reappeared`: an ID seen in history returns after being absent from current.

NSW Health publishes no stable record ID. `closure_order_id` is therefore a
SHA-256 hash of normalised premise name, address and commencement date. A
correction to any key field may appear as a removal and addition. `record_hash`
hashes all published fields separately from observation metadata.

## Required setup

1. Create a **private** Azure Blob container named
   `illegal-darts-enforcement-tracker`.
2. Generate a container-level HTTPS SAS URL with Read, Add, Create, Write and
   List permissions. Choose and record an expiry date that allows timely
   rotation.
3. In the GitHub repository, create the Actions secret
   `AZURE_STORAGE_CONTAINER_SAS_URL` containing the complete container SAS URL.
4. Commit and push this project to `main`. Scheduled Actions run only from the
   default branch.
5. Open **Actions → Update NSW closure-order tracker → Run workflow**.
6. Verify that the raw CSV bytes, snapshot and current row counts, initial
   `added` count, history rows, changes, and completed manifest row agree.

Record the SAS expiry in the repository or organisation's credential-rotation
system. Do not commit the SAS URL.

## Run locally

Open `illegal-darts-enforcement-tracker.Rproj` in RStudio or open the repository
folder in VS Code. From the repository root:

```powershell
& "C:\Program Files\R\R-4.5.3\bin\x64\Rscript.exe" "tests\testthat.R"
```

The production script requires the Azure SAS environment variable:

```powershell
$env:AZURE_STORAGE_CONTAINER_SAS_URL = "https://...container?..."
& "C:\Program Files\R\R-4.5.3\bin\x64\Rscript.exe" "R\01-update-closure-orders.R"
```

Dependencies are declared in the workflow and loaded at the top of the R
script with `pacman::p_load()`. Raw and generated local data directories are
ignored by Git.
## Failure behavior

Empty data, malformed CSV, missing or unexpected schema fields, invalid dates
or coordinates, missing key fields, and duplicate generated IDs reject the
run. The response is archived under `rejected/`, the rejection is appended to
the manifest, and current/history remain unchanged. Missing SharePoint metadata
or a metadata byte-count discrepancy is recorded as a warning only.
