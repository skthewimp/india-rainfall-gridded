# Comfortable days per year, 1951-2024, for India's 12 largest cities.
# One panel per city, ordered by population; a dot per year and a loess trend.
#
#   outputs/city_comfortable_days.png
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

teal <- "#176d6e"

# 12 largest urban agglomerations, Census 2011, in descending order.
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
  "Lucknow", 26.85, 80.95
)

# ---- Data ----
read_parquet("data/comfortable_days_annual.parquet") ->
  annual

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

# Trend values at both ends, labelled on each panel.
city_years %>%
  filter(year == min(year) | year == max(year), .by = city) %>%
  mutate(
    hjust = if_else(year == min(year), 1.2, -0.2),
    .by = city
  ) ->
  trend_ends

print(trend_ends %>% select(city, year, trend))

# ---- Chart ----
city_years %>%
  ggplot(aes(year, comfortable)) +
  geom_point(colour = "grey70", size = 0.8) +
  geom_line(aes(y = trend), colour = teal, linewidth = 0.9) +
  geom_point(data = trend_ends, aes(y = trend), colour = teal, size = 1.6) +
  geom_text(
    data = trend_ends,
    aes(y = trend, label = round(trend), hjust = hjust),
    colour = teal,
    size = 2.8,
    fontface = "bold"
  ) +
  facet_wrap(vars(city), ncol = 4) +
  scale_x_continuous(
    breaks = c(1960, 1990, 2020),
    expand = expansion(mult = 0.15)
  ) +
  scale_y_continuous(breaks = seq(0, 300, 100)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "Bengaluru, Chennai and Hyderabad have lost a third or more of their comfortable days",
    subtitle = paste0(
      "Comfortable days a year, 1951-2024; northern cities are flat or slightly up. ",
      "Dots are years; the line is a loess trend, labelled at each end."
    ),
    x = NULL,
    y = NULL,
    caption = paste0(
      "A comfortable day: daily high 15-30°C, overnight low at least 8°C, and under 15 mm of rain. ",
      "Each city is its nearest grid cell: rainfall on IMD's 0.25° grid,\n",
      "temperature on its 1° grid. Cities are the 12 largest urban agglomerations (Census 2011), ",
      "largest first. Years missing over 10% of days are dropped. Source: IMD."
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
    strip.text = element_text(face = "bold", hjust = 0, size = 10),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3),
    axis.text = element_text(colour = "grey45", size = 8),
    panel.spacing.x = unit(14, "pt"),
    panel.spacing.y = unit(10, "pt"),
    plot.margin = margin(14, 16, 10, 14)
  )

ggsave("outputs/city_comfortable_days.png", width = 9, height = 7, dpi = 200, bg = "white")
