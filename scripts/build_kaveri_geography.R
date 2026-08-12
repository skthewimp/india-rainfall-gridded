# Build the Kaveri basin, dam-checkpoint catchments, and IMD cell weights.
#
# Outer basin: CWC/NWIC basin boundary.
# Upstream checkpoint catchments and rivers: HydroBASINS/HydroRIVERS v1.
# State boundary: geoBoundaries ADM1.
#
# Source downloads:
# https://nwdp.nwic.gov.in/dataset/basin-cwc
# https://www.hydrosheds.org/products/hydrobasins
# https://www.hydrosheds.org/products/hydrorivers
# https://www.geoboundaries.org/api/current/gbOpen/IND/ADM1/

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(patchwork)
  library(sf)
  library(tibble)
})

sf_use_s2(FALSE)

# Equal-area CRS for unions, intersections, and cell weights.
area_crs <- 6933

dir.create("data", showWarnings = FALSE)
dir.create("outputs", showWarnings = FALSE)

basin_path <- "sources/boundaries/basin_cwc.GeoJSON"
state_path <- "sources/boundaries/india_adm1.geojson"
hybas_path <- "sources/hydrobasins/hybas_as_lev12_v1c.shp"
river_path <- paste0(
  "sources/hydrorivers/HydroRIVERS_v10_as_shp/",
  "HydroRIVERS_v10_as.shp"
)

stopifnot(
  file.exists(basin_path),
  file.exists(state_path),
  file.exists(hybas_path),
  file.exists(river_path),
  file.exists("cell_lookup.parquet")
)

# Read only southern India from the two large HydroSHEDS layers.
bbox_wgs84 <- st_as_sfc(
  st_bbox(c(xmin = 73.5, ymin = 9.5, xmax = 81.5, ymax = 14.5), crs = 4326)
)

cwc_basins <- st_read(basin_path, quiet = TRUE) %>%
  st_make_valid()

cwc_kaveri <- cwc_basins %>%
  filter(ba_name == "Cauvery") %>%
  st_transform(area_crs) %>%
  summarise(
    cwc_area_sqkm = first(area_sqkm),
    source = "CWC/NWIC basin boundary"
  ) %>%
  st_transform(4326)

states <- st_read(state_path, quiet = TRUE) %>%
  st_make_valid() %>%
  st_transform(4326)

karnataka <- states %>%
  filter(shapeISO == "IN-KA")

hybas_local <- st_read(
  hybas_path,
  wkt_filter = st_as_text(bbox_wgs84),
  quiet = TRUE
) %>%
  st_make_valid()

# The level-12 polygon at the Kaveri outlet has MAIN_BAS 4120028760.
# Selecting this ID retains the full tributary topology, not a river buffer.
kaveri_main_basin <- 4120028760

hybas_kaveri <- hybas_local %>%
  filter(MAIN_BAS == kaveri_main_basin)

hybas_kaveri_area <- st_transform(hybas_kaveri, area_crs)

rivers <- st_read(
  river_path,
  wkt_filter = st_as_text(bbox_wgs84),
  quiet = TRUE
) %>%
  filter(HYBAS_L12 %in% hybas_kaveri$HYBAS_ID) %>%
  st_make_valid()

# Coordinates are used only to identify the containing HydroBASINS polygon.
# HydroBASINS level 12 then supplies the upstream topology.
checkpoints <- tribble(
  ~zone_id, ~checkpoint, ~kind, ~river, ~lon, ~lat, ~reported_area_km2, ~coordinate_source,
  "upstream_harangi", "Harangi", "dam", "Harangi", 75.90556, 12.49167, NA_real_, "GeoNames/Wikidata",
  "upstream_hemavathi", "Hemavathi", "dam", "Hemavathi", 76.05453, 12.82216, 2810, "Wikidata; Hassan district",
  "upstream_krs", "KRS", "dam", "Kaveri", 76.57214, 12.42437, 10619, "Apple Maps; CWC catchment area",
  "upstream_kabini", "Kabini", "dam", "Kabini", 76.34887, 11.98951, 2142, "IWAI/CWC",
  "upstream_biligundlu", "Biligundlu", "gauge", "Kaveri", 77.72389, 12.18222, 36682, "CWC hydrological station",
  "upstream_mettur", "Mettur", "dam", "Kaveri", 77.82315, 11.80505, 42217, "GeoNames; CWC catchment area",
  "upstream_bhavanisagar", "Bhavanisagar", "dam", "Bhavani", 77.11389, 11.47083, NA_real_, "Wikidata",
  "upstream_amaravathi", "Amaravathi", "dam", "Amaravathi", 77.26000, 10.41067, 829, "Tamil Nadu WRD/Wikidata"
)

checkpoint_sf <- st_as_sf(
  checkpoints,
  coords = c("lon", "lat"),
  crs = 4326,
  remove = FALSE
)

checkpoint_match <- st_intersects(
  st_transform(checkpoint_sf, area_crs),
  hybas_kaveri_area
)
stopifnot(lengths(checkpoint_match) == 1)

checkpoint_sf$target_hybas_id <- vapply(
  checkpoint_match,
  function(i) hybas_kaveri$HYBAS_ID[i],
  numeric(1)
)

upstream_ids <- function(target_id, basins) {
  ids <- target_id

  repeat {
    new_ids <- basins$HYBAS_ID[basins$NEXT_DOWN %in% ids]
    next_ids <- union(ids, new_ids)

    if (length(next_ids) == length(ids)) break
    ids <- next_ids
  }

  ids
}

checkpoint_zones <- lapply(seq_len(nrow(checkpoint_sf)), function(i) {
  ids <- upstream_ids(checkpoint_sf$target_hybas_id[i], hybas_kaveri)

  hybas_kaveri_area %>%
    filter(HYBAS_ID %in% ids) %>%
    summarise() %>%
    st_transform(4326) %>%
    mutate(
      zone_id = checkpoint_sf$zone_id[i],
      zone = paste("Upstream of", checkpoint_sf$checkpoint[i]),
      zone_type = checkpoint_sf$kind[i],
      checkpoint = checkpoint_sf$checkpoint[i],
      river = checkpoint_sf$river[i],
      target_hybas_id = checkpoint_sf$target_hybas_id[i],
      hydrobasins_up_area_km2 = hybas_kaveri$UP_AREA[
        match(checkpoint_sf$target_hybas_id[i], hybas_kaveri$HYBAS_ID)
      ],
      reported_area_km2 = checkpoint_sf$reported_area_km2[i]
    )
}) %>%
  bind_rows()

whole_zone <- cwc_kaveri %>%
  transmute(
    zone_id = "whole_basin",
    zone = "Whole Kaveri basin",
    zone_type = "basin",
    checkpoint = NA_character_,
    river = "Kaveri",
    target_hybas_id = NA_real_,
    hydrobasins_up_area_km2 = NA_real_,
    reported_area_km2 = cwc_area_sqkm
  )

karnataka_zone <- st_intersection(
  st_transform(cwc_kaveri, area_crs),
  st_transform(karnataka, area_crs)
) %>%
  summarise() %>%
  st_transform(4326) %>%
  transmute(
    zone_id = "within_karnataka",
    zone = "Kaveri basin within Karnataka",
    zone_type = "administrative cut",
    checkpoint = NA_character_,
    river = "Kaveri",
    target_hybas_id = NA_real_,
    hydrobasins_up_area_km2 = NA_real_,
    reported_area_km2 = 34273
  )

zones <- bind_rows(whole_zone, karnataka_zone, checkpoint_zones) %>%
  select(
    zone_id, zone, zone_type, checkpoint, river,
    target_hybas_id, hydrobasins_up_area_km2, reported_area_km2,
    geometry
  ) %>%
  st_make_valid()

zones_area <- st_transform(zones, area_crs) %>%
  mutate(zone_area_km2 = as.numeric(st_area(geometry)) / 1e6)

lookup <- read_parquet("cell_lookup.parquet") %>%
  distinct(cell_lat, cell_lon)

cell_geometry <- lapply(seq_len(nrow(lookup)), function(i) {
  x <- lookup$cell_lon[i]
  y <- lookup$cell_lat[i]
  st_polygon(list(matrix(
    c(
      x - 0.125, y - 0.125,
      x + 0.125, y - 0.125,
      x + 0.125, y + 0.125,
      x - 0.125, y + 0.125,
      x - 0.125, y - 0.125
    ),
    ncol = 2,
    byrow = TRUE
  )))
})

cells <- st_sf(
  lookup,
  geometry = st_sfc(cell_geometry, crs = 4326)
) %>%
  st_transform(area_crs) %>%
  mutate(cell_area_km2 = as.numeric(st_area(geometry)) / 1e6)

cell_weights <- lapply(seq_len(nrow(zones_area)), function(i) {
  zone_i <- zones_area[i, ]
  candidates <- st_intersects(zone_i, cells)[[1]]

  overlap <- st_intersection(
    cells[candidates, c("cell_lat", "cell_lon", "cell_area_km2")],
    zone_i %>% select(zone_id)
  ) %>%
    mutate(overlap_km2 = as.numeric(st_area(geometry)) / 1e6) %>%
    st_drop_geometry()

  overlap %>%
    mutate(
      zone = zones_area$zone[i],
      zone_area_km2 = zones_area$zone_area_km2[i],
      cell_fraction = overlap_km2 / cell_area_km2,
      area_weight = overlap_km2 / sum(overlap_km2)
    ) %>%
    select(
      zone_id, zone, cell_lat, cell_lon,
      overlap_km2, cell_area_km2, cell_fraction,
      zone_area_km2, area_weight
    )
}) %>%
  bind_rows()

zone_summary <- cell_weights %>%
  summarise(
    zone = first(zone),
    zone_area_km2 = first(zone_area_km2),
    mapped_area_km2 = sum(overlap_km2),
    grid_coverage_pct = 100 * mapped_area_km2 / zone_area_km2,
    cells = n(),
    .by = zone_id
  ) %>%
  left_join(
    zones %>%
      st_drop_geometry() %>%
      select(
        zone_id, zone_type, river,
        hydrobasins_up_area_km2, reported_area_km2
      ),
    by = "zone_id"
  ) %>%
  arrange(match(zone_id, zones$zone_id))

write_parquet(cell_weights, "data/kaveri_cell_weights.parquet")
write.csv(zone_summary, "data/kaveri_zone_summary.csv", row.names = FALSE)
st_write(zones, "data/kaveri_zones.gpkg", delete_dsn = TRUE, quiet = TRUE)
st_write(checkpoint_sf, "data/kaveri_checkpoints.gpkg", delete_dsn = TRUE, quiet = TRUE)

# Keep enough river network to show tributaries without drawing every stream.
map_rivers <- rivers %>%
  filter(UPLAND_SKM >= 100) %>%
  mutate(line_weight = pmin(log10(pmax(UPLAND_SKM, 100)), 4.8))

map_states <- states %>%
  filter(shapeISO %in% c("IN-KA", "IN-KL", "IN-TN", "IN-PY"))

map_bbox <- st_bbox(cwc_kaveri)
map_bbox[c("xmin", "xmax")] <- map_bbox[c("xmin", "xmax")] + c(-0.35, 0.35)
map_bbox[c("ymin", "ymax")] <- map_bbox[c("ymin", "ymax")] + c(-0.25, 0.25)

source_note <- paste0(
  "Sources: basin — CWC/NWIC; rivers and upstream topology — HydroSHEDS; ",
  "state borders — geoBoundaries. Dam coordinates identify HydroBASINS level-12 catchments."
)

base_map <- ggplot() +
  geom_sf(data = map_states, fill = "grey97", colour = "white", linewidth = 0.5) +
  geom_sf(data = cwc_kaveri, fill = "#dceceb", colour = "#175b5c", linewidth = 0.75) +
  geom_sf(
    data = map_rivers,
    aes(linewidth = line_weight),
    colour = "#2f7f80",
    alpha = 0.75,
    lineend = "round"
  ) +
  scale_linewidth_continuous(range = c(0.12, 1.15), guide = "none") +
  geom_sf(
    data = map_states,
    fill = NA,
    colour = "grey55",
    linewidth = 0.35
  ) +
  geom_sf(
    data = checkpoint_sf,
    aes(shape = kind),
    size = 2.2,
    stroke = 0.8,
    fill = "white",
    colour = "#7a3e1d"
  ) +
  scale_shape_manual(values = c(dam = 21, gauge = 23), guide = "none") +
  geom_text_repel(
    data = checkpoint_sf,
    aes(x = lon, y = lat, label = checkpoint),
    size = 3,
    colour = "grey20",
    min.segment.length = 0,
    segment.colour = "grey60",
    segment.size = 0.25,
    box.padding = 0.25,
    point.padding = 0.2,
    max.overlaps = Inf,
    seed = 42
  ) +
  coord_sf(
    xlim = map_bbox[c("xmin", "xmax")],
    ylim = map_bbox[c("ymin", "ymax")],
    expand = FALSE,
    datum = NA
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 15, colour = "grey15"),
    plot.subtitle = element_text(size = 10, colour = "grey35", margin = margin(b = 8)),
    plot.caption = element_text(size = 7.5, colour = "grey45", hjust = 0, margin = margin(t = 8)),
    plot.margin = margin(12, 18, 12, 12)
  )

catchment_map <- base_map +
  labs(
    title = "The Kaveri catchment and its main rainfall checkpoints",
    subtitle = "The river network includes tributaries; each marked point defines a cumulative upstream catchment.",
    caption = source_note
  )

ggsave(
  "outputs/kaveri_catchment_map.png",
  catchment_map,
  width = 10,
  height = 7.2,
  dpi = 180,
  bg = "white"
)

whole_cells <- cell_weights %>%
  filter(zone_id == "whole_basin") %>%
  mutate(
    xmin = cell_lon - 0.125,
    xmax = cell_lon + 0.125,
    ymin = cell_lat - 0.125,
    ymax = cell_lat + 0.125
  )

cell_map <- ggplot() +
  geom_sf(data = map_states, fill = "grey98", colour = "white", linewidth = 0.5) +
  geom_rect(
    data = whole_cells,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = cell_fraction),
    colour = "white",
    linewidth = 0.12
  ) +
  geom_sf(data = cwc_kaveri, fill = NA, colour = "#175b5c", linewidth = 0.8) +
  geom_sf(
    data = map_rivers %>% filter(UPLAND_SKM >= 500),
    colour = "#2f7f80",
    linewidth = 0.25,
    alpha = 0.75
  ) +
  scale_fill_gradient(
    low = "#eef5f4",
    high = "#176d6e",
    limits = c(0, 1),
    labels = scales::label_percent(),
    name = "Cell inside\nbasin"
  ) +
  coord_sf(
    xlim = map_bbox[c("xmin", "xmax")],
    ylim = map_bbox[c("ymin", "ymax")],
    expand = FALSE,
    datum = NA
  ) +
  labs(
    title = "IMD cells are weighted by how much overlaps the basin",
    subtitle = paste0(
      nrow(whole_cells),
      " 0.25° cells contribute. Edge cells get fractional rather than all-or-nothing weights."
    ),
    caption = paste0(
      "Grid: IMD 0.25° daily rainfall. Basin: CWC/NWIC. ",
      "Area calculations use an equal-area projection."
    )
  ) +
  theme_void(base_size = 11) +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 7),
    plot.title = element_text(face = "bold", size = 15, colour = "grey15"),
    plot.subtitle = element_text(size = 10, colour = "grey35", margin = margin(b = 8)),
    plot.caption = element_text(size = 7.5, colour = "grey45", hjust = 0, margin = margin(t = 8)),
    plot.margin = margin(12, 12, 12, 12)
  )

ggsave(
  "outputs/kaveri_imd_cells_map.png",
  cell_map,
  width = 10,
  height = 7.2,
  dpi = 180,
  bg = "white"
)

# Facets make the cumulative and tributary checkpoint definitions auditable.
zone_facets <- zones %>%
  filter(zone_id != "whole_basin") %>%
  mutate(
    zone = factor(
      zone,
      levels = c(
        "Kaveri basin within Karnataka",
        "Upstream of Harangi",
        "Upstream of Hemavathi",
        "Upstream of KRS",
        "Upstream of Kabini",
        "Upstream of Biligundlu",
        "Upstream of Mettur",
        "Upstream of Bhavanisagar",
        "Upstream of Amaravathi"
      )
    )
  )

checkpoint_map <- ggplot() +
  geom_sf(data = cwc_kaveri, fill = "grey96", colour = "grey75", linewidth = 0.25) +
  geom_sf(data = zone_facets, fill = "#4a9693", colour = "#175b5c", linewidth = 0.35) +
  facet_wrap(vars(zone), ncol = 3) +
  coord_sf(datum = NA) +
  labs(
    title = "Each checkpoint means all land draining to that point",
    subtitle = "Tributary dams are separate upstream basins; Biligundlu and Mettur are cumulative main-stem checkpoints.",
    caption = source_note
  ) +
  theme_void(base_size = 10) +
  theme(
    strip.text = element_text(face = "bold", size = 9, hjust = 0),
    panel.spacing = unit(5, "pt"),
    plot.title = element_text(face = "bold", size = 15, colour = "grey15"),
    plot.subtitle = element_text(size = 10, colour = "grey35", margin = margin(b = 8)),
    plot.caption = element_text(size = 7.5, colour = "grey45", hjust = 0, margin = margin(t = 8)),
    plot.margin = margin(12, 18, 12, 12)
  )

ggsave(
  "outputs/kaveri_checkpoint_zones.png",
  checkpoint_map,
  width = 10,
  height = 9.2,
  dpi = 180,
  bg = "white"
)

print(zone_summary)
