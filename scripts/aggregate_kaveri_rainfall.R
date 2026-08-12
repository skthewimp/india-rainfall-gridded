# Area-weighted monthly and annual rainfall for the Kaveri basin zones.
# Run scripts/build_kaveri_geography.R first.

suppressPackageStartupMessages({
  library(arrow)
  library(DBI)
  library(dplyr)
  library(duckdb)
})

stopifnot(
  dir.exists("rainfall_parquet"),
  file.exists("data/kaveri_cell_weights.parquet")
)

con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

dbExecute(con, "PRAGMA threads=4")

# Do the large Parquet scan and spatial-weight join inside DuckDB. The daily
# denominator makes a missing cell-day visible and prevents silent undercounting.
monthly <- dbGetQuery(con, "
  WITH weights AS (
    SELECT
      zone_id,
      zone,
      CAST(cell_lat AS FLOAT) AS cell_lat,
      CAST(cell_lon AS FLOAT) AS cell_lon,
      overlap_km2,
      zone_area_km2,
      area_weight
    FROM read_parquet('data/kaveri_cell_weights.parquet')
  ),
  rainfall AS (
    SELECT date, year, lat, lon, rainfall_mm
    FROM read_parquet(
      'rainfall_parquet/year=*/data.parquet',
      hive_partitioning = true
    )
    WHERE lat BETWEEN 9.0 AND 14.75
      AND lon BETWEEN 73.25 AND 81.75
  ),
  daily AS (
    SELECT
      w.zone_id,
      w.zone,
      r.date,
      r.year,
      first(w.zone_area_km2) AS zone_area_km2,
      sum(CAST(r.rainfall_mm AS DOUBLE) * w.area_weight) /
        sum(w.area_weight) AS rainfall_mm,
      sum(w.area_weight) AS area_weight_coverage,
      count(*) AS observed_cells
    FROM rainfall r
    INNER JOIN weights w
      ON r.lat = w.cell_lat
     AND r.lon = w.cell_lon
    GROUP BY w.zone_id, w.zone, r.date, r.year
  )
  SELECT
    zone_id,
    first(zone) AS zone,
    year,
    CAST(extract(month FROM date) AS INTEGER) AS month,
    first(zone_area_km2) AS zone_area_km2,
    sum(rainfall_mm) AS rainfall_mm,
    sum(rainfall_mm) * first(zone_area_km2) * 1e-6 AS rainfall_km3,
    count(*) AS observed_days,
    min(area_weight_coverage) AS min_area_weight_coverage,
    min(observed_cells) AS min_observed_cells
  FROM daily
  GROUP BY zone_id, year, month
  ORDER BY zone_id, year, month
") %>%
  as_tibble()

annual <- monthly %>%
  summarise(
    zone = first(zone),
    zone_area_km2 = first(zone_area_km2),
    rainfall_mm = sum(rainfall_mm),
    rainfall_km3 = sum(rainfall_km3),
    observed_days = sum(observed_days),
    min_area_weight_coverage = min(min_area_weight_coverage),
    min_observed_cells = min(min_observed_cells),
    months = n(),
    .by = c(zone_id, year)
  ) %>%
  arrange(zone_id, year)

stopifnot(
  all(monthly$min_area_weight_coverage > 0.999),
  all(annual$months == 12),
  all(annual$observed_days %in% c(365, 366))
)

write_parquet(monthly, "data/kaveri_rainfall_monthly.parquet")
write_parquet(annual, "data/kaveri_rainfall_annual.parquet")

cat(
  "Kaveri rainfall:",
  nrow(monthly), "zone-months and",
  nrow(annual), "zone-years;",
  min(annual$year), "to", max(annual$year), "\n"
)
