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

<!-- claude-session:6f6d5a64-ba41-4b58-91ba-dbe1d3800ced:start -->
## 2026-08-11 13:11 IST | Claude session `6f6d5a64-ba4`

### User prompts
> the pune data looks highly suspect. can you verify there is no mistake? [Image #1]
> no look at the early period. till 1950 or so.

### Work done
- Found it. There's a **step-break around 1950**, not a smooth climate signal. Pune decade means: **1900s-1940s ≈ 1,900-2,900 mm**, then **1950s onward crashes to ~700-900 mm**. A ~2.5x drop between the 1940s and 1950s...
- Confirmed - it's an **artifact, not climate, and it's specific to the Pune-Ghats cell.** Pre/post-1950 ratios: - **Pune (18.5,73.75): 2.08** ← the break - Mumbai 0.87, Delhi 0.93, Jaipur 0.91, Bengaluru 0.97 — all fla...
- Touched files: `kaveri_rainfall.Rmd`, `.posit/`, `explore_rainfall.Rmd`
- kaveri_rainfall.Rmd | 371 +++++++++-------------------------------------------

<!-- claude-session:6f6d5a64-ba41-4b58-91ba-dbe1d3800ced:end -->



## 2026-08-11 14:08 IST | Kaveri catchment rainfall

### User prompts
> i want to look at the total rainfall in the Kaveri catchment year each year, maybe even monthly. and see trends over time and stuff. first start by getting a map with the kaveri catchment region. then map it to the cells here. and then look at aggregate rainfall. now this needs to include tributaries as well. and needs to be checkpointed along the course of the river. "upstream of KRS", "within karnataka", any other dams, etc.

> ok great. write a blogpost about this. and push all this to github. i'll examine soon.

### Work done
- Combined the CWC/NWIC whole-basin boundary with HydroBASINS level-12 topology and HydroRIVERS tributaries.
- Built fractional IMD cell weights for the whole basin, Karnataka, and eight dam/gauge catchments; validated coverage and reported catchment areas.
- Aggregated 1901-2025 daily rainfall into monthly and annual area-weighted depth and volume using DuckDB.
- Kept trend claims to 1951-2024 after confirming a pre-1951 Western Ghats discontinuity, especially in Kabini.
- Added `kaveri_rainfall.Rmd`, three reproducible scripts, README instructions, and a public-facing draft in `blog-post.md`.

<!-- claude-session:b8522f13-d30a-4f34-b421-005dbe9a5968:start -->
## 2026-08-19 13:45 IST | Claude session `b8522f13-d30`

### User prompts
> <ide_opened_file>The user opened the file /Users/Karthik/Documents/work/data_work/weather/explore_rainfall.Rmd in the IDE. This may or may not be related to the current task.</ide_opened_file> Harold Edwin Hurst came...
> actually use data only from post 1951 for this.

### Work done
- Final re-run to confirm everything executes clean after the text edits.
- Clean. Notebook now runs on **1951–2024** throughout. **Post-1951 results (sorted by storage need):** | City | Storage (yrs) | H | |---|---|---| | Delhi | 6.9 | 0.83 | | Bengaluru | 5.2 | 0.87 | | Jaipur | 4.8 | 0.74...
- Touched files: `kaveri_rainfall.Rmd`, `.posit/`, `explore_rainfall.Rmd`, `hurst_rainfall.Rmd`
- kaveri_rainfall.Rmd | 371 +++++++++-------------------------------------------

<!-- claude-session:b8522f13-d30a-4f34-b421-005dbe9a5968:end -->







## 2026-10-11 to 2026-10-12 | Comfortable weather across India

Built with Claude Code. Charts in `outputs/`, write-up in
`blog-comfortable-weather.md`.

### Prompts (in order, lightly edited)

1. *"We have long term weather data (rainfall and temperature) for all India,
   gridded, from 1951 onwards. Use that to produce a map of India like this one
   [a South America map of days with comfortable weather]. Before you make the
   map, discuss the approach. The definition of 'comfortable weather' needs to be
   India specific. How will you get data for that?"*
2. *"Ignore humidity for now. Do with what we have - temperature and rain, both
   max and min temp. Max temp at 15-30; >30 is still hard. Is rain < 5 mm OK or
   should we make it 10 mm?"*
3. *"If IMD says 2.5-15 mm is light rain, keep 15 mm as the cutoff. 8° for min is
   fine. No elevation adjustment - leave it at 1°. Let's discuss the max temp a
   bit more."*
4. *"Keep 30. Build now. Also, for each gridpoint, for each year, mark each day
   comfortable or not, so we can do longitudinal analysis."*
5. *"Commit and push"* (README and temperature script).
6. *"Map is too boring. Use the RYG diverging scale like the original - it uses
   some blue also."*
7. *"Use the official India map, it must be somewhere on this computer. Where we
   don't have data leave it white."* + *"Mark more large cities, maybe 20."*
8. *"Do we need such a diverging scale or is green-yellow-red enough? Adjust the
   scales to include both ends."*
9. *"For India's 12 largest cities, draw comfortable days per year: year on x, a
   dot per year, a loess line, panels in descending order of city size."*
10. *"Swap Lucknow for Nagpur."* / *"Move the end labels away from the line."* /
    *"Add lines between the panels so it's clear which label is for which city."*
11. *"Next, a fuzzy map. Whether a day is comfortable is probabilistic - to get
    around 30 being comfortable but 31 not. How do we model this? Produce it, and
    produce both the map and the panelled chart."*
12. *"All notebooks and outputs can be in git. Document properly, commit and
    push, and update the devlog, changelog and blog."*

### Decisions

- **India-specific definition.** The source map used daily high 60-87°F, dew
  point at most 60°F and cloud cover at most 50%. Cloud cover was dropped (a
  cloudy day in India is usually welcome) and IMD has no humidity, so the rule
  is: daily high 15-30°C, overnight low at least 8°C, rain under 15 mm.
  - 30°C: India's median grid-cell daily high is 31-33°C, so the cap sits on the
    steep part of the distribution (moving it to 32°C takes the cells clearing
    150 days from 86 to 250 of 360). Kept at 30 because, without humidity data,
    it is what screens out the muggy coasts - the 1° cell at 9.5°N, 76.5°E (just
    south of Kochi) has 165 days a year between 30 and 32°C. The cost is a harsh penalty on the dry Deccan.
  - 8°C night floor: 10°C halved Delhi's count (128 to 56) by removing its
    best winter days; 5°C barely bit; 8°C drops the cold-wave weeks.
  - 15 mm: the top of IMD's "light rain" band. Moving from 5 to 10 mm changed
    city counts by only 2-12 days, so this choice matters little.
- **Humidity via ERA5-Land was discussed and deferred.** It would add dew point
  at 0.1°, but needs a Copernicus account. Elevation downscaling of the 1°
  temperature grid (lapse rate) was also discussed and rejected - stay at 1°.
- **Output grain is the 0.25° rainfall cell.** Each takes the temperature of the
  1° cell it sits in. 60 coastal/border rainfall cells have no 1° cell over them
  and take the nearest one, flagged `temp_from_neighbour`. Key `(date, lat, lon)`
  checked unique; row count checked equal to the rainfall table.
- **Missing data stays missing.** `comfortable` is NULL when inputs are missing;
  annual counts carry `observed_days` so period averages rescale rather than
  undercount. Maps drop cells missing more than 10% of days in a period.
- **Fuzzy score.** Each threshold becomes a logistic curve that is 0.5 at the
  hard cut-off; the day's score is the product of the four (independent
  thresholds). Widths: 1°C on the hot side of the daily high (28°C ~ 0.88, 32°C
  ~ 0.12), 1.5°C on the cold sides, 0.4 on log-mm for rain (7 mm ~ 0.87, 30 mm ~
  0.15). Read as the share of people whose cut-offs the day clears; summed, it
  gives expected comfortable days, and reduces to the hard count as widths go to
  zero. Widths are judgement calls, not fitted.
- **Maps.** Red-yellow-green (ColorBrewer RdYlGn), green = more comfortable,
  legend spanning the data range. The change map is rust-teal diverging around
  zero with a symmetric midpoint, so the smaller gains side never reaches full
  teal. Cells are clipped to the DataMeet state outlines (via geoBoundaries),
  which follow India's official boundary - Ladakh includes Gilgit-Baltistan and
  Aksai Chin. No Survey of India file was found on disk.
- **City panels.** Census 2011 urban agglomerations, largest first. Lucknow
  shares Kanpur's 1° temperature cell, so Nagpur (13th) replaces it. Shared y
  axis, city name inside a boxed panel, loess ends labelled.

### Findings

- Typical grid cell: about 90 comfortable days a year (1995-2024). The most
  comfortable areas are the Himalaya, the north-east, and south Karnataka into
  the Kerala highlands; the fewest are Tamil Nadu, Telangana and the Gujarat
  coast.
- 76% of comparable cells lost comfortable days between 1951-80 and 1995-2024.
  The Deccan lost 30-40 a year; in a Deccan box, days above 30°C rose from 238
  to 274 a year. The north-west gained a little (Jaipur +15, Delhi +10) because
  nights under 8°C fell from 54 to 41 a year.
- City trends 1951 to 2024 (hard): Bengaluru 231 to 155, Hyderabad 101 to 54,
  Chennai 75 to 26. Fuzzy: Bengaluru 210 to 148, Chennai 73 to 40, Hyderabad 104
  to 70. Fuzzy and hard maps correlate at 0.99.

### Problems solved

- DuckDB in R refused a prepared parameter inside `CREATE VIEW`; switched to
  `sprintf()` for that one integer.
- `sum()` and `count_if()` over all-NULL groups return NULL in DuckDB, which
  made some cell-years NA. Fixed with `count(*) FILTER (WHERE comfortable)` and
  `coalesce(sum(comfort_score), 0)`.
- The hard flag and fuzzy score have different missingness (SQL `FALSE AND NULL`
  is FALSE, but arithmetic with NULL is NULL), so the score got its own
  denominator, `score_observed_days`.
- The state outline was drawn in white on a white background, so it was
  invisible; added a grey country outline and a white India fill underneath.
- Hairline seams between clipped grid squares: outline each square in its own
  fill colour.
- `ggrepel` 0.9.8 ignores `label.size` for the box border; it reads the
  `linewidth` aesthetic, so set `linewidth = 0`.
- City names placed at a data x-coordinate widened the x-scale; fixed x limits
  so names and end labels fit without moving the data.

<!-- claude-session:b0de8b11-023d-4636-8537-9716af80bdf6:start -->
## 2026-10-11 16:26 IST | Claude session `b0de8b11-023`

### User prompts
> we have long term weather data (rainfall nad temperature) for all india, gridded. from 1951 onwards. use that to produce me a map of india like this one: https://x.com/gvtcontractor/status/2109034898996564161 . before...
> ignore humidity for now. do with what we have - temperature and rain. both max and mintemp. max temp put at 15-30. >30 is still hard. and is rain < 5mm ok or should we make it 10mm? makes sense?
> if imd says 2.5-15mm as light rain, let's keep 15mm as the cutoff. and 8deg for min is fine. and no point with elevation assessment. leave it at 1deg. one more thing - let's discuss a bit more onthe max temp

### Work done
- Now the .gitignore and README.
- Everything is now committed and pushed (`8274444`), and the working tree is clean. That covers the three notebooks, all 13 charts in `outputs/`, the README, the changelog, the dev log and a new blog post. **What's in...

<!-- claude-session:b0de8b11-023d-4636-8537-9716af80bdf6:end -->

<!-- claude-session:42f6bc8f-dbd2-4cf6-ab30-caad775e8e68:start -->
## 2026-10-12 11:00 IST | Claude session `42f6bc8f-dbd`

### User prompts
> on the comfortable days data - can we figure out for each city WHEN the comfortable days are? each day of year (ignore feb29) plot probability of being comfortble. and similar panelled plot to the delta in comfortable...
> you can add vertical gridliesn for each month break

### Work done
- I made a new chart showing when in the year each city's comfortable days fall: `outputs/city_comfort_seasons.png`, plus `_fuzzy.png`. Committed as `8064855` and pushed. Skills used: caveman (from the session hook), ka...
- Both season charts (`outputs/city_comfort_seasons.png` and `_fuzzy.png`) now have a faint vertical gridline at the start of every month. The axis still labels only Jan, Apr, Jul and Oct. Re-rendered and checked the im...

<!-- claude-session:42f6bc8f-dbd2-4cf6-ab30-caad775e8e68:end -->
