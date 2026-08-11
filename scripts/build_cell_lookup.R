# Build a cell -> representative-town lookup (largest place per grid cell).
# Input:  city_cell_mapping.parquet (from citymap.py), rainfall_parquet/ (from scrape.py)
# Output: cell_lookup.parquet -- one row per data cell, labelled with its biggest town.

suppressMessages({library(arrow); library(dplyr)})

cm <- read_parquet("city_cell_mapping.parquet")
ds <- open_dataset("rainfall_parquet")

# all land cells that actually carry rainfall data
cells <- ds |> filter(year == 2025) |> distinct(lat, lon) |> collect() |>
  rename(cell_lat = lat, cell_lon = lon)

# largest place in each cell
rep <- cm |> group_by(cell_lat, cell_lon) |>
  slice_max(population, n = 1, with_ties = FALSE) |> ungroup() |>
  select(cell_lat, cell_lon, name, asciiname, state, population)

# how many named places fall in each cell
cnt <- cm |> count(cell_lat, cell_lon, name = "n_places")

lookup <- cells |>
  left_join(rep, by = c("cell_lat", "cell_lon")) |>
  left_join(cnt, by = c("cell_lat", "cell_lon")) |>
  mutate(n_places = ifelse(is.na(n_places), 0L, n_places)) |>
  arrange(desc(population))

write_parquet(lookup, "cell_lookup.parquet")
cat("cell_lookup.parquet:", nrow(lookup), "cells,",
    sum(!is.na(lookup$name)), "named,", sum(is.na(lookup$name)), "unnamed\n")
