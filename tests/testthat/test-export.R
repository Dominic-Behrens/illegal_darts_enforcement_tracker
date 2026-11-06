# Tests daily deduplication and history rebuilt from immutable snapshots.
# Inputs: synthetic tracker runs. Outputs: temporary dashboard JSON.
test_that("export keeps the latest complete daily snapshot and derives changes", {
  withr::local_dir(file.path("..", ".."))
  source("R/02-export-dashboard.R", local = TRUE)
  root <- withr::local_tempdir()
  output_path <- file.path(withr::local_tempdir(), "dashboard.json")
  run_local(root, c(order_row(name = "Shop A"), order_row(name = "Shop B")),
            "2026-07-21 00:00:00", "first")
  run_local(root, order_row(name = "Shop A", exemption_variation = "Yes"),
            "2026-07-21 01:00:00", "second")
  run_local(root, c(order_row(name = "Shop A", exemption_variation = "Yes"),
                    order_row(name = "Shop B")), "2026-07-23 00:00:00", "third")
  store <- local_store(root)
  expect_no_error(export_dashboard(store, output_path))
  dashboard <- jsonlite::read_json(output_path, simplifyVector = TRUE)
  expect_equal(nrow(dashboard$observations), 3L)
  expect_equal(sum(dashboard$observations$snapshot_date == "2026-07-21"), 1L)
  expect_equal(sum(dashboard$changes$is_initial_snapshot), 1L)
  # The earlier same-day Shop B observation must not create a reappearance.
  expect_equal(dashboard$changes$change_type, c("added", "added"))
  expect_equal(anyDuplicated(dashboard$observations[c("snapshot_date", "closure_order_id")]), 0L)

  # Old changes/current/history/manifest files are not needed to export.
  expect_false(any(grepl("^(changes|current|history|manifest)/", store$list())))
  expect_equal(length(store$list("snapshots/")), 3L)
})

test_that("empty or invalid snapshot stores cannot publish a dashboard", {
  withr::local_dir(file.path("..", ".."))
  source("R/02-export-dashboard.R", local = TRUE)
  root <- withr::local_tempdir()
  output_path <- file.path(withr::local_tempdir(), "dashboard.json")
  store <- local_store(root)
  expect_error(export_dashboard(store, output_path), "No immutable")
  run_local(root, order_row(), "2026-11-06 00:00:00", "first")
  path <- store$list("snapshots/")[[1]]
  rows <- parquet_to_table(store$read(path)) %>% mutate(snapshot_date = as.Date("2000-01-01"))
  store$write(path, raw_to_parquet(rows))
  expect_error(export_dashboard(store, output_path), "Invalid immutable snapshot")
  expect_false(file.exists(output_path))
})
