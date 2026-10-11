"""Download IMD daily 1-degree Tmin/Tmax and build cell-day Parquet partitions.

Run with /Users/Karthik/envs/datascience/.venv/bin/python.
Original binary files are retained under sources/temperature for reproducibility.
"""

import argparse
import calendar
from pathlib import Path
import time

import numpy as np
import pandas as pd
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--start-year", type=int, default=1951)
parser.add_argument("--end-year", type=int, default=2025)
args = parser.parse_args()
if args.start_year > args.end_year:
    parser.error("start-year must not exceed end-year")

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "sources" / "temperature"
OUTPUT = ROOT / "temperature_parquet"
BASE_URL = "https://www.imdpune.gov.in/cmpg/Griddata/"
VARIABLES = {"mintemp": "tmin_c", "maxtemp": "tmax_c"}
LATITUDES = np.arange(7.5, 38.5, dtype=np.float32)
LONGITUDES = np.arange(67.5, 98.5, dtype=np.float32)
RAW.mkdir(parents=True, exist_ok=True)

# Downloads are read-only POST requests, so retrying them is safe.
session = requests.Session()
retry = Retry(
    total=4,
    backoff_factor=2,
    status_forcelist=[429, 500, 502, 503, 504],
    allowed_methods=["GET", "POST"],
)
session.mount("https://", HTTPAdapter(max_retries=retry))


def read_grid(content, year):
    """IMD's C/GrADS examples specify daily lat/lon float32 records, UNDEF 99.9."""
    days = 366 if calendar.isleap(year) else 365
    expected_bytes = days * len(LATITUDES) * len(LONGITUDES) * 4
    if len(content) != expected_bytes:
        raise ValueError(
            f"{year}: expected {expected_bytes:,} binary bytes, got {len(content):,}; "
            f"response begins {content[:80]!r}"
        )
    values = np.frombuffer(content, dtype="<f4").copy()
    values[values == np.float32(99.9)] = np.nan
    observed = values[~np.isnan(values)]
    # Wide physical bounds detect corrupt downloads / wrong byte order;
    # unexpected values block the write rather than being silently removed.
    if not len(observed) or not np.isfinite(observed).all():
        raise ValueError(f"{year}: empty or non-finite temperature grid")
    if observed.min() < -100 or observed.max() > 70:
        raise ValueError(f"{year}: unexpected range {observed.min()} to {observed.max()}")
    return values


failures = []
for year in range(args.start_year, args.end_year + 1):
    destination = OUTPUT / f"year={year}" / "data.parquet"
    if destination.exists():
        print(f"{year}: already saved", flush=True)
        continue

    try:
        temperatures = {}
        for source_name, column in VARIABLES.items():
            raw_path = RAW / f"{source_name}_{year}.grd"
            if raw_path.exists():
                values = read_grid(raw_path.read_bytes(), year)
            else:
                print(f"{year}: downloading {source_name}", flush=True)
                response = session.post(
                    BASE_URL + source_name + ".php",
                    data={source_name: str(year)},
                    timeout=(20, 90),
                )
                response.raise_for_status()
                values = read_grid(response.content, year)
                temporary = raw_path.with_suffix(".part")
                temporary.write_bytes(response.content)
                temporary.replace(raw_path)
                time.sleep(2)
            temperatures[column] = values

        # One year fits comfortably in memory (~351k raw grid-days).
        dates = pd.date_range(f"{year}-01-01", f"{year}-12-31")
        frame = pd.MultiIndex.from_product(
            [dates, LATITUDES, LONGITUDES], names=["date", "lat", "lon"]
        ).to_frame(index=False)
        for column, values in temperatures.items():
            frame[column] = values
        frame[["lat", "lon"]] = frame[["lat", "lon"]].astype("float32")

        # Exclude only grid-days with neither measurement (mostly outside India).
        # Keep partial Tmin/Tmax observations and source inconsistencies visible.
        empty = frame[["tmin_c", "tmax_c"]].isna().all(axis=1)
        frame = frame.loc[~empty].copy()
        duplicates = frame.duplicated(["date", "lat", "lon"], keep=False)
        if duplicates.any():
            print(frame.loc[duplicates].to_string(index=False), flush=True)
            raise ValueError("Duplicate cell-day keys; refusing canonical write")
        if frame["date"].nunique() != len(dates):
            raise ValueError(f"{year}: one or more dates have no observations")
        inverted = frame["tmin_c"] > frame["tmax_c"]
        print(
            f"{year}: rows={len(frame):,}; empty grid-days={empty.sum():,}; "
            f"missing={frame[['tmin_c', 'tmax_c']].isna().sum().to_dict()}; "
            f"Tmin>Tmax={inverted.sum():,}; "
            f"range={frame[['tmin_c', 'tmax_c']].agg(['min', 'max']).to_dict()}",
            flush=True,
        )
        if inverted.any():
            print(frame.loc[inverted].head(5).to_string(index=False), flush=True)

        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(".part")
        frame.to_parquet(temporary, index=False, compression="zstd")
        temporary.replace(destination)
    except (requests.RequestException, ValueError, OSError) as exc:
        failures.append(year)
        print(f"{year}: FAILED: {exc}", flush=True)

session.close()
if failures:
    raise SystemExit(f"Incomplete years: {failures}. Rerun to resume.")
print(f"Complete: {args.start_year}–{args.end_year} in {OUTPUT}", flush=True)
