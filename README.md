# NSW tobacco closure-order tracker

This project takes a weekly snapshot of every row in the official NSW Health
[tobacco closure-order register](https://www.health.nsw.gov.au/tobacco/Pages/closure-register.aspx).
The register excludes expired orders, so the tracker preserves observations
from its first successful run onward; it does not reconstruct earlier history.

The GitHub Action runs each Sunday at 18:00 UTC (Monday at 04:00 AEST or 05:00
AEDT in NSW) and can also be started manually. It downloads
the [source CSV](https://www.health.nsw.gov.au/tobacco/register/closure-orders.csv),
archives its original bytes and response headers, validates and normalises the
data, and appends a dated Parquet snapshot to a private Azure Blob container.

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
snapshots/snapshot_date=YYYY-MM-DD/run_id=.../closure-orders.parquet
rejected/snapshot_date=YYYY-MM-DD/run_id=.../
```

Each scrape appends a run partition. No mutable current, history, changes or
manifest tables are read or written. Existing legacy files are left in Azure.
The raw archive is written first; only a validated snapshot is used by export.

The dashboard reads the snapshot partitions, keeps the latest complete run per
Sydney calendar date, and combines those daily observations. Each daily
snapshot has one row per order ID. For equal fetch timestamps, run ID breaks
ties in descending order. Selecting the whole daily snapshot means an order
removed by a later scrape that day does not survive from an earlier scrape.
Orders remain in history across dates, including when they disappear from the
live register. Changes are derived between the retained daily snapshots.
The earliest available date is the baseline. There is no fixed start-date or
minimum-date-count check; an empty store or invalid snapshot still fails.

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
6. Check the logged saved row count, export date range and observation count.
   The first date is a baseline; reruns on one date must not add duplicate rows.

Record the SAS expiry in the repository or organisation's credential-rotation
system. Do not commit the SAS URL.

On 2026-11-06, the rotated SAS successfully saved to Azure. A read-only
export found 19 valid partitions over 18 dates, from 2026-07-21 to 2026-11-06.
The earlier export failed because its hard-coded start date rejected the
additional 21 July snapshot. The simplified exporter uses the available
validated history without that fixed-date assumption. The simplified run
passed all 41 tests, saved 126 orders and exported 2,647 observations across
18 dates. Its later website deployment failed because GitHub Pages is not
enabled. Enable Pages with GitHub Actions as the source to publish the dashboard.

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
run. Rejected source bytes and response headers are archived under `rejected/`.
Accepted snapshots are not changed. Export rejects invalid snapshots and
publishes only after all available snapshot partitions pass validation.
