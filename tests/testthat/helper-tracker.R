source(testthat::test_path("..", "..", "R", "01-update-closure-orders.R"))

csv_bytes <- function(rows) {
  header <- paste(
    "Premises name,Address,Council,Closure Order Type,",
    "Date Commenced,Conclusion,Reason",
    sep = ""
  )
  charToRaw(paste(c(header, rows), collapse = "\n"))
}

fake_response <- function(bytes) {
  list(
    status_code = 200L,
    content = bytes,
    headers = charToRaw(paste0(
      "HTTP/1.1 200 OK\r\n",
      "ETag: test-etag\r\n",
      "Last-Modified: Tue, 21 Jul 2026 00:00:00 GMT\r\n\r\n"
    ))
  )
}

order_row <- function(
    name = "Test Shop",
    address = "1 Test Street, Sydney NSW 2000",
    council = "Sydney",
    type = "Short",
    commenced = "20-Jul-26",
    conclusion = "18-Oct-26",
    reason = "Sale of illicit tobacco") {
  csv_quote <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  paste(
    csv_quote(name),
    csv_quote(address),
    csv_quote(council),
    csv_quote(type),
    csv_quote(commenced),
    csv_quote(conclusion),
    csv_quote(reason),
    sep = ","
  )
}

run_local <- function(root, rows, when, run_id) {
  run_tracker(
    local_store(root),
    fake_response(csv_bytes(rows)),
    fetched_at = as.POSIXct(when, tz = "UTC"),
    run_id = run_id
  )
}
