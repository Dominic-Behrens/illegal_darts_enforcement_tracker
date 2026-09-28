# NSW tobacco closure-order tracker

This project takes a weekly snapshot of every row in the official NSW Health
[tobacco closure-order register](https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx).
The register excludes expired orders, so the tracker preserves observations
from its first successful run onward; it does not reconstruct earlier history.

The GitHub Action runs each Sunday at 18:00 UTC (Monday at 04:00 AEST or 05:00
AEDT in NSW) and can also be started manually. It downloads
the [source CSV](https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv),
archives its original bytes and response headers, obtains SharePoint file
metadata, validates and normalises the data, and writes Parquet outputs to a
private Azure Blob container.

## Public dashboard

The static dashboard lives in `site/` and is published to GitHub Pages after
each successful scheduled or manual update. Enable **Settings → Pages →
Build and deployment → Source: GitHub Actions** in the repository once.
Its public JSON extract is rebuilt from immutable validated snapshot
partitions in the private Azure container. The container SAS requires Read
and List for export; the URL is used by Actions only and is never sent to
the browser. Deployment fails closed if ingestion or export fails.

The charts count orders listed at each weekly observation, not all enforcement
actions or orders issued that week. An `added` change means first observed;
the first observation is a baseline, not a week's new orders. The map uses
coordinates as published by NSW Health and omits rows without coordinates.
The register excludes expired orders; historical coverage begins only with
the first successful tracker snapshot. Council labels are shown as published.

For a local preview, `site/data/dashboard.json` can combine dated public
[Internet Archive captures](https://web.archive.org/web/*/https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv)
with a live NSW Health download. These are sparse, uneven observations: days
between captures are unknown. The local file is ignored by Git and labelled
separately from the production tracker export. The live CSV alone cannot
reconstruct historical register counts. Serve `site/` with a static HTTP
server (for example
`python3 -m http.server 8765 --directory site`) and open
`http://localhost:8765/`. A `file://` URL cannot fetch the JSON.

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
and source hash. `current` is the latest accepted snapshot. `history` and
`manifest/runs.parquet` are mutable operational tables. A faulty HEAD request
previously caused them to be overwritten each week; they currently retain
only the latest run. The public export therefore reads the immutable
`snapshots/` partitions and re-derives changes instead of trusting these
mutable tables. The old per-run `changes/` partitions likewise reflect the
faulty baseline classification and are not used to calculate dashboard events.

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

As of 2026-09-28 the configured Actions SAS permits blob reads but Azure
returns `AuthorizationPermissionMismatch` for container listing. Rotate the
Actions secret to a **container-level SAS with List and Read** (and retain Add,
Create and Write for the weekly update). Do not paste the SAS into an issue,
log or chat. Then run **Actions → Export public dashboard history → Run
workflow**, download its `dashboard-data` artifact and place `dashboard.json`
in the ignored `site/data/` folder for local preview. The exporter requires
the original 22 July Sydney snapshot and at least 11 dated observations.

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
