# Changelog

## 2026-10-12

### Added
- `scripts/plot_city_comfort_seasons.R`: for the same 12 cities, the chance each
  day of the year is comfortable, 1951-80 vs 1995-2024, with the gap shaded.
  Takes the `fuzzy` argument too.
- Fuzzy comfort score: each cell-day gets `comfort_score` between 0 and 1, the
  product of logistic curves centred on the hard thresholds. The annual table
  gains `comfort_score_days` and `score_observed_days`.
- `fuzzy` argument for `map_comfortable_days.R` and `plot_city_comfort_trends.R`,
  writing `_fuzzy` versions of each chart.
- `scripts/plot_city_comfort_trends.R`: comfortable days a year, 1951-2024, for
  the largest cities, one boxed panel each with a loess trend labelled at both ends.
- Notebooks `explore_rainfall.Rmd` and `hurst_rainfall.Rmd` now in the repo.
- Rendered charts in `outputs/` are now committed.
- `blog-comfortable-weather.md`, this changelog, and README sections on the
  repository layout, notebooks and comfortable-days caveats.

### Changed
- City trends use Nagpur instead of Lucknow, which shares Kanpur's 1°
  temperature cell.
- `kaveri_rainfall.Rmd` reports volumes in TMCFT and drops the `trend` package.
- `.gitignore`: `outputs/` and PNGs no longer ignored; `data/`,
  `comfort_parquet/`, `.posit/` and `Rplots.pdf` ignored.

## 2026-10-11

### Added
- `scripts/download_temperature.py`: IMD 1° daily Tmin/Tmax, 1951-2025, to
  `temperature_parquet/`.
- `scripts/build_comfortable_days.R`: flags every 0.25° cell-day from 1951 as
  comfortable (daily high 15-30°C, low at least 8°C, rain under 15 mm), writing
  `comfort_parquet/` (136M rows) and `data/comfortable_days_annual.parquet`.
- `scripts/map_comfortable_days.R`: maps of average comfortable days
  (1995-2024) and change since 1951-1980.

### Changed
- Comfort maps clipped to India's official boundary with no-data areas left
  white; 20 cities labelled; red-yellow-green scale whose legend spans the
  data range.

## 2026-08-19

### Added
- Exploration and Hurst rainfall notebooks (local only until 2026-10-12).

## 2026-08-12

### Fixed
- Kaveri rainfall made cumulative.

## 2026-08-11

### Added
- Kaveri catchment rainfall analysis: geography fetch and build scripts,
  DuckDB aggregation, `kaveri_rainfall.Rmd` and `blog-post.md`.

### Changed
- Pipeline scripts moved into `scripts/`; one-off code dropped.

## 2026-08-10

### Added
- IMD 0.25° daily rainfall, 1901-2025, to year-partitioned Parquet
  (`scripts/scrape.py`), GeoNames place-to-cell mapping and a largest-town
  label per cell.
