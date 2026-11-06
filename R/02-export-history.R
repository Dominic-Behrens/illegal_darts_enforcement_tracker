# Combines dated snapshots into one flat CSV database.
# Inputs: private Azure snapshots/ blobs (container List and Read).
# Outputs: output/02-export-history/closure-orders.csv and Azure closure-orders.csv.
source("R/01-update-closure-orders.R", local = TRUE)

export_history <- function(store, output_path = "output/02-export-history/closure-orders.csv") {
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
    "closure_order_type", "date_commenced", "conclusion_date", "record_hash"
  )
  runs <- lapply(snapshots, function(path) {
    partition <- sub("^snapshots/", "", dirname(path))
    rows <- parquet_to_table(store$read(path))
    expected_date <- sub("^snapshot_date=([^/]+)/.*$", "\\1", partition)
    expected_run <- sub("^.*/run_id=", "", partition)
    if (!all(required %in% names(rows)) || nrow(rows) == 0L ||
        anyDuplicated(rows$closure_order_id) ||
        any(is.na(rows$closure_order_id)) || any(!nzchar(rows$closure_order_id)) ||
        any(is.na(rows$snapshot_date)) ||
        any(as.character(rows$snapshot_date) != expected_date) ||
        any(is.na(rows$run_id)) || any(rows$run_id != expected_run) ||
        any(is.na(rows$fetched_at))) {
      stop("Invalid immutable snapshot: ", path, call. = FALSE)
    }
    tibble(
      snapshot_date = as.Date(expected_date),
      fetched_at = max(rows$fetched_at),
      run_id = expected_run,
      rows = list(rows)
    )
  }) %>% bind_rows() %>%
    arrange(snapshot_date, desc(fetched_at), desc(run_id)) %>%
    distinct(snapshot_date, .keep_all = TRUE) %>%
    arrange(snapshot_date)

  history <- bind_rows(runs$rows) %>%
    arrange(snapshot_date, closure_order_id) %>%
    select(snapshot_date, closure_order_id, everything())

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(history, output_path, na = "")
  store$write("closure-orders.csv", read_file_raw(output_path), "text/csv; charset=utf-8")
  message("Exported ", nrow(runs), " observation dates (",
          min(runs$snapshot_date), " to ", max(runs$snapshot_date),
          "); ", nrow(history), " order observations.")
  invisible(output_path)
}

export_main <- function() {
  container_sas_url <- Sys.getenv("AZURE_STORAGE_CONTAINER_SAS_URL")
  if (container_sas_url == "") {
    stop("AZURE_STORAGE_CONTAINER_SAS_URL is not configured.", call. = FALSE)
  }
  export_history(azure_store(container_sas_url))
}

if (sys.nframe() == 0L) export_main()
