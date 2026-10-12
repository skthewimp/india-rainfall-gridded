# When in the year are the comfortable days? For the same 12 cities as
# plot_city_comfort_trends.R, the chance that each day of the year is
# comfortable, in an early and a recent 30-year window. The gap between the
# two lines shows which part of the year the lost (or gained) days came from.
#
#   outputs/city_comfort_seasons.png
#
# Run with the argument `fuzzy` to use the fuzzy comfort score (the expected
# share of comfortable days) instead; the output then ends in _fuzzy.png.
#
# Run scripts/build_comfortable_days.R first.

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(dplyr)
  library(ggplot2)
})

# ---- Parameters ----
EARLY_YEARS <- 1951:1980
RECENT_YEARS <- 1995:2024   # 2025 left out: provisional
MIN_OBSERVED_SHARE <- 0.9   # drop city-years missing >10% of days
SMOOTH_DAYS <- 15           # centred moving average, wrapping round the year
FUZZY <- "fuzzy" %in% commandArgs(trailingOnly = TRUE)

teal <- "#176d6e"
grey_early <- "grey60"

# Same cities, same order, as the trend chart.
cities <- tribble(
  ~city, ~city_lat, ~city_lon,
  "Mumbai", 19.08, 72.88,
  "Delhi", 28.61, 77.21,
  "Kolkata", 22.57, 88.36,
  "Chennai", 13.08, 80.27,
  "Bengaluru", 12.97, 77.59,
  "Hyderabad", 17.39, 78.49,
  "Ahmedabad", 23.02, 72.57,
  "Pune", 18.52, 73.86,
  "Surat", 21.17, 72.83,
  "Jaipur", 26.91, 75.79,
  "Kanpur", 26.45, 80.33,
  "Nagpur", 21.15, 79.09
)

# ---- Nearest 0.25° grid cell to each city (same rule as the maps) ----
arrow::read_parquet("data/comfortable_days_annual.parquet") ->
  annual

annual %>%
  distinct(lat, lon) %>%
  cross_join(cities) %>%
  mutate(dist2 = (lat - city_lat)^2 + (lon - city_lon)^2) %>%
  slice_min(dist2, n = 1, with_ties = FALSE, by = city) %>%
  select(city, lat, lon) ->
  city_cells

# ---- Daily rows for those cells ----
con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
duckdb_register(con, "city_cells", city_cells)

# lat/lon are stored as FLOAT, so match within a small tolerance rather
# than on exact equality.
daily <- dbGetQuery(con, sprintf("
  SELECT
    c.city,
    d.year,
    CAST(d.date AS DATE) AS date,
    d.comfortable,
    d.comfort_score
  FROM read_parquet('comfort_parquet/year=*/*.parquet', hive_partitioning = true) d
  JOIN city_cells c
    ON abs(d.lat - c.lat) < 0.01
   AND abs(d.lon - c.lon) < 0.01
  WHERE d.year BETWEEN %d AND %d
", min(EARLY_YEARS), max(RECENT_YEARS)))

# One value per day: the 0/1 flag, or the 0-1 fuzzy score. NA = unknown.
daily %>%
  as_tibble() %>%
  mutate(value = if (FUZZY) comfort_score else as.numeric(comfortable)) ->
  daily

# ---- Keep the same city-years as the trend chart ----
daily %>%
  summarise(
    days = n(),
    observed = sum(!is.na(value)),
    .by = c(city, year)
  ) %>%
  filter(observed >= MIN_OBSERVED_SHARE * days) %>%
  select(city, year) ->
  good_city_years

# ---- Probability by day of year, per period ----
# Feb 29 dropped; day of year then runs 1-365 in every year, so 1 Mar is
# always day 60.
daily %>%
  semi_join(good_city_years, by = c("city", "year")) %>%
  filter(format(date, "%m-%d") != "02-29") %>%
  mutate(
    doy = as.integer(format(as.Date(paste0("2001-", format(date, "%m-%d"))), "%j")),
    period = case_when(
      year %in% EARLY_YEARS ~ "early",
      year %in% RECENT_YEARS ~ "recent"
    )
  ) %>%
  filter(!is.na(period), !is.na(value)) %>%
  summarise(
    p_comfortable = mean(value),
    years = n(),
    .by = c(city, period, doy)
  ) %>%
  arrange(city, period, doy) %>%
  # Single days rest on ~30 years each, so smooth over a few weeks. circular
  # = TRUE wraps 31 Dec into 1 Jan.
  mutate(
    p_smooth = as.numeric(stats::filter(
      p_comfortable,
      rep(1 / SMOOTH_DAYS, SMOOTH_DAYS),
      circular = TRUE
    )),
    .by = c(city, period)
  ) %>%
  mutate(city = factor(city, levels = cities %>% pull(city))) ->
  seasonal

# Years behind each period, per city (some temperature cells start late).
seasonal %>%
  summarise(min_years = min(years), max_years = max(years), .by = c(city, period)) %>%
  print(n = Inf)

stopifnot(all(seasonal %>% count(city, period) %>% pull(n) == 365))

# Sanity check: summed probabilities should match the trend chart's period
# averages of comfortable days a year.
seasonal %>%
  summarise(days_a_year = sum(p_comfortable), .by = c(city, period)) %>%
  tidyr::pivot_wider(names_from = period, values_from = days_a_year) %>%
  mutate(change = recent - early) %>%
  print()

# ---- Shading between the lines: where the recent window lost days ----
seasonal %>%
  select(city, doy, period, p_smooth) %>%
  tidyr::pivot_wider(names_from = period, values_from = p_smooth) ->
  gap

# Period labels sit on the Pune panel, where the two lines are furthest
# apart: the early label above its line, the recent one inside the hump under its own.
# Positions are hand-placed from the rendered chart.
# The fuzzy curves peak lower, so their labels sit lower.
label_y <- if (FUZZY) c(0.94, 0.25) else c(1.05, 0.36)

period_labels <- tribble(
  ~city, ~doy, ~label, ~colour,
  "Pune", 228, "1951-80", grey_early,
  "Pune", 224, "1995-2024", teal
) %>%
  mutate(p_smooth = label_y) %>%
  mutate(city = factor(city, levels = cities %>% pull(city)))

month_starts <- as.integer(format(as.Date(sprintf("2001-%02d-01", 1:12)), "%j"))

# ---- Text that differs between the hard and fuzzy versions ----
if (FUZZY) {
  output_suffix <- "_fuzzy"
  measure_text <- "Expected share of each day of the year that is comfortable, fuzzy thresholds"
} else {
  output_suffix <- ""
  measure_text <- "Share of years in which each day of the year was comfortable"
}
chart_title <- "The south lost comfortable monsoon and early-winter days; Delhi and Jaipur gained a few"

# ---- Chart ----
seasonal %>%
  ggplot(aes(doy, p_smooth)) +
  geom_ribbon(
    data = gap,
    aes(x = doy, ymin = pmin(early, recent), ymax = pmax(early, recent)),
    inherit.aes = FALSE,
    fill = teal,
    alpha = 0.12
  ) +
  geom_line(
    data = \(d) filter(d, period == "early"),
    colour = grey_early,
    linewidth = 0.6
  ) +
  geom_line(
    data = \(d) filter(d, period == "recent"),
    colour = teal,
    linewidth = 0.9
  ) +
  geom_text(
    data = cities %>% mutate(city = factor(city, levels = city)),
    aes(x = 4, y = Inf, label = city),
    hjust = 0,
    vjust = 1.6,
    fontface = "bold",
    size = 3.6,
    colour = "grey15"
  ) +
  geom_text(
    data = period_labels,
    aes(label = label, colour = colour),
    size = 2.9,
    fontface = "bold"
  ) +
  scale_colour_identity() +
  facet_wrap(vars(city), ncol = 4) +
  scale_x_continuous(
    breaks = month_starts[c(1, 4, 7, 10)],
    labels = c("Jan", "Apr", "Jul", "Oct"),
    limits = c(1, 365),
    expand = expansion(0)
  ) +
  scale_y_continuous(
    breaks = c(0, 0.5, 1),
    labels = scales::percent,
    limits = c(0, 1.18)
  ) +
  labs(
    title = chart_title,
    subtitle = paste0(
      measure_text,
      ", 1951-80 (grey) and 1995-2024 (teal).\n",
      "Shading marks the gap: where the teal line sits lower, those weeks lost comfortable days."
    ),
    x = NULL,
    y = NULL,
    caption = paste0(
      sprintf("Each day of the year averaged over its years, then smoothed with a %d-day moving average; Feb 29 dropped. ", SMOOTH_DAYS),
      "Years missing over 10% of days are dropped.\n",
      "A comfortable day: daily high 15-30°C, overnight low at least 8°C, and under 15 mm of rain. ",
      "Each city is its nearest grid cell. Source: IMD."
    )
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    plot.title.position = "plot",
    plot.caption.position = "plot",
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(colour = "grey35", margin = margin(b = 10)),
    plot.caption = element_text(colour = "grey45", hjust = 0, size = 7.5, lineheight = 1.1),
    strip.text = element_blank(),
    panel.border = element_rect(colour = "grey75", fill = NA, linewidth = 0.4),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3),
    axis.text = element_text(colour = "grey45", size = 8),
    panel.spacing = unit(6, "pt"),
    plot.margin = margin(14, 16, 10, 14)
  )

ggsave(
  sprintf("outputs/city_comfort_seasons%s.png", output_suffix),
  width = 9,
  height = 7.2,
  dpi = 200,
  bg = "white"
)
