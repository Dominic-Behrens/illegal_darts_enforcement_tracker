# Tests the flat CSV database and daily deduplication.
# Inputs: synthetic tracker runs. Outputs: temporary CSV files.
test_that("CSV keeps all fields and the latest whole snapshot per date", {
  withr::local_dir(file.path("..", ".."))
  source("R/02-export-history.R", local = TRUE)
  root <- withr::local_tempdir()
  output_path <- file.path(withr::local_tempdir(), "closure-orders.csv")
  reason <- 'Reason with comma, "quote" and café'
  run_local(root, c(order_row(name = "Shop A"), order_row(name = "Shop B")),
            "2026-07-21 00:00:00", "first")
  run_local(root, order_row(name = "Shop A", reason = reason, exemption_variation = "Yes"),
            "2026-07-21 01:00:00", "second")
  run_local(root, c(order_row(name = "Shop A", exemption_variation = "Yes"),
                    order_row(name = "Shop B")), "2026-07-23 00:00:00", "third")
  store <- local_store(root)
  expect_no_error(export_history(store, output_path))
  history <- read_csv(output_path, show_col_types = FALSE)
  expect_equal(nrow(history), 3L)
  first_day <- history %>% filter(snapshot_date == as.Date("2026-07-21"))
  expect_equal(first_day$premise_name, "Shop A")
  expect_equal(first_day$exemption_variation, "Yes")
  expect_equal(first_day$reason, reason)
  expect_equal(anyDuplicated(history[c("snapshot_date", "closure_order_id")]), 0L)
  expect_true(all(c("reason", "exemption_variation", "fetched_at", "run_id") %in% names(history)))
  expect_identical(store$read("closure-orders.csv"), read_file_raw(output_path))

  # Rebuilding from the same snapshots must not append duplicate observations.
  expect_no_error(export_history(store, output_path))
  expect_equal(nrow(read_csv(output_path, show_col_types = FALSE)), 3L)
  expect_false(any(grepl("^(changes|current|history|manifest)/", store$list())))
  expect_equal(length(store$list("snapshots/")), 3L)
})

test_that("invalid snapshots cannot overwrite the last good CSV", {
  withr::local_dir(file.path("..", ".."))
  source("R/02-export-history.R", local = TRUE)
  root <- withr::local_tempdir()
  output_path <- file.path(withr::local_tempdir(), "closure-orders.csv")
  store <- local_store(root)
  expect_error(export_history(store, output_path), "No immutable")
  run_local(root, order_row(), "2026-11-06 00:00:00", "first")
  export_history(store, output_path)
  before <- digest(store$read("closure-orders.csv"))
  path <- store$list("snapshots/")[[1]]
  rows <- parquet_to_table(store$read(path)) %>% mutate(snapshot_date = as.Date("2000-01-01"))
  store$write(path, raw_to_parquet(rows))
  expect_error(export_history(store, output_path), "Invalid immutable snapshot")
  expect_equal(digest(store$read("closure-orders.csv")), before)
  expect_equal(digest(read_file_raw(output_path)), before)
})
