test_that("BOM, multiline fields and whitespace are normalised", {
  bytes <- csv_bytes(order_row(
    name = "  Test\u00a0 Shop  ",
    reason = "First line\nsecond line",
    exemption_variation = "  Yes  "
  ))
  bytes <- c(charToRaw("\ufeff"), bytes)

  parsed <- parse_closure_csv(
    bytes,
    as.Date("2026-07-21"),
    as.POSIXct("2026-07-21 18:00:00", tz = "UTC"),
    "test-run"
  )

  expect_equal(parsed$premise_name, "Test Shop")
  expect_equal(parsed$reason, "First line second line")
  expect_equal(parsed$exemption_variation, "Yes")
  expect_equal(parsed$date_commenced, as.Date("2026-07-20"))
  expect_equal(parsed$conclusion_date, as.Date("2026-10-18"))
  expect_true(is.na(parsed$latitude))
  expect_true(is.na(parsed$longitude))
})

test_that("IDs and record hashes are deterministic", {
  first <- parse_closure_csv(
    csv_bytes(order_row()), as.Date("2026-07-21"),
    as.POSIXct("2026-07-21", tz = "UTC"), "one"
  )
  second <- parse_closure_csv(
    csv_bytes(order_row()), as.Date("2026-07-22"),
    as.POSIXct("2026-07-22", tz = "UTC"), "two"
  )
  changed <- parse_closure_csv(
    csv_bytes(order_row(exemption_variation = "Yes")), as.Date("2026-07-22"),
    as.POSIXct("2026-07-22", tz = "UTC"), "three"
  )

  expect_equal(first$closure_order_id, second$closure_order_id)
  expect_equal(first$record_hash, second$record_hash)
  expect_equal(first$closure_order_id, changed$closure_order_id)
  expect_false(first$record_hash == changed$record_hash)
})

test_that("the current official source headings are mapped", {
  header <- paste(
    "Premise name,Address,Council,Latitude,Longitude,",
    "Short or long term closure order,Date commenced,",
    "Conclusion of closure order,Reason for closure order,",
    "Exemption/variation",
    sep = ""
  )
  row <- paste(
    '"Test Shop","1 Test Street","Sydney",-33.86,151.21,',
    '"Short","20-Jul-26","18-Oct-26","Reason","Yes"',
    sep = ""
  )

  parsed <- parse_closure_csv(
    charToRaw(paste(header, row, sep = "\n")),
    as.Date("2026-07-21"),
    as.POSIXct("2026-07-21", tz = "UTC"),
    "test"
  )

  expect_equal(parsed$closure_order_type, "Short")
  expect_equal(parsed$latitude, -33.86)
  expect_equal(parsed$longitude, 151.21)
  expect_equal(parsed$exemption_variation, "Yes")
})

test_that("schema, dates, keys and ID uniqueness are validated", {
  bad_schema <- charToRaw("Premises name,Address\nShop,Somewhere")
  bad_date <- csv_bytes(order_row(commenced = "not a date"))
  missing_key <- csv_bytes(order_row(name = ""))
  duplicate <- csv_bytes(c(order_row(), order_row(reason = "Different")))

  parse <- function(bytes) parse_closure_csv(
    bytes, as.Date("2026-07-21"),
    as.POSIXct("2026-07-21", tz = "UTC"), "test"
  )

  expect_error(parse(bad_schema), "missing required")
  expect_error(parse(bad_date), "Invalid date_commenced")
  expect_error(parse(missing_key), "missing closure-order key")
  expect_error(parse(duplicate), "duplicate closure_order_id")
  expect_error(parse(raw()), "empty")
})
