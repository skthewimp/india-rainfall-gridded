#!/usr/bin/env bash

# Download the public geometry inputs used by build_kaveri_geography.R.
# Existing files are retained, so the script is safe to rerun.

set -euo pipefail

mkdir -p sources/boundaries sources/hydrobasins sources/hydrorivers

download() {
  local url="$1"
  local output="$2"

  if [[ -f "$output" ]]; then
    printf 'exists: %s\n' "$output"
  else
    curl -L "$url" -o "$output"
  fi
}

download \
  "https://nwdp.nwic.gov.in/dataset/ec216ae7-1beb-4365-8473-d60a7fc4a98c/resource/a6838033-06cd-4e32-bc46-e47ce5135a06/download/basin_cwc_geojson.zip" \
  "sources/boundaries/basin_cwc_geojson.zip"

if [[ ! -f sources/boundaries/basin_cwc.GeoJSON ]]; then
  unzip -o sources/boundaries/basin_cwc_geojson.zip -d sources/boundaries
fi

download \
  "https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/IND/ADM1/geoBoundaries-IND-ADM1_simplified.geojson" \
  "sources/boundaries/india_adm1.geojson"

download \
  "https://data.hydrosheds.org/file/hydrobasins/standard/hybas_as_lev12_v1c.zip" \
  "sources/hydrobasins/hybas_as_lev12_v1c.zip"

if [[ ! -f sources/hydrobasins/hybas_as_lev12_v1c.shp ]]; then
  unzip -o sources/hydrobasins/hybas_as_lev12_v1c.zip -d sources/hydrobasins
fi

download \
  "https://data.hydrosheds.org/file/HydroRIVERS/HydroRIVERS_v10_as_shp.zip" \
  "sources/hydrorivers/HydroRIVERS_v10_as_shp.zip"

if [[ ! -f sources/hydrorivers/HydroRIVERS_v10_as_shp/HydroRIVERS_v10_as.shp ]]; then
  unzip -o sources/hydrorivers/HydroRIVERS_v10_as_shp.zip -d sources/hydrorivers
fi

printf 'Kaveri geography sources ready.\n'
