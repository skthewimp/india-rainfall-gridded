# Comfortable days per year, 1951-2024, for 12 of India's largest cities.
# One panel per city, ordered by population; a dot per year and a loess trend.
#
#   outputs/city_comfortable_days.png
#
# Run with the argument `fuzzy` to plot the fuzzy comfort score (expected
# comfortable days) instead; the output then ends in _fuzzy.png.
#
# Run scripts/build_comfortable_days.R first.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ggplot2)
})

# ---- Parameters ----
LAST_YEAR <- 2024          # 2025 left out: provisional
MIN_OBSERVED_SHARE <- 0.9  # drop years missing >10% of days
LOESS_SPAN <- 0.75
FUZZY <- "fuzzy" %in% commandArgs(trailingOnly = TRUE)

teal <- "#176d6e"

# Largest urban agglomerations, Census 2011, in descending order. Lucknow
# (12th) shares Kanpur's 1° temperature cell, so Nagpur (13th) replaces it.
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

# ---- Data ----
read_parquet("data/comfortable_days_annual.parquet") ->
  annual

# In fuzzy mode, swap in the summed scores and their own denominator; the rest
# of the script then runs unchanged.
if (FUZZY) {
  annual %>%
    mutate(
      comfortable_days = comfort_score_days,
      observed_days = score_observed_days
    ) ->
    annual
}

# Each city reads its nearest 0.25° grid cell (same rule as the maps).
annual %>%
  distinct(lat, lon) %>%
  cross_join(cities) %>%
  mutate(dist2 = (lat - city_lat)^2 + (lon - city_lon)^2) %>%
  slice_min(dist2, n = 1, with_ties = FALSE, by = city) %>%
  select(city, lat, lon) ->
  city_cells

# Years with a few missing days are scaled up to a full year; years missing
# more than 10% are dropped.
annual %>%
  inner_join(city_cells, by = c("lat", "lon")) %>%
  filter(
    year <= LAST_YEAR,
    observed_days >= MIN_OBSERVED_SHARE * days
  ) %>%
  mutate(comfortable = comfortable_days / observed_days * days) %>%
  mutate(
    trend = predict(loess(comfortable ~ year, span = LOESS_SPAN)),
    .by = city
  ) %>%
  mutate(city = factor(city, levels = cities %>% pull(city))) ->
  city_years

city_years %>%
  summarise(
    years = n(),
    first_year = min(year),
    .by = city
  ) %>%
  print()

# Trend values at both ends, labelled on each panel, set a few years out
# from the end point so they clear the line and the dots.
LABEL_GAP_YEARS <- 3

city_years %>%
  filter(year == min(year) | year == max(year), .by = city) %>%
  mutate(
    is_start = year == min(year),
    label_x = if_else(is_start, year - LABEL_GAP_YEARS, year + LABEL_GAP_YEARS),
    hjust = if_else(is_start, 1, 0),
    .by = city
  ) ->
  trend_ends

print(trend_ends %>% select(city, year, trend))

# ---- Text that differs between the hard and fuzzy versions ----
if (FUZZY) {
  output_suffix <- "_fuzzy"
  chart_title <- "With fuzzy thresholds too, Bengaluru, Chennai and Hyderabad lost 30-46% of comfortable days"
  measure_text <- "Expected comfortable days a year with fuzzy thresholds"
  definition_text <- paste0(
    "Fuzzy comfort: each day scores 0-1, 0.5 at each threshold (high 15°C or 30°C, low 8°C, 15 mm of rain) ",
    "and fading over a few degrees or mm either side.\n"
  )
} else {
  output_suffix <- ""
  chart_title <- "Bengaluru, Chennai and Hyderabad have lost a third or more of their comfortable days"
  measure_text <- "Comfortable days a year"
  definition_text <- "A comfortable day: daily high 15-30°C, overnight low at least 8°C, and under 15 mm of rain.\n"
}

# ---- Chart ----
city_years %>%
  ggplot(aes(year, comfortable)) +
  geom_point(colour = "grey70", size = 0.8) +
  # City name inside its own boxed panel, so it can't be read as belonging
  # to the panel above.
  geom_text(
    data = cities %>% mutate(city = factor(city, levels = city)),
    aes(x = 1939, y = Inf, label = city),
    hjust = 0,
    vjust = 1.6,
    fontface = "bold",
    size = 3.6,
    colour = "grey15"
  ) +
  geom_line(aes(y = trend), colour = teal, linewidth = 0.9) +
  geom_point(data = trend_ends, aes(y = trend), colour = teal, size = 1.6) +
  geom_text(
    data = trend_ends,
    aes(x = label_x, y = trend, label = round(trend), hjust = hjust),
    colour = teal,
    size = 2.8,
    fontface = "bold"
  ) +
  facet_wrap(vars(city), ncol = 4) +
  scale_x_continuous(
    breaks = c(1960, 1990, 2020),
    # Fixed limits leave room for the end labels and the city name.
    limits = c(1936, 2037),
    expand = expansion(0)
  ) +
  scale_y_continuous(
    breaks = seq(0, 200, 100),
    limits = c(0, 300)
  ) +
  coord_cartesian(clip = "off") +
  labs(
    title = chart_title,
    subtitle = paste0(
      measure_text,
      ", 1951-2024; northern cities are flat or slightly up.\n",
      "Dots are years; the line is a loess trend, labelled at each end."
    ),
    x = NULL,
    y = NULL,
    caption = paste0(
      definition_text,
      "Each city is its nearest grid cell: rainfall on IMD's 0.25° grid, temperature on its 1° grid. ",
      "Years missing over 10% of days are dropped.\n",
      "Cities are the largest urban agglomerations (Census 2011), largest first; ",
      "Nagpur replaces Lucknow, which shares Kanpur's temperature cell. Source: IMD."
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
  sprintf("outputs/city_comfortable_days%s.png", output_suffix),
  width = 9,
  height = 7.2,
  dpi = 200,
  bg = "white"
)
