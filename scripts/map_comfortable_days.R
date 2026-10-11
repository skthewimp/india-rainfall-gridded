# Maps of comfortable days per year across India, from the annual summary
# built by scripts/build_comfortable_days.R.
#
#   outputs/comfortable_days_map.png         average days a year, recent period
#   outputs/comfortable_days_change_map.png  recent period minus early period

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ggplot2)
  library(sf)
})

# ---- Parameters ----
RECENT_YEARS <- c(1995, 2024)  # 2025 left out: provisional
EARLY_YEARS <- c(1951, 1980)
MIN_OBSERVED_SHARE <- 0.9      # drop cells missing >10% of days in a period

teal <- "#176d6e"
rust <- "#a65425"
comfort_colours <- c(
  "#f6d9f2", # pink: fewest comfortable days
  "#c3a6ea",
  "#6fb1ee", # blue
  "#3fbfa6",
  "#9ad15a", # green
  "#f5df45", # yellow
  "#f39c33", # orange
  "#cf2a1e"  # red: most comfortable days
)

# Cities labelled on the maps. Each reads the value of its nearest grid cell.
# side is where the label sits relative to the point.
cities <- tribble(
  ~city, ~city_lat, ~city_lon, ~side,
  "Delhi", 28.61, 77.21, "right",
  "Mumbai", 19.08, 72.88, "right",
  "Chennai", 13.08, 80.27, "right",
  "Kolkata", 22.57, 88.36, "right",
  "Bengaluru", 12.97, 77.59, "left",
  "Hyderabad", 17.39, 78.49, "right",
  "Pune", 18.52, 73.86, "right",
  "Jaipur", 26.91, 75.79, "right",
  "Srinagar", 34.08, 74.80, "right"
)

# ---- Data ----
read_parquet("data/comfortable_days_annual.parquet") ->
  annual

read_sf("sources/boundaries/india_adm1.geojson", quiet = TRUE) ->
  states

# Average comfortable days a year over a period. Days with a missing flag are
# left out of the denominator, then the rate is scaled to a 365.25-day year.
period_average <- function(years) {
  annual %>%
    filter(between(year, years[1], years[2])) %>%
    summarise(
      observed_share = sum(observed_days) / sum(days),
      comfortable_days = sum(comfortable_days) / sum(observed_days) * 365.25,
      .by = c(lat, lon)
    ) %>%
    filter(observed_share >= MIN_OBSERVED_SHARE)
}

period_average(RECENT_YEARS) ->
  recent

period_average(EARLY_YEARS) ->
  early

recent %>%
  inner_join(early, by = c("lat", "lon"), suffix = c("_recent", "_early")) %>%
  mutate(change = comfortable_days_recent - comfortable_days_early) ->
  change

# Attach the nearest cell's value to each city.
label_cities <- function(cells, value_col) {
  cities %>%
    cross_join(cells) %>%
    mutate(dist2 = (lat - city_lat)^2 + (lon - city_lon)^2) %>%
    slice_min(dist2, n = 1, with_ties = FALSE, by = city) %>%
    mutate(
      value = round(.data[[value_col]]),
      label_lon = if_else(side == "left", city_lon - 0.45, city_lon + 0.45),
      hjust = if_else(side == "left", 1, 0)
    )
}

label_cities(recent, "comfortable_days") ->
  recent_labels

label_cities(change, "change") ->
  change_labels

print(recent_labels %>% select(city, value))
print(change_labels %>% select(city, value))

# ---- Shared map styling ----
map_theme <- theme_void(base_size = 10) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    plot.title.position = "plot",
    plot.caption.position = "plot",
    plot.title = element_text(face = "bold", size = 14.5, margin = margin(b = 4)),
    plot.subtitle = element_text(colour = "grey35", margin = margin(b = 6)),
    plot.caption = element_text(colour = "grey45", hjust = 0, size = 7.5, lineheight = 1.1),
    legend.position = "top",
    legend.justification = "left",
    legend.title = element_text(colour = "grey30", size = 8.5),
    legend.text = element_text(colour = "grey30", size = 8),
    legend.key.height = unit(7, "pt"),
    legend.key.width = unit(48, "pt"),
    plot.margin = margin(14, 14, 10, 14)
  )

city_layers <- function(labels, label_text) {
  list(
    geom_point(
      data = labels,
      aes(city_lon, city_lat),
      shape = 21,
      fill = "white",
      colour = "grey15",
      size = 1.6,
      stroke = 0.5
    ),
    geom_label(
      data = labels,
      aes(label_lon, city_lat, label = label_text, hjust = hjust),
      size = 2.7,
      colour = "grey10",
      fill = alpha("white", 0.8),
      linewidth = 0,
      label.padding = unit(1.5, "pt")
    )
  )
}

caption_text <- paste0(
  "A comfortable day: daily high 15-30°C, overnight low at least 8°C, and under 15 mm of rain.\n",
  "No humidity data, so humid coasts look kinder than they feel. Temperature is on IMD's 1° grid (~110 km),\n",
  "so hill stations blur into the plains around them; rainfall is on the 0.25° grid. Source: IMD daily gridded data."
)

# ---- Map 1: comfortable days a year, recent period ----
ggplot() +
  geom_tile(
    data = recent,
    aes(lon, lat, fill = comfortable_days),
    width = 0.25,
    height = 0.25
  ) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.2) +
  city_layers(recent_labels, paste(recent_labels$city, recent_labels$value)) +
  # Pink-blue-green-yellow-red scale after the South America map this copies:
  # red is the most comfortable.
  scale_fill_gradientn(
    colours = comfort_colours,
    breaks = c(0, 50, 100, 150, 200, 250, 300),
    limits = c(0, 300),
    name = "Comfortable days a year"
  ) +
  coord_sf(xlim = c(67.5, 97.6), ylim = c(6.5, 37.3), expand = FALSE) +
  guides(fill = guide_colourbar(title.position = "top")) +
  labs(
    title = "Comfortable weather lives in the hills, the north-east and Karnataka",
    subtitle = sprintf(
      "Average days a year with comfortable weather, %d-%d.\nA typical grid cell gets about 90.",
      RECENT_YEARS[1],
      RECENT_YEARS[2]
    ),
    caption = caption_text
  ) +
  map_theme

ggsave("outputs/comfortable_days_map.png", width = 7.5, height = 8, dpi = 200, bg = "white")

# ---- Map 2: change between the two periods ----
change_limit <- 50

ggplot() +
  geom_tile(
    data = change,
    aes(lon, lat, fill = change),
    width = 0.25,
    height = 0.25
  ) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.2) +
  city_layers(
    change_labels,
    paste(change_labels$city, sprintf("%+d", as.integer(change_labels$value)))
  ) +
  scale_fill_gradient2(
    low = rust,
    mid = "#f4f2ee",
    high = teal,
    midpoint = 0,
    limits = c(-change_limit, change_limit),
    oob = scales::squish,
    breaks = c(-50, -25, 0, 25, 50),
    labels = c("-50 or more", "-25", "0", "+25", "+50 or more"),
    name = "Change in comfortable days a year"
  ) +
  coord_sf(xlim = c(67.5, 97.6), ylim = c(6.5, 37.3), expand = FALSE) +
  guides(fill = guide_colourbar(title.position = "top")) +
  labs(
    title = "The Deccan has lost a month of comfortable days a year to heat",
    subtitle = sprintf(
      "Change in comfortable days a year, %d-%d vs %d-%d.\nThe north-west gained a few as its winter nights got warmer.",
      RECENT_YEARS[1],
      RECENT_YEARS[2],
      EARLY_YEARS[1],
      EARLY_YEARS[2]
    ),
    caption = caption_text
  ) +
  map_theme

ggsave("outputs/comfortable_days_change_map.png", width = 7.5, height = 8, dpi = 200, bg = "white")
