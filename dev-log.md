# Dev log — India gridded rainfall → Parquet

Built in one session with Claude Code (Opus 4.8). This logs the prompts, the
decisions made, the problems hit, and what's still open.

## Prompts (in order)

Lightly edited, PII stripped.

1. *"Help explore `RF25_ind2025_rfp25.nc` and store it in an easy and smaller
   format (parquet?)."*
2. *"Yes do a quick sanity check. After that let's scrape for historical data."*
3. Config answers: **all years 1901–2025**, **partitioned by year**, **delete
   the `.nc` after converting**.
4. *"For the cells for which we have the data, do we have a mapping of towns /
   cities etc.?"*
5. Config answers: **city → cell lookup**, using **offline GeoNames**.
6. *"Yes do it. Choose the largest [town] for each cell."*
7. *"Show me a few rows of this."* → *"I can't see the actual data. A few rows
   here."*
8. *"Make a proper devlog, then a public MIT GitHub repo with all of this. I
   don't own the licence for the data."*

## What the file turned out to be

`ncdump -h` on the source file:

- Dims: `LONGITUDE=135`, `LATITUDE=129`, `TIME=365` (unlimited).
- One variable: `RAINFALL(TIME, LATITUDE, LONGITUDE)`, float, mm,
  `_FillValue = -999`.
- `TIME` units `days since 1900-12-31`; xarray decodes it straight to dates.

So it's IMD Pune's 0.25° daily gridded rainfall — one year per file, the same
schema every year back to 1901.

## Decisions

- **Long/tidy Parquet, not wide.** `date, lat, lon, rainfall_mm`. Drop the
  `-999` fill cells (ocean + outside India). That alone takes each year from
  6.36M cells to ~1.81M rows, and 25 MB of NetCDF to ~3.5 MB of zstd Parquet.
- **`float32` for lat/lon/rainfall.** The grid is on a 0.25° lattice and
  rainfall is reported to ~2 decimals; float32 is plenty and halves the width.
- **Partition by year** (`year=YYYY/data.parquet`). Arrow reads it lazily,
  filters push down, and adding a future year is just dropping in a folder.
- **Resumable scraper.** `scrape.py` skips any year whose Parquet already
  exists, so a dropped connection mid-run costs nothing. 2 s sleep between
  years to be polite to the IMD server.
- **City → cell, not cell → city, for the join.** People ask "rainfall for
  Pune", so the useful key is (place → its cell). The reverse (labelling every
  cell) is a separate, coarser convenience table.
- **GeoNames offline, not a geocoding API.** 558k Indian populated places in a
  15 MB dump; no keys, no rate limits, runs in seconds.

## Problems solved

- **No Python libs, and `pip` is uv-shimmed.** `pip3 install` errored asking for
  a venv. Fix: `uv venv .venv` then `uv pip install --python .venv/bin/python …`.
  (`.venv/bin/python -m pip` fails — the venv has no pip; must go through `uv`.)
- **How does the IMD site serve a year?** The download page posts a form:
  `POST RF25.php` with a single field `RF25=<year>`. Confirmed by curling the
  raw HTML and reading the `<form>` / `<option>` values, then test-downloading
  1901. Plain `urllib` POST does the rest.
- **Snapping places to cells fast.** 558k places against 4,964 cells. Instead of
  a 558k×4,964 distance matrix, compute each place's covering cell by rounding
  onto the 0.25° lattice (O(n), 556,289 land in one shot). Only the 1,706 that
  land on a no-data cell (coast/islands) get a brute-force nearest-cell search,
  chunked with numpy. Median place→cell distance 10.6 km, as expected for a
  28 km cell.
- **Sanity checks that actually caught nothing wrong.** 72.6% of 2025 rain falls
  Jun–Sep (monsoon), peak 26 Jul. The Mumbai cell logs 423 mm on 2005-07-27 —
  the real 26 July 2005 deluge. Bengaluru cell: 125 years, mean 871 mm/yr,
  wettest 2022, driest 2002. All plausible.

## What's still to look up / verify

- **IMD redistribution terms.** The code is MIT; the *data* is IMD's. Before
  publishing any derived dataset (the Parquet, the charts), confirm what IMD's
  data-supply policy actually permits. Right now nothing derived is committed.
- **0 vs missing on land.** We treat `-999` as "no cell" and everything else as
  a real reading including 0. Worth spot-checking that no genuine land cell is
  all-`-999` for a year (i.e. that we're not silently dropping a station gap).
- **2025 is provisional.** It's the real-time series and may be revised. Decide
  whether to re-pull it periodically.
- **Island snaps.** A few Andaman/Lakshadweep places snap >20 km to the nearest
  mainland-ish cell. If those matter, filter on `dist_km` or handle separately.
- **Representative-town choice.** "Largest by population" is one call; GeoNames
  population is patchy for small towns (many are 0), so the biggest-town label
  can be arbitrary in rural cells. An alternative is "nearest place to cell
  centre" or "district HQ".
- **Leap years.** Handled automatically (xarray decodes 366-day years); row
  counts confirm it (1,816,824 rows in leap 2024 vs 1,811,860 in 2025).

## Repo hygiene

`.gitignore` keeps all data out: `*.nc`, `rainfall_parquet/`, the GeoNames
dumps, and the two derived Parquet lookups. Someone cloning the repo runs the
three scripts and rebuilds everything from the original sources.

<!-- claude-session:2a5dc498-559e-4ac6-aca2-41eb1ab394d2:start -->
## 2026-08-10 09:22 IST | Claude session `2a5dc498-559`

### User prompts
> help explore @RF25_ind2025_rfp25.nc . and store it in an easy and smaller format (parquet?).
> yes do a quick sanity check. after that let's scrape for historical data.
> <task-notification> <task-id>b7ebmbq9x</task-id> <tool-use-id>toolu_01BGKZNcJHg6mp8SJs6NwWM6</tool-use-id> <output-file>/private/tmp/claude-501/-Users-Karthik-Documents-work-data-work-weather/2a5dc498-559e-4ac6-aca2-4...

### Work done
- Everything's in place and git is clean. Saving a memory so a fresh chat picks up where this left off:
- Yes - safe to clear. Everything's documented in three places: **1. In the repo (pushed):** - `README.md` — setup, run steps, grid facts, licensing, caveats - `dev-log.md` — full process, all your prompts, decisions, p...

<!-- claude-session:2a5dc498-559e-4ac6-aca2-41eb1ab394d2:end -->

<!-- claude-session:fa9a2829-c40e-48be-9726-73efd1d217b5:start -->
## 2026-08-11 10:21 IST | Claude session `fa9a2829-c40`

### User prompts
> i'd started a project recently to edit my website. now i don['t know which folder it was in. find it and navigate to that folder so we c an revive it
> ok so basically what are the changes i'd requested? i need to make it a good lead gen thing. so that people c an see me there and wnat to hire me for consulting or workshops.
> don't add any years on any projects. and no need to include sabre etc. also. and fix the typo. and show me hte content here before you push.

### Work done
- Using skills: karthik-writing-style. Reading your voice files first.
- The bucket headers were the AI tell - "AI inside real business workflows / Pricing and revenue models" is exactly the capability-matrix voice to kill. In your voice, coherence comes from concrete, understated lines, n...

<!-- claude-session:fa9a2829-c40e-48be-9726-73efd1d217b5:end -->

<!-- claude-session:04fc5bbe-c066-42af-ba12-12f8da480f63:start -->
## 2026-08-11 11:05 IST | Claude session `04fc5bbe-c06`

### User prompts
> clean up this folder. remove the old raw data files (only keep the parquets). keep only the necessary (for future downloads) pieces of code, and put them in their own folder.
> what is the RF*parquet doing here? is it necessraey?
> now create an R note book (.Rmd) to explore and visualise the data in my style. keep it concise.

### Work done
- Let me smoke-test the R actually runs (arrow paths, town filter, aggregations).
- All chunks run. Verified against real data: 226M rows, 45,656 daily means (125 yrs), Bengaluru cell resolves to (13, 77.5), 2025 map = 4,964 cells, 0-7996mm. `explore_rainfall.Rmd` — 8 chunks, weather-scratchpad textu...
- Touched files: `.posit/`, `explore_rainfall.Rmd`

<!-- claude-session:04fc5bbe-c066-42af-ba12-12f8da480f63:end -->

