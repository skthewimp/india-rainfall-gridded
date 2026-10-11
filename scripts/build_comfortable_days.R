# Flag every grid-cell-day from 1951 as "comfortable" or not, using IMD
# daily temperature (1° grid) and rainfall (0.25° grid).
#
# Output grain is the 0.25° rainfall grid. Each rainfall cell takes the
# temperature of the 1° cell it sits in, so temperature is blocky at 1° and
# rainfall is at full resolution.
#
# Writes:
#   comfort_parquet/year=YYYY/*.parquet       one row per rainfall cell per day
#   data/comfortable_days_annual.parquet      one row per rainfall cell per year
#
# Run from the repo root after scrape.py and download_temperature.py.

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

# ---- Definition of a comfortable day: change these to change the map ----
# All three conditions must hold. Bounds are inclusive.
TMAX_MIN_C <- 15  # daytime high not cold
TMAX_MAX_C <- 30  # daytime high not hot; >30 is uncomfortable in India
TMIN_MIN_C <- 8   # night not cold (drops north Indian cold-wave weeks)
RAIN_MAX_MM <- 15 # below IMD's "moderate rain" (light rain is 2.5-15.5 mm)

FIRST_YEAR <- 1951 # temperature data starts here

stopifnot(
  dir.exists("rainfall_parquet"),
  dir.exists("temperature_parquet")
)
dir.create("data", showWarnings = FALSE)
if (dir.exists("comfort_parquet")) unlink("comfort_parquet", recursive = TRUE)

con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA threads=4")

dbExecute(con, sprintf("
  CREATE VIEW rainfall AS
  SELECT date, year, lat, lon, rainfall_mm
  FROM read_parquet('rainfall_parquet/year=*/data.parquet', hive_partitioning = true)
  WHERE year >= %d
", FIRST_YEAR))

dbExecute(con, "
  CREATE VIEW temperature AS
  SELECT date, lat, lon, tmin_c, tmax_c
  FROM read_parquet('temperature_parquet/year=*/*.parquet', hive_partitioning = true)
")

# ---- Map each rainfall cell to one temperature cell ----
# 1° temperature cells are centred on x.5 and cover [x, x+1). A rainfall cell
# goes to the temperature cell containing it (rainfall cells exactly on a whole
# degree go to the cell north/east of them).
#
# 60 coastal and border rainfall cells have no temperature cell there. They take
# the nearest temperature cell that exists in any year (ties broken by lat, lon)
# and are flagged with temp_from_neighbour so they can be excluded.
dbExecute(con, "
  CREATE TABLE cell_map AS
  WITH rain_cells AS (
    SELECT DISTINCT lat, lon
    FROM rainfall
  ),
  temp_cells AS (
    SELECT DISTINCT lat, lon
    FROM temperature
  ),
  candidates AS (
    SELECT
      r.lat,
      r.lon,
      t.lat AS temp_lat,
      t.lon AS temp_lon,
      (t.lat = floor(r.lat) + 0.5 AND t.lon = floor(r.lon) + 0.5) AS is_parent,
      (t.lat - r.lat)^2 + (t.lon - r.lon)^2 AS dist2
    FROM rain_cells r
    CROSS JOIN temp_cells t
  )
  SELECT
    lat,
    lon,
    temp_lat,
    temp_lon,
    NOT is_parent AS temp_from_neighbour
  FROM candidates
  QUALIFY row_number() OVER (
    PARTITION BY lat, lon
    ORDER BY is_parent DESC, dist2, temp_lat, temp_lon
  ) = 1
")

map_check <- dbGetQuery(con, "
  SELECT
    count(*) AS cells,
    count(DISTINCT (lat, lon)) AS distinct_cells,
    sum(temp_from_neighbour::INT) AS from_neighbour,
    max(greatest(abs(temp_lat - lat), abs(temp_lon - lon))) AS max_offset_deg
  FROM cell_map
")
print(map_check)
stopifnot(map_check$cells == map_check$distinct_cells)

# ---- Daily flags ----
# comfortable is NULL (unknown) when any input is missing that day - e.g. a
# temperature cell that IMD only covers from 1969, or a missing Tmax value.
dbExecute(con, sprintf("
  COPY (
    SELECT
      r.date,
      r.year,
      r.lat,
      r.lon,
      m.temp_lat,
      m.temp_lon,
      m.temp_from_neighbour,
      t.tmax_c,
      t.tmin_c,
      r.rainfall_mm,
      (
        t.tmax_c BETWEEN %1$s AND %2$s
        AND t.tmin_c >= %3$s
        AND r.rainfall_mm < %4$s
      ) AS comfortable
    FROM rainfall r
    INNER JOIN cell_map m
      ON r.lat = m.lat
     AND r.lon = m.lon
    LEFT JOIN temperature t
      ON t.date = r.date
     AND t.lat = m.temp_lat
     AND t.lon = m.temp_lon
    ORDER BY r.date, r.lat, r.lon
  )
  TO 'comfort_parquet' (FORMAT parquet, PARTITION_BY (year), COMPRESSION zstd)
", TMAX_MIN_C, TMAX_MAX_C, TMIN_MIN_C, RAIN_MAX_MM))

dbExecute(con, "
  CREATE VIEW comfort AS
  SELECT *
  FROM read_parquet('comfort_parquet/year=*/*.parquet', hive_partitioning = true)
")

# Key check: one row per cell per day, and no row lost or duplicated by the join.
key_check <- dbGetQuery(con, "
  SELECT
    (SELECT count(*) FROM comfort) AS rows,
    (SELECT count(*) FROM (SELECT DISTINCT date, lat, lon FROM comfort)) AS distinct_keys,
    (SELECT count(*) FROM rainfall) AS rainfall_rows,
    (SELECT count(comfortable) FROM comfort) AS flagged_rows
")
print(key_check)
stopifnot(
  key_check$rows == key_check$distinct_keys,
  key_check$rows == key_check$rainfall_rows
)

# ---- Annual summary per cell ----
# observed_days counts days with a known flag, so a year with gaps can be
# rescaled or dropped rather than silently undercounted.
dbExecute(con, "
  COPY (
    SELECT
      lat,
      lon,
      year,
      any_value(temp_lat) AS temp_lat,
      any_value(temp_lon) AS temp_lon,
      any_value(temp_from_neighbour) AS temp_from_neighbour,
      count(*) AS days,
      count(comfortable) AS observed_days,
      count(*) FILTER (WHERE comfortable) AS comfortable_days
    FROM comfort
    GROUP BY lat, lon, year
    ORDER BY lat, lon, year
  )
  TO 'data/comfortable_days_annual.parquet' (FORMAT parquet)
")

print(dbGetQuery(con, "
  SELECT
    count(*) AS cell_years,
    count(DISTINCT (lat, lon, year)) AS distinct_cell_years,
    sum(observed_days) / sum(days) AS share_observed
  FROM read_parquet('data/comfortable_days_annual.parquet')
"))
