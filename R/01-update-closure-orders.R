# Downloads and validates the NSW tobacco closure-order register, then records
# immutable raw/snapshot/change files and updates the current, history and run
# manifest tables.
# Inputs: NSW Health closure-order CSV and SharePoint file metadata; the prior
# current/history/manifest Parquet blobs when present.
# Outputs: raw/, snapshots/, changes/, rejected/, current/, history/ and
# manifest/ objects in the configured Azure container or local test directory.

pacman::p_load(
  arrow,
  curl,
  digest,
  dplyr,
  jsonlite,
  purrr,
  readr,
  stringr,
  tibble
)

csv_url <- paste0(
  "https://www.health.nsw.gov.au/tobacco/register/",
  "closure-orders.csv"
)
register_url <- paste0(
  "https://www.health.nsw.gov.au/tobacco/Pages/",
  "closure-register.aspx"
)
metadata_url <- paste0(
  "https://www.health.nsw.gov.au/_api/web/",
  "GetFileByServerRelativeUrl('/tobacco/register/closure-orders.csv')",
  "?$select=Name,Length,TimeCreated,TimeLastModified,ETag,ServerRelativeUrl"
)

required_source_fields <- c(
  "premise_name",
  "address",
  "council",
  "closure_order_type",
  "date_commenced",
  "conclusion_date",
  "reason"
)

source_aliases <- c(
  "premises_name" = "premise_name",
  "premise_name" = "premise_name",
  "address" = "address",
  "council" = "council",
  "closure_order_type" = "closure_order_type",
  "short_or_long_term_closure_order" = "closure_order_type",
  "date_commenced" = "date_commenced",
  "conclusion" = "conclusion_date",
  "conclusion_date" = "conclusion_date",
  "conclusion_of_closure_order" = "conclusion_date",
  "reason" = "reason",
  "reason_for_closure_order" = "reason",
  "latitude" = "latitude",
  "longitude" = "longitude"
)

normalise_names <- function(x) {
  x %>%
    str_replace("^\\ufeff", "") %>%
    str_to_lower() %>%
    str_replace_all("[^a-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

normalise_text <- function(x) {
  x %>%
    str_replace_all("\\u00a0", " ") %>%
    str_replace_all("[[:space:]]+", " ") %>%
    str_trim() %>%
    na_if("")
}

parse_register_date <- function(x, field) {
  x <- normalise_text(x)
  formats <- c("%d-%b-%y", "%d-%b-%Y", "%d/%m/%Y", "%Y-%m-%d")
  parsed <- as.Date(rep(NA_character_, length(x)))

  for (format in formats) {
    missing <- is.na(parsed) & !is.na(x)
    parsed[missing] <- as.Date(x[missing], format = format)
  }

  invalid <- !is.na(x) & is.na(parsed)
  if (any(invalid)) {
    examples <- paste(head(unique(x[invalid]), 3), collapse = ", ")
    stop("Invalid ", field, " value(s): ", examples, call. = FALSE)
  }

  parsed
}

hash_values <- function(...) {
  values <- list(...) %>%
    map(~ ifelse(is.na(.x), "<NA>", as.character(.x)))

  pmap_chr(values, function(...) {
    digest(
      toJSON(list(...), auto_unbox = TRUE, na = "string"),
      algo = "sha256",
      serialize = FALSE
    )
  })
}

parse_closure_csv <- function(raw_bytes, snapshot_date, fetched_at, run_id) {
  if (length(raw_bytes) == 0L) {
    stop("Downloaded CSV is empty.", call. = FALSE)
  }

  raw_table <- suppressMessages(
    read_csv(
      raw_bytes,
      col_types = cols(.default = col_character()),
      na = character(),
      trim_ws = FALSE,
      name_repair = "minimal",
      progress = FALSE
    )
  )

  if (nrow(raw_table) == 0L) {
    stop("Downloaded CSV contains no data rows.", call. = FALSE)
  }

  cleaned_names <- normalise_names(names(raw_table))
  mapped_names <- unname(source_aliases[cleaned_names])
  mapped_names[is.na(mapped_names)] <- cleaned_names[is.na(mapped_names)]

  if (anyDuplicated(mapped_names)) {
    stop("CSV contains duplicate columns after name normalisation.", call. = FALSE)
  }
  names(raw_table) <- mapped_names

  missing_fields <- setdiff(required_source_fields, names(raw_table))
  if (length(missing_fields) > 0L) {
    stop(
      "CSV is missing required field(s): ",
      paste(missing_fields, collapse = ", "),
      call. = FALSE
    )
  }

  unexpected_fields <- setdiff(
    names(raw_table),
    c(required_source_fields, "latitude", "longitude")
  )
  if (length(unexpected_fields) > 0L) {
    stop(
      "CSV contains unexpected field(s): ",
      paste(unexpected_fields, collapse = ", "),
      call. = FALSE
    )
  }

  if (!"latitude" %in% names(raw_table)) raw_table$latitude <- NA_character_
  if (!"longitude" %in% names(raw_table)) raw_table$longitude <- NA_character_
  raw_table[c("latitude", "longitude")] <- map(
    raw_table[c("latitude", "longitude")],
    normalise_text
  )

  text_fields <- c(
    "premise_name", "address", "council", "closure_order_type", "reason"
  )
  raw_table[text_fields] <- map(raw_table[text_fields], normalise_text)

  key_missing <- is.na(raw_table$premise_name) |
    is.na(raw_table$address) |
    is.na(raw_table$date_commenced)
  if (any(key_missing)) {
    stop("CSV contains a missing closure-order key field.", call. = FALSE)
  }

  latitude <- parse_double(raw_table$latitude, na = character())
  longitude <- parse_double(raw_table$longitude, na = character())
  bad_coordinates <- (
    (!is.na(raw_table$latitude) & is.na(latitude)) |
      (!is.na(raw_table$longitude) & is.na(longitude)) |
      (!is.na(latitude) & (latitude < -90 | latitude > 90)) |
      (!is.na(longitude) & (longitude < -180 | longitude > 180))
  )
  if (any(bad_coordinates)) {
    stop("CSV contains invalid coordinates.", call. = FALSE)
  }
  raw_table$latitude <- latitude
  raw_table$longitude <- longitude

  result <- raw_table %>%
    transmute(
      closure_order_id = hash_values(
        str_to_lower(premise_name),
        str_to_lower(address),
        format(parse_register_date(date_commenced, "date_commenced"))
      ),
      premise_name,
      address,
      council,
      latitude,
      longitude,
      closure_order_type,
      date_commenced = parse_register_date(date_commenced, "date_commenced"),
      conclusion_date = parse_register_date(conclusion_date, "conclusion_date"),
      reason,
      record_hash = hash_values(
        premise_name,
        address,
        council,
        latitude,
        longitude,
        closure_order_type,
        format(date_commenced),
        format(conclusion_date),
        reason
      ),
      snapshot_date = as.Date(snapshot_date),
      fetched_at = as.POSIXct(fetched_at, tz = "UTC"),
      run_id = as.character(run_id)
    )

  if (anyDuplicated(result$closure_order_id)) {
    stop("CSV produces duplicate closure_order_id values.", call. = FALSE)
  }

  result
}

empty_snapshot <- function() {
  tibble(
    closure_order_id = character(), premise_name = character(),
    address = character(), council = character(), latitude = double(),
    longitude = double(), closure_order_type = character(),
    date_commenced = as.Date(character()),
    conclusion_date = as.Date(character()), reason = character(),
    record_hash = character(), snapshot_date = as.Date(character()),
    fetched_at = as.POSIXct(character(), tz = "UTC"), run_id = character()
  )
}

derive_changes <- function(current, previous_current, history, initial_snapshot) {
  previous_current <- previous_current %||% empty_snapshot()
  history <- history %||% empty_snapshot()

  current_ids <- current$closure_order_id
  previous_ids <- previous_current$closure_order_id
  historical_ids <- unique(history$closure_order_id)

  new_rows <- current %>%
    filter(!closure_order_id %in% previous_ids) %>%
    mutate(
      change_type = if_else(
        closure_order_id %in% historical_ids,
        "reappeared",
        "added"
      ),
      previous_record_hash = NA_character_,
      current_record_hash = record_hash
    )

  updated_rows <- current %>%
    inner_join(
      previous_current %>%
        select(closure_order_id, previous_record_hash = record_hash),
      by = "closure_order_id"
    ) %>%
    filter(record_hash != previous_record_hash) %>%
    mutate(
      change_type = "updated",
      current_record_hash = record_hash
    )

  removed_rows <- previous_current %>%
    filter(!closure_order_id %in% current_ids) %>%
    mutate(
      snapshot_date = unique(current$snapshot_date),
      fetched_at = unique(current$fetched_at),
      run_id = unique(current$run_id),
      change_type = if_else(
        !is.na(conclusion_date) & snapshot_date > conclusion_date,
        "expired",
        "removed_early"
      ),
      previous_record_hash = record_hash,
      current_record_hash = NA_character_
    )

  bind_rows(new_rows, updated_rows, removed_rows) %>%
    mutate(
      is_initial_snapshot = initial_snapshot,
      detected_at = unique(current$fetched_at)
    ) %>%
    select(
      change_type,
      is_initial_snapshot,
      detected_at,
      previous_record_hash,
      current_record_hash,
      everything()
    )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

raw_to_parquet <- function(table) {
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)
  write_parquet(table, path)
  readBin(path, what = "raw", n = file.info(path)$size)
}

parquet_to_table <- function(raw_bytes) {
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)
  writeBin(raw_bytes, path)
  read_parquet(path, as_data_frame = TRUE) %>% as_tibble()
}

local_store <- function(root) {
  dir.create(root, recursive = TRUE, showWarnings = FALSE)

  list(
    exists = function(path) file.exists(file.path(root, path)),
    read = function(path) readBin(
      file.path(root, path), what = "raw", n = file.info(file.path(root, path))$size
    ),
    write = function(path, bytes, content_type = "application/octet-stream") {
      target <- file.path(root, path)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      writeBin(bytes, target)
      invisible(target)
    }
  )
}

azure_blob_url <- function(container_sas_url, path) {
  parts <- str_split_fixed(container_sas_url, "\\?", 2)
  encoded_path <- str_split(path, "/", simplify = FALSE)[[1]] %>%
    map_chr(curl_escape) %>%
    paste(collapse = "/")
  paste0(str_remove(parts[1], "/$"), "/", encoded_path, "?", parts[2])
}

azure_store <- function(container_sas_url) {
  request <- function(path, method, bytes = NULL, content_type = NULL) {
    handle <- new_handle(
      customrequest = method,
      httpheader = c(
        "x-ms-version: 2023-11-03",
        if (method == "PUT") "x-ms-blob-type: BlockBlob",
        if (!is.null(content_type)) paste0("Content-Type: ", content_type)
      ),
      postfields = bytes
    )
    curl_fetch_memory(azure_blob_url(container_sas_url, path), handle = handle)
  }

  list(
    exists = function(path) {
      response <- tryCatch(request(path, "HEAD"), error = identity)
      !inherits(response, "error") && response$status_code == 200L
    },
    read = function(path) {
      response <- request(path, "GET")
      if (response$status_code != 200L) {
        stop("Could not read Azure blob: ", path, call. = FALSE)
      }
      response$content
    },
    write = function(path, bytes, content_type = "application/octet-stream") {
      response <- request(path, "PUT", bytes, content_type)
      if (!response$status_code %in% c(200L, 201L)) {
        stop("Could not write Azure blob: ", path, call. = FALSE)
      }
      invisible(path)
    }
  )
}

read_parquet_if_exists <- function(store, path) {
  if (!store$exists(path)) return(NULL)
  parquet_to_table(store$read(path))
}

append_manifest <- function(store, row) {
  path <- "manifest/runs.parquet"
  old <- read_parquet_if_exists(store, path)
  manifest <- bind_rows(old, row)
  store$write(path, raw_to_parquet(manifest), "application/vnd.apache.parquet")
}

headers_to_list <- function(headers) {
  parsed <- parse_headers_list(headers)
  parsed[!names(parsed) %in% c("set-cookie")]
}

fetch_source <- function(url, accept = NULL) {
  handle <- new_handle(
    useragent = "illegal-darts-enforcement-tracker/1.0",
    httpheader = if (!is.null(accept)) paste0("Accept: ", accept)
  )
  response <- curl_fetch_memory(url, handle = handle)
  if (response$status_code != 200L) {
    stop("Source returned HTTP ", response$status_code, ": ", url, call. = FALSE)
  }
  response
}

run_tracker <- function(
    store,
    csv_response,
    metadata_response = NULL,
    fetched_at = Sys.time(),
    run_id = NULL) {
  fetched_at <- as.POSIXct(fetched_at, tz = "UTC")
  snapshot_date <- as.Date(fetched_at, tz = "Australia/Sydney")
  run_id <- run_id %||% paste0(
    format(fetched_at, "%Y%m%dT%H%M%SZ", tz = "UTC"), "-",
    substr(digest(csv_response$content, algo = "sha256"), 1, 12)
  )
  partition <- paste0("snapshot_date=", snapshot_date, "/run_id=", run_id)
  source_sha256 <- digest(csv_response$content, algo = "sha256")

  header_bytes <- charToRaw(toJSON(
    headers_to_list(csv_response$headers),
    auto_unbox = TRUE,
    pretty = TRUE
  ))
  metadata_bytes <- if (is.null(metadata_response)) {
    charToRaw("{}")
  } else {
    metadata_response$content
  }

  warnings <- character()
  if (is.null(metadata_response)) {
    warnings <- c(warnings, "SharePoint metadata was unavailable.")
  } else {
    metadata <- tryCatch(
      fromJSON(rawToChar(metadata_response$content, multiple = FALSE)),
      error = function(error) NULL
    )
    metadata_length <- metadata$Length %||% metadata$d$Length %||% NA_real_
    if (!is.na(metadata_length) && as.double(metadata_length) !=
        length(csv_response$content)) {
      warnings <- c(
        warnings,
        paste0(
          "SharePoint metadata length (", metadata_length,
          ") differs from downloaded bytes (", length(csv_response$content), ")."
        )
      )
    }
  }

  parsed <- tryCatch(
    parse_closure_csv(
      csv_response$content,
      snapshot_date,
      fetched_at,
      run_id
    ),
    error = identity
  )

  base_manifest <- tibble(
    run_id = run_id,
    snapshot_date = snapshot_date,
    fetched_at = fetched_at,
    csv_url = csv_url,
    register_url = register_url,
    metadata_url = metadata_url,
    etag = headers_to_list(csv_response$headers)[["etag"]] %||% NA_character_,
    last_modified = headers_to_list(csv_response$headers)[["last-modified"]] %||%
      NA_character_,
    source_sha256 = source_sha256,
    source_bytes = as.double(length(csv_response$content)),
    row_count = if (inherits(parsed, "error")) NA_integer_ else nrow(parsed),
    added_count = NA_integer_,
    updated_count = NA_integer_,
    expired_count = NA_integer_,
    removed_early_count = NA_integer_,
    reappeared_count = NA_integer_,
    warnings = paste(warnings, collapse = " | "),
    status = if (inherits(parsed, "error")) "rejected" else "in_progress",
    error = if (inherits(parsed, "error")) conditionMessage(parsed) else NA_character_
  )

  if (inherits(parsed, "error")) {
    rejected_base <- paste0("rejected/", partition, "/")
    store$write(
      paste0(rejected_base, "closure-orders.csv"),
      csv_response$content,
      "text/csv"
    )
    store$write(
      paste0(rejected_base, "closure-orders.headers.json"),
      header_bytes,
      "application/json"
    )
    store$write(
      paste0(rejected_base, "closure-orders.metadata.json"),
      metadata_bytes,
      "application/json"
    )
    append_manifest(store, base_manifest)
    stop(conditionMessage(parsed), call. = FALSE)
  }

  previous_current <- read_parquet_if_exists(
    store, "current/closure-orders.parquet"
  )
  history <- read_parquet_if_exists(store, "history/closure-orders.parquet")
  initial_snapshot <- is.null(history) || nrow(history) == 0L
  changes <- derive_changes(parsed, previous_current, history, initial_snapshot)
  new_history <- bind_rows(history, parsed)

  change_counts <- table(factor(
    changes$change_type,
    levels = c("added", "updated", "expired", "removed_early", "reappeared")
  ))
  manifest_row <- base_manifest %>%
    mutate(
      added_count = as.integer(change_counts[["added"]]),
      updated_count = as.integer(change_counts[["updated"]]),
      expired_count = as.integer(change_counts[["expired"]]),
      removed_early_count = as.integer(change_counts[["removed_early"]]),
      reappeared_count = as.integer(change_counts[["reappeared"]]),
      status = "complete"
    )

  raw_base <- paste0("raw/", partition, "/")
  store$write(
    paste0(raw_base, "closure-orders.csv"),
    csv_response$content,
    "text/csv"
  )
  store$write(
    paste0(raw_base, "closure-orders.headers.json"),
    header_bytes,
    "application/json"
  )
  store$write(
    paste0(raw_base, "closure-orders.metadata.json"),
    metadata_bytes,
    "application/json"
  )
  store$write(
    paste0("snapshots/", partition, "/closure-orders.parquet"),
    raw_to_parquet(parsed),
    "application/vnd.apache.parquet"
  )
  store$write(
    paste0("changes/", partition, "/changes.parquet"),
    raw_to_parquet(changes),
    "application/vnd.apache.parquet"
  )
  store$write(
    "current/closure-orders.parquet",
    raw_to_parquet(parsed),
    "application/vnd.apache.parquet"
  )
  store$write(
    "history/closure-orders.parquet",
    raw_to_parquet(new_history),
    "application/vnd.apache.parquet"
  )
  append_manifest(store, manifest_row)

  invisible(list(snapshot = parsed, changes = changes, manifest = manifest_row))
}

main <- function() {
  container_sas_url <- Sys.getenv("AZURE_STORAGE_CONTAINER_SAS_URL")
  if (container_sas_url == "") {
    stop(
      "AZURE_STORAGE_CONTAINER_SAS_URL is not configured.",
      call. = FALSE
    )
  }

  csv_response <- fetch_source(csv_url, "text/csv")
  metadata_response <- tryCatch(
    fetch_source(metadata_url, "application/json;odata=nometadata"),
    error = function(error) {
      warning(conditionMessage(error), call. = FALSE)
      NULL
    }
  )

  run_tracker(
    azure_store(container_sas_url),
    csv_response,
    metadata_response
  )
}

if (sys.nframe() == 0L) main()
