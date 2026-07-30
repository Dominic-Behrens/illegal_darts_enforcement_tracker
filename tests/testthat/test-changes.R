test_that("initial and unchanged snapshots have the expected changes", {
  root <- withr::local_tempdir()
  rows <- c(order_row(name = "Shop A"), order_row(name = "Shop B"))

  first <- run_local(root, rows, "2026-07-21 18:00:00", "run-1")
  second <- run_local(root, rows, "2026-07-22 18:00:00", "run-2")

  expect_equal(first$changes$change_type, c("added", "added"))
  expect_true(all(first$changes$is_initial_snapshot))
  expect_equal(nrow(second$changes), 0L)
  expect_equal(nrow(second$snapshot), 2L)
})

test_that("updates, early removals, expiry and reappearance are distinguished", {
  root <- withr::local_tempdir()
  a <- order_row(name = "Shop A", conclusion = "30-Jul-26")
  b <- order_row(name = "Shop B", conclusion = "30-Jul-26")
  c <- order_row(name = "Shop C", conclusion = "20-Jul-26")
  run_local(root, c(a, b, c), "2026-07-21 18:00:00", "run-1")

  update <- run_local(
    root,
    c(order_row(
      name = "Shop A",
      conclusion = "30-Jul-26",
      exemption_variation = "Yes"
    )),
    "2026-07-22 18:00:00",
    "run-2"
  )
  expect_setequal(
    update$changes$change_type,
    c("updated", "removed_early", "expired")
  )

  reappearance <- run_local(
    root,
    c(
      order_row(
        name = "Shop A",
        conclusion = "30-Jul-26",
        exemption_variation = "Yes"
      ),
      b
    ),
    "2026-07-23 18:00:00",
    "run-3"
  )
  expect_equal(reappearance$changes$change_type, "reappeared")
})

test_that("the new field marks legacy-schema records as updated", {
  root <- withr::local_tempdir()
  first <- run_local(root, order_row(), "2026-07-21 18:00:00", "run-1")
  store <- local_store(root)

  legacy_snapshot <- first$snapshot %>%
    mutate(
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
      )
    ) %>%
    select(-exemption_variation)

  store$write(
    "current/closure-orders.parquet",
    raw_to_parquet(legacy_snapshot)
  )
  store$write(
    "history/closure-orders.parquet",
    raw_to_parquet(legacy_snapshot)
  )

  migrated <- run_local(
    root,
    order_row(),
    "2026-07-22 18:00:00",
    "run-2"
  )
  history <- read_parquet_if_exists(
    store,
    "history/closure-orders.parquet"
  )

  expect_equal(migrated$changes$change_type, "updated")
  expect_equal(history$exemption_variation, c(NA_character_, "No"))
})
