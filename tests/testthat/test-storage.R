test_that("local storage round-trips Parquet data", {
  root <- withr::local_tempdir()
  store <- local_store(root)
  table <- empty_snapshot()
  table <- bind_rows(table, tibble(
    closure_order_id = "id", premise_name = "Shop", address = "Address",
    council = "Council", latitude = NA_real_, longitude = NA_real_,
    closure_order_type = "Short", date_commenced = as.Date("2026-07-20"),
    conclusion_date = as.Date("2026-10-18"), reason = "Reason",
    record_hash = "hash", snapshot_date = as.Date("2026-07-21"),
    fetched_at = as.POSIXct("2026-07-21", tz = "UTC"), run_id = "run"
  ))

  store$write("test/table.parquet", raw_to_parquet(table))
  restored <- parquet_to_table(store$read("test/table.parquet"))

  expect_equal(restored, table)
})

test_that("invalid input cannot alter last-good current or history", {
  root <- withr::local_tempdir()
  store <- local_store(root)
  run_local(root, order_row(), "2026-07-21 18:00:00", "good-run")
  before_current <- digest(store$read("current/closure-orders.parquet"))
  before_history <- digest(store$read("history/closure-orders.parquet"))

  expect_error(
    run_tracker(
      store,
      fake_response(charToRaw("bad,data\n1,2")),
      fetched_at = as.POSIXct("2026-07-22 18:00:00", tz = "UTC"),
      run_id = "bad-run"
    ),
    "missing required"
  )

  expect_equal(digest(store$read("current/closure-orders.parquet")), before_current)
  expect_equal(digest(store$read("history/closure-orders.parquet")), before_history)
  expect_true(store$exists(paste0(
    "rejected/snapshot_date=2026-07-23/run_id=bad-run/closure-orders.csv"
  )))
})
