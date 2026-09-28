# Exports the validated run-partitioned snapshots for the public dashboard.
# Inputs: private Azure snapshots/ and changes/ blobs (container List and Read).
# Output: site/data/dashboard.json for deployment to GitHub Pages.
source("R/01-update-closure-orders.R", local = TRUE)

export_dashboard <- function(store, output_path = "site/data/dashboard.json") {
  paths <- store$list()
  snapshots <- grep(
    "^snapshots/snapshot_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/run_id=[^/]+/closure-orders[.]parquet$",
    paths,
    value = TRUE
  )
  if (length(snapshots) == 0L) {
    stop("No immutable closure-order snapshots are available.", call. = FALSE)
  }

  required <- c(
    "snapshot_date", "run_id", "fetched_at", "closure_order_id",
    "premise_name", "address", "council", "latitude", "longitude",
    "closure_order_type", "date_commenced", "conclusion_date"
  )
  runs <- lapply(snapshots, function(path) {
    partition <- sub("^snapshots/", "", dirname(path))
    change_path <- paste0("changes/", partition, "/changes.parquet")
    if (!change_path %in% paths) {
      stop("Snapshot has no matching change partition: ", path, call. = FALSE)
    }
    rows <- parquet_to_table(store$read(path))
    expected_date <- sub("^snapshot_date=([^/]+)/.*$", "\\1", partition)
    expected_run <- sub("^.*/run_id=", "", partition)
    if (!all(required %in% names(rows)) || nrow(rows) == 0L ||
        anyDuplicated(rows$closure_order_id) ||
        any(is.na(rows$snapshot_date)) ||
        any(as.character(rows$snapshot_date) != expected_date) ||
        any(is.na(rows$run_id)) || any(rows$run_id != expected_run) ||
        any(is.na(rows$fetched_at))) {
      stop("Invalid immutable snapshot: ", path, call. = FALSE)
    }
    tibble(
      snapshot_date = as.Date(expected_date),
      fetched_at = max(rows$fetched_at),
      rows = list(rows)
    )
  }) %>% bind_rows() %>%
    arrange(snapshot_date, desc(fetched_at)) %>%
    distinct(snapshot_date, .keep_all = TRUE) %>%
    arrange(snapshot_date)

  # The first accepted run was 21 July UTC (22 July in Sydney). The repo
  # recorded 11 successful run dates through 27 September UTC. Do not publish
  # a partial extract if older immutable snapshots cannot be listed.
  if (min(runs$snapshot_date) != as.Date("2026-07-22") || nrow(runs) < 11L) {
    stop("Immutable tracker history is incomplete; expected at least 11 ",
         "observation dates starting 2026-07-22.", call. = FALSE)
  }

  history <- NULL
  previous <- NULL
  detected <- vector("list", nrow(runs))
  for (i in seq_len(nrow(runs))) {
    current <- runs$rows[[i]]
    detected[[i]] <- derive_changes(current, previous, history, i == 1L) %>%
      select(snapshot_date, closure_order_id, change_type,
             is_initial_snapshot, council)
    history <- bind_rows(history, current)
    previous <- current
  }

  observations <- history %>%
    select(snapshot_date, closure_order_id, premise_name, address, council,
           latitude, longitude, closure_order_type, date_commenced,
           conclusion_date) %>%
    mutate(across(c(snapshot_date, date_commenced, conclusion_date), as.character))
  changes <- bind_rows(detected) %>%
    mutate(snapshot_date = as.character(snapshot_date))

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    list(
      source_mode = "tracker",
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      observations = observations,
      changes = changes
    ),
    output_path,
    pretty = TRUE,
    auto_unbox = TRUE,
    dataframe = "rows",
    na = "null"
  )
  invisible(output_path)
}

export_main <- function() {
  container_sas_url <- Sys.getenv("AZURE_STORAGE_CONTAINER_SAS_URL")
  if (container_sas_url == "") {
    stop("AZURE_STORAGE_CONTAINER_SAS_URL is not configured.", call. = FALSE)
  }
  export_dashboard(azure_store(container_sas_url))
}

if (sys.nframe() == 0L) export_main()
