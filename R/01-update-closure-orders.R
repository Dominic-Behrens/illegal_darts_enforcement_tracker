# Scrapes and validates the NSW tobacco closure-order register.
# Inputs: NSW Health closure-order CSV and response headers.
# Outputs: immutable raw/ and snapshots/ partitions in Azure (or local tests);
# rejected/ partitions hold invalid source responses. Existing data is not read.

pacman::p_load(
  arrow,
  curl,
  digest,
  dplyr,
  jsonlite,
  purrr,
  readr,
  stringr,
  tibble,
  xml2
)

csv_url <- paste0(
  "https://www.health.nsw.gov.au/tobacco/register/",
  "closure-orders.csv"
)

required_source_fields <- c(
  "premise_name",
  "address",
  "council",
  "closure_order_type",
  "date_commenced",
  "conclusion_date",
  "reason",
  "exemption_variation"
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
  "exemption_variation" = "exemption_variation",
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
    "premise_name", "address", "council", "closure_order_type", "reason",
    "exemption_variation"
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
      exemption_variation,
      record_hash = hash_values(
        premise_name,
        address,
        council,
        latitude,
        longitude,
        closure_order_type,
        format(date_commenced),
        format(conclusion_date),
        reason,
        exemption_variation
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
    exemption_variation = character(),
    record_hash = character(), snapshot_date = as.Date(character()),
    fetched_at = as.POSIXct(character(), tz = "UTC"), run_id = character()
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
    },
    list = function(prefix = "") {
      paths <- list.files(root, recursive = TRUE, full.names = FALSE)
      paths[startsWith(paths, prefix)]
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
    },
    list = function(prefix = "") {
      paths <- character()
      marker <- ""
      repeat {
        url <- paste0(
          container_sas_url, "&restype=container&comp=list&prefix=",
          curl_escape(prefix), "&maxresults=5000",
          if (nzchar(marker)) paste0("&marker=", curl_escape(marker))
        )
        response <- curl_fetch_memory(url, handle = new_handle(
          httpheader = "x-ms-version: 2023-11-03"
        ))
        if (response$status_code != 200L) {
          stop(
            "Could not list Azure blobs (HTTP ", response$status_code,
            "). The container SAS needs List permission.",
            call. = FALSE
          )
        }
        listing <- xml2::read_xml(response$content)
        paths <- c(paths, xml2::xml_text(
          xml2::xml_find_all(listing, ".//Blobs/Blob/Name")
        ))
        marker <- xml2::xml_text(xml2::xml_find_first(
          listing, ".//NextMarker"
        ))
        if (is.na(marker) || !nzchar(marker)) break
      }
      paths
    }
  )
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
    fetched_at = Sys.time(),
    run_id = NULL) {
  fetched_at <- as.POSIXct(fetched_at, tz = "UTC")
  snapshot_date <- as.Date(fetched_at, tz = "Australia/Sydney")
  run_id <- run_id %||% paste0(
    format(fetched_at, "%Y%m%dT%H%M%SZ", tz = "UTC"), "-",
    substr(digest(csv_response$content, algo = "sha256"), 1, 12)
  )
  partition <- paste0("snapshot_date=", snapshot_date, "/run_id=", run_id, "/")
  parsed <- tryCatch(
    parse_closure_csv(csv_response$content, snapshot_date, fetched_at, run_id),
    error = identity
  )

  # Save the source before committing the validated snapshot used by export.
  raw_base <- paste0(if (inherits(parsed, "error")) "rejected/" else "raw/", partition)
  store$write(paste0(raw_base, "closure-orders.csv"), csv_response$content, "text/csv")
  store$write(
    paste0(raw_base, "closure-orders.headers.json"),
    charToRaw(toJSON(headers_to_list(csv_response$headers), auto_unbox = TRUE, pretty = TRUE)),
    "application/json"
  )
  if (inherits(parsed, "error")) stop(conditionMessage(parsed), call. = FALSE)

  store$write(
    paste0("snapshots/", partition, "closure-orders.parquet"),
    raw_to_parquet(parsed),
    "application/vnd.apache.parquet"
  )
  message("Saved ", nrow(parsed), " orders for ", snapshot_date, "; run ", run_id)
  invisible(list(snapshot = parsed))
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
  run_tracker(azure_store(container_sas_url), csv_response)
}

if (sys.nframe() == 0L) main()
