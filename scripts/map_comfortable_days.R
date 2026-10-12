# Maps of comfortable days per year across India, from the annual summary
# built by scripts/build_comfortable_days.R.
#
#   outputs/comfortable_days_map.png         average days a year, recent period
#   outputs/comfortable_days_change_map.png  recent period minus early period
#
# Run with the argument `fuzzy` to map the fuzzy comfort score (expected
# comfortable days) instead; outputs then end in _fuzzy.png.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(sf)
})

sf_use_s2(FALSE) # planar geometry: the grid is a lat/lon lattice

# ---- Parameters ----
RECENT_YEARS <- c(1995, 2024)  # 2025 left out: provisional
EARLY_YEARS <- c(1951, 1980)
MIN_OBSERVED_SHARE <- 0.9      # drop cells missing >10% of days in a period
FUZZY <- "fuzzy" %in% commandArgs(trailingOnly = TRUE)

teal <- "#176d6e"
rust <- "#a65425"
# ColorBrewer RdYlGn: red is the fewest comfortable days, green the most.
comfort_colours <- c(
  "#d73027",
  "#fc8d59",
  "#fee08b",
  "#d9ef8b",
  "#91cf60",
  "#1a9850"
)

# Cities labelled on the maps: the 20 largest urban areas, swapping a few
# near-neighbours (Kanpur, Thane) for regional spread. Each reads the value of
# its nearest grid cell.
cities <- tribble(
  ~city, ~city_lat, ~city_lon,
  "Delhi", 28.61, 77.21,
  "Mumbai", 19.08, 72.88,
  "Kolkata", 22.57, 88.36,
  "Chennai", 13.08, 80.27,
  "Bengaluru", 12.97, 77.59,
  "Hyderabad", 17.39, 78.49,
  "Ahmedabad", 23.02, 72.57,
  "Pune", 18.52, 73.86,
  "Surat", 21.17, 72.83,
  "Jaipur", 26.91, 75.79,
  "Lucknow", 26.85, 80.95,
  "Nagpur", 21.15, 79.09,
  "Indore", 22.72, 75.86,
  "Bhopal", 23.26, 77.41,
  "Patna", 25.59, 85.14,
  "Visakhapatnam", 17.69, 83.22,
  "Kochi", 9.93, 76.27,
  "Guwahati", 26.14, 91.74,
  "Chandigarh", 30.73, 76.78,
  "Srinagar", 34.08, 74.80
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

# DataMeet state boundaries, which follow India's official boundary
# (Ladakh includes Gilgit-Baltistan and Aksai Chin).
read_sf("sources/boundaries/india_adm1.geojson", quiet = TRUE) ->
  states

states %>%
  st_union() ->
  india

# Grid cells as 0.25° squares clipped to India's boundary, so cells don't spill
# over the coast or the border. Areas with no data stay white.
cells_to_squares <- function(cells) {
  cells %>%
    st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>%
    st_buffer(dist = 0.125, endCapStyle = "SQUARE") %>%
    st_intersection(india)
}

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
    mutate(value = round(.data[[value_col]]))
}

label_cities(recent, "comfortable_days") ->
  recent_labels

label_cities(change, "change") ->
  change_labels

cells_to_squares(recent) ->
  recent_squares

cells_to_squares(change) ->
  change_squares

print(recent_labels %>% select(city, value))
print(change_labels %>% select(city, value))

# Colour scales run from the lowest cell to the highest, so both ends of the
# colour range are used. Legend breaks are the two ends plus round numbers
# that are not crowding them.
scale_ends <- function(values) {
  c(floor(min(values)), ceiling(max(values)))
}

end_breaks <- function(values, step) {
  ends <- scale_ends(values)
  inner <- seq(ceiling(ends[1] / step) * step, ends[2], by = step)
  inner <- inner[inner - ends[1] >= step / 2 & ends[2] - inner >= step / 2]
  sort(c(ends, inner))
}

# ---- Shared map styling ----
map_theme <- theme_void(base_size = 10) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    plot.title.position = "plot",
    plot.caption.position = "plot",
    plot.title = element_text(face = "bold", size = 13.5, margin = margin(b = 4)),
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
    geom_label_repel(
      data = labels,
      aes(city_lon, city_lat, label = label_text),
      size = 2.5,
      colour = "grey10",
      fill = alpha("white", 0.85),
      linewidth = 0, # no box border
      label.padding = unit(1.5, "pt"),
      box.padding = unit(3, "pt"),
      point.padding = unit(3, "pt"),
      min.segment.length = 0.3,
      segment.colour = "grey30",
      segment.size = 0.3,
      seed = 1
    )
  )
}

# ---- Text that differs between the hard and fuzzy versions ----
if (FUZZY) {
  output_suffix <- "_fuzzy"
  definition_text <- paste0(
    "Fuzzy comfort: each day scores 0-1. The score is 0.5 at each threshold (daily high 15°C or 30°C, low 8°C, 15 mm of rain)\n",
    "and fades over a few degrees or millimetres either side; a year's scores add up to its expected comfortable days.\n"
  )
  map_subtitle <- "Expected comfortable days a year with fuzzy thresholds, %d-%d.\nA typical grid cell gets about 90."
  change_title <- "With fuzzy thresholds, the Deccan has still lost about four weeks a year"
} else {
  output_suffix <- ""
  definition_text <- "A comfortable day: daily high 15-30°C, overnight low at least 8°C, and under 15 mm of rain.\n"
  map_subtitle <- "Average days a year with comfortable weather, %d-%d.\nA typical grid cell gets about 90."
  change_title <- "The Deccan has lost a month of comfortable days a year to heat"
}

caption_text <- paste0(
  definition_text,
  "No humidity data, so humid coasts look kinder than they feel. Temperature is on IMD's 1° grid (~110 km),\n",
  "so hill stations blur into the plains around them; rainfall is on the 0.25° grid. Source: IMD daily gridded data."
)

# ---- Map 1: comfortable days a year, recent period ----
ggplot() +
  geom_sf(data = india, fill = "white", colour = NA) +
  geom_sf(
    data = recent_squares,
    aes(fill = comfortable_days, colour = comfortable_days),
    linewidth = 0.1
  ) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.2) +
  geom_sf(data = india, fill = NA, colour = "grey35", linewidth = 0.3) +
  city_layers(recent_labels, paste(recent_labels$city, recent_labels$value)) +
  scale_fill_gradientn(
    colours = comfort_colours,
    breaks = end_breaks(recent$comfortable_days, 50),
    limits = scale_ends(recent$comfortable_days),
    name = "Comfortable days a year",
    aesthetics = c("fill", "colour")
  ) +
  coord_sf(xlim = c(67.5, 97.6), ylim = c(6.5, 37.3), expand = FALSE) +
  guides(fill = guide_colourbar(title.position = "top"), colour = "none") +
  labs(
    title = "Comfortable weather lives in the hills, the north-east and Karnataka",
    subtitle = sprintf(
      map_subtitle,
      RECENT_YEARS[1],
      RECENT_YEARS[2]
    ),
    caption = caption_text
  ) +
  map_theme

ggsave(
  sprintf("outputs/comfortable_days_map%s.png", output_suffix),
  width = 7.5,
  height = 8,
  dpi = 200,
  bg = "white"
)

# ---- Map 2: change between the two periods ----
ggplot() +
  geom_sf(data = india, fill = "white", colour = NA) +
  geom_sf(
    data = change_squares,
    aes(fill = change, colour = change),
    linewidth = 0.1
  ) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.2) +
  geom_sf(data = india, fill = NA, colour = "grey35", linewidth = 0.3) +
  city_layers(
    change_labels,
    paste(change_labels$city, sprintf("%+d", as.integer(change_labels$value)))
  ) +
  scale_fill_gradient2(
    low = rust,
    mid = "#f4f2ee",
    high = teal,
    # The midpoint stays at zero, so the smaller gains side never reaches
    # full teal: equal shades mean equal changes in either direction.
    midpoint = 0,
    limits = scale_ends(change$change),
    breaks = end_breaks(change$change, 25),
    labels = function(x) if_else(x == 0, "0", sprintf("%+d", as.integer(x))),
    name = "Change in comfortable days a year",
    aesthetics = c("fill", "colour")
  ) +
  coord_sf(xlim = c(67.5, 97.6), ylim = c(6.5, 37.3), expand = FALSE) +
  guides(fill = guide_colourbar(title.position = "top"), colour = "none") +
  labs(
    title = change_title,
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

ggsave(
  sprintf("outputs/comfortable_days_change_map%s.png", output_suffix),
  width = 7.5,
  height = 8,
  dpi = 200,
  bg = "white"
)
