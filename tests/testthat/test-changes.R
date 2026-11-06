# Change classifications are derived from snapshots during dashboard export.
test_that("snapshot changes distinguish baseline, updates, removals and returns", {
  first <- parse_closure_csv(
    csv_bytes(c(order_row(name = "Shop A", conclusion = "30-Jul-26"),
                order_row(name = "Shop B", conclusion = "30-Jul-26"),
                order_row(name = "Shop C", conclusion = "20-Jul-26"))),
    as.Date("2026-07-22"), as.POSIXct("2026-07-22", tz = "UTC"), "first"
  )
  baseline <- derive_changes(first, NULL, NULL, TRUE)
  expect_equal(baseline$change_type, rep("added", 3))
  expect_true(all(baseline$is_initial_snapshot))
  expect_equal(nrow(derive_changes(first, first, first, FALSE)), 0L)

  second <- parse_closure_csv(
    csv_bytes(order_row(name = "Shop A", conclusion = "30-Jul-26", exemption_variation = "Yes")),
    as.Date("2026-07-23"), as.POSIXct("2026-07-23", tz = "UTC"), "second"
  )
  expect_setequal(derive_changes(second, first, first, FALSE)$change_type,
                  c("updated", "removed_early", "expired"))
  third <- first %>%
    filter(premise_name != "Shop C") %>%
    mutate(snapshot_date = as.Date("2026-07-24"),
           fetched_at = as.POSIXct("2026-07-24", tz = "UTC"), run_id = "third",
           exemption_variation = if_else(premise_name == "Shop A", "Yes", exemption_variation),
           record_hash = if_else(premise_name == "Shop A", second$record_hash[[1]], record_hash))
  expect_equal(derive_changes(third, second, bind_rows(first, second), FALSE)$change_type,
               "reappeared")
})
