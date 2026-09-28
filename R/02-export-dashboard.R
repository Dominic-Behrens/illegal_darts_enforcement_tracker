# Exports accepted weekly observations and changes for the public dashboard.
#
# Inputs: private Azure history, manifest and accepted run change partitions.
# Output: site/data/dashboard.json for deployment to GitHub Pages.
source("R/01-update-closure-orders.R", local = TRUE)

export_dashboard <- function(store, output_path = "site/data/dashboard.json") {
  manifest <- read_parquet_if_exists(store, "manifest/runs.parquet")
  history <- read_parquet_if_exists(store, "history/closure-orders.parquet")
  if (is.null(manifest) || is.null(history)) {
    stop("Dashboard export requires both the run manifest and history.", call. = FALSE)
  }

  manifest_fields <- c("status", "snapshot_date", "run_id", "fetched_at")
  history_fields <- c(
    "snapshot_date", "run_id", "closure_order_id", "premise_name", "address",
    "council", "latitude", "longitude", "closure_order_type",
    "date_commenced", "conclusion_date"
  )
  if (!all(manifest_fields %in% names(manifest)) ||
      !all(history_fields %in% names(history))) {
    stop("Dashboard source is missing required manifest or history fields.", call. = FALSE)
  }

  completed <- manifest %>%
    filter(status == "complete") %>%
    arrange(snapshot_date, desc(fetched_at)) %>%
    distinct(snapshot_date, .keep_all = TRUE) %>%
    select(snapshot_date, run_id)
  if (nrow(completed) == 0L) {
    stop("Dashboard export requires a completed run.", call. = FALSE)
  }

  observations <- history %>%
    semi_join(completed, by = c("snapshot_date", "run_id")) %>%
    select(all_of(setdiff(history_fields, "run_id"))) %>%
    mutate(
      snapshot_date = as.character(snapshot_date),
      date_commenced = as.character(date_commenced),
      conclusion_date = as.character(conclusion_date)
    )
  if (nrow(observations) == 0L) {
    stop("Dashboard export requires accepted history rows.", call. = FALSE)
  }

  change_fields <- c(
    "snapshot_date", "closure_order_id", "change_type", "is_initial_snapshot",
    "council"
  )
  changes <- lapply(seq_len(nrow(completed)), function(i) {
    partition <- paste0(
      "snapshot_date=", completed$snapshot_date[[i]],
      "/run_id=", completed$run_id[[i]]
    )
    path <- paste0("changes/", partition, "/changes.parquet")
    table <- read_parquet_if_exists(store, path)
    if (is.null(table) || !all(c(change_fields, "run_id") %in% names(table))) {
      stop("Dashboard export requires accepted changes at ", path, call. = FALSE)
    }
    if (any(table$run_id != completed$run_id[[i]] | !(
      table$snapshot_date == completed$snapshot_date[[i]]
    ))) {
      stop("Change partition does not match completed run: ", path, call. = FALSE)
    }
    table %>%
      select(all_of(change_fields)) %>%
      mutate(snapshot_date = as.character(snapshot_date))
  }) %>% bind_rows()

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
