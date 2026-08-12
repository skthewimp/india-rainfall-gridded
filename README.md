# India daily gridded rainfall → Parquet

Scripts to turn the India Meteorological Department's 0.25° daily gridded
rainfall archive (NetCDF, one file per year, 1901–2025) into a tidy,
year-partitioned Parquet dataset, plus a mapping from IMD grid cells to Indian
towns and cities.

**No data is shipped in this repo** — only the code. See
[Data & licensing](#data--licensing) for why, and how to fetch the data
yourself.

## What the scripts produce

Run end to end and you get:

| Output | Rows | Size | Built by |
|---|---|---|---|
| `rainfall_parquet/year=YYYY/data.parquet` | 226.6M (all years) | ~400 MB | `scrape.py` |
| `city_cell_mapping.parquet` | 557,995 places → cells | ~10 MB | `citymap.py` |
| `cell_lookup.parquet` | 4,964 cells, one biggest town each | small | `build_cell_lookup.R` |

The rainfall table is long/tidy: `date, lat, lon, rainfall_mm` (+ `year` from
the partition folder). One row per land grid cell per day. Ocean and
out-of-India cells (IMD `_FillValue = -999`) are dropped, which is what shrinks
each 25 MB NetCDF year to ~3.5 MB of Parquet.

## The grid

- 0.25° × 0.25°, 135 longitudes × 129 latitudes, first point at 6.5°N / 66.5°E,
  last at 38.5°N / 100.0°E.
- 4,964 of those ~17,000 grid points sit over Indian land and carry data.
- Each cell is roughly 28 × 28 km — district-sized, not a single town. A cell
  can hold many towns (the Bengaluru cell contains 513 named places) or none
  (457 cells are desert, high Himalaya or dense forest with no named place).

## Setup

Python side (download + NetCDF → Parquet), using [uv](https://docs.astral.sh/uv/):

```bash
uv venv .venv
uv pip install --python .venv/bin/python xarray netCDF4 pandas pyarrow
```

R side (lookup table + charts) needs `arrow`, `dplyr`, `lubridate`, `ggplot2`.
The Kaveri analysis additionally uses `sf`, `duckdb`, `DBI`, `trend`, and
`ggrepel`.

## Run it

```bash
# 1. Download all years 1901–2025 and convert to rainfall_parquet/
#    Resumable: re-running skips years already converted. Deletes each .nc
#    after converting. ~30–45 min, ~3 GB downloaded, polite 2 s delay.
.venv/bin/python scripts/scrape.py

# 2. Map Indian populated places (GeoNames) to their grid cell.
#    Needs IN.txt + admin1.txt (see below).
.venv/bin/python scripts/citymap.py

# 3. Label each cell with its largest town.
Rscript scripts/build_cell_lookup.R
```

For the place mapping, grab the GeoNames dumps first:

```bash
curl -sL https://download.geonames.org/export/dump/IN.zip -o IN.zip && unzip IN.zip IN.txt
curl -sL https://download.geonames.org/export/dump/admin1CodesASCII.txt -o admin1.txt
```

Pipeline scripts live in `scripts/`; run them from the repo root (paths are
root-relative).

## Using the data

Rainfall for any city, across all 125 years — join through the cell lookup:

```r
library(arrow); library(dplyr)

cell <- read_parquet("cell_lookup.parquet") |> filter(name == "Bengaluru")

open_dataset("rainfall_parquet") |>
  filter(lat == cell$cell_lat, lon == cell$cell_lon) |>
  collect()
```

`open_dataset()` is lazy — filters push down to the Parquet files, so pulling
one cell out of 226M rows is quick.

## Kaveri catchment analysis

`kaveri_rainfall.Rmd` maps the Kaveri basin to the IMD grid, then compares
area-weighted monthly and annual rainfall for the whole basin, the Karnataka
portion, and catchments upstream of major dams and gauges. Tributaries are
included through HydroBASINS upstream topology rather than a buffer around the
main river.

Download the external CWC/NWIC, HydroBASINS, HydroRIVERS, and geoBoundaries
files, then build the geography and rainfall aggregates:

```bash
bash scripts/fetch_kaveri_geography.sh
Rscript scripts/build_kaveri_geography.R
Rscript scripts/aggregate_kaveri_rainfall.R
```

The build script creates fractional grid-cell weights for the whole basin and
for Harangi, Hemavathi, KRS, Kabini, Biligundlu, Mettur, Bhavanisagar, and
Amaravathi. The second scans the year-partitioned rainfall Parquet with DuckDB
and writes compact monthly and annual aggregates under `data/`.

The external geometries, derived rainfall tables, and rendered charts remain
untracked. See [`blog-post.md`](blog-post.md) for the findings and caveats.

## Data & licensing

The **code** in this repo is MIT (see `LICENSE`). The **data is not**, and is
deliberately not committed here:

- **Rainfall** — © India Meteorological Department, Pune. High-resolution
  (0.25°) daily gridded rainfall, 1901–2024 (final) + 2025 (real-time /
  provisional). Download the yearly NetCDF files from
  <https://www.imdpune.gov.in/cmpg/Griddata/Rainfall_25_NetCDF.html>. Use is
  subject to IMD's data-supply terms — check them before you redistribute
  anything derived from it.
- **Place names** — from [GeoNames](https://www.geonames.org/), licensed
  CC BY 4.0. The `IN.zip` / `admin1CodesASCII.txt` dumps are downloaded by you,
  not bundled here.

If you only want the code, you have it. If you want the data, the scripts fetch
it for you.

## Caveats worth knowing

- **A cell is not a town.** ~28 km cells; the "largest town per cell" label is a
  convenience, not a gauge reading. Suburbs share their city's cell.
- **1,706 coastal/island places** don't fall inside a data cell and are snapped
  to the nearest one (median snap 10.6 km; a handful of island points are far
  further — check `dist_km` if precision matters).
- **Dates print in IST.** Values are stored at midnight UTC, so R may show
  `05:30:00`. They're daily totals — wrap with `as.Date()`.
- **2025 is provisional.** Treat the current year as real-time data that may be
  revised; 1901–2024 are the final series.
