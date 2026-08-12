# What does a century of rain look like across the Kaveri basin?

I started with what I thought was a fairly simple question: how much rain falls in the Kaveri catchment every year?

The rainfall data was already sitting on my machine - daily, 0.25-degree IMD grids going back to 1901. I had turned the original NetCDF files into Parquet, mostly because 226 million rows become much less frightening when Arrow and DuckDB can do the heavy lifting.

All I needed was a map of the Kaveri basin. Then I could pick the cells inside it and add up the rain.

This, predictably, was not quite how it worked.

## A river is not a line

The first problem was defining the catchment.

Drawing a buffer around the Kaveri would miss the point. Rain falling over the Kabini, Hemavathi, Harangi, Bhavani or Amaravathi catchments eventually enters the same river system. The unit I needed was all the land draining to a point, including every tributary upstream of it.

I used the Central Water Commission's boundary for the whole Kaveri basin. For checkpoints along the river, I used HydroBASINS level-12 polygons and their upstream-downstream topology. A dam coordinate identifies the small sub-basin containing it; from there, the code walks backwards through every polygon that drains into that point.

That gives me ten useful cuts:

- the whole basin;
- the part of the basin inside Karnataka;
- cumulative catchments upstream of KRS, Biligundlu and Mettur;
- tributary catchments upstream of Harangi, Hemavathi, Kabini, Bhavanisagar and Amaravathi.

This distinction matters. "Upstream of KRS" is not the same thing as "the Kaveri near Mysuru". It is about 11,000 square kilometres and includes the rain falling across the upstream tributary network.

## Mapping a coarse rainfall grid to an irregular basin

The IMD rainfall grid is 0.25 degrees - roughly 28 km by 28 km around Karnataka. The Kaveri boundary, unsurprisingly, does not respect those squares.

The lazy option is to keep a cell when its centre falls inside the basin. That turns edge cells into an all-or-nothing decision and makes the answer depend on an arbitrary point.

Instead, I intersected every grid cell with every catchment and calculated the overlap area. A cell that is 80% inside the basin gets four times the weight of one that is 20% inside it. There are 153 contributing IMD cells for the whole basin, with 99.4% of the mapped basin area covered by the grid.

The output is an area-weighted rainfall depth in millimetres. I also convert that depth into cubic kilometres falling over the catchment. The whole basin averages about 958 mm a year from 1951 to 2024 - roughly 82 cubic kilometres of gross rainfall.

The word *gross* is doing useful work there. This is rain, not water arriving at a dam.

## The basin has become a little wetter. Its tributaries have not moved together.

I compared the average for 1995-2024 with 1951-1980. I prefer this to pretending that one straight trend line captures everything happening over 74 noisy monsoons.

For the whole Kaveri basin, the recent period is about 5% wetter than the early one.

But the whole-basin number hides a fairly sharp split:

- the Karnataka portion is 11.6% wetter;
- upstream of KRS is 12% wetter;
- upstream of Biligundlu is 8.8% wetter;
- upstream of Mettur is 8% wetter;
- Kabini is 6.8% lower;
- Bhavanisagar is 13.1% lower;
- Harangi is essentially unchanged.

Amaravathi shows the largest increase, at about 14%, though it is a much smaller catchment and its annual numbers bounce around more.

So the interesting result is not "the Kaveri is getting wetter". Some large cumulative catchments have received more rain, while two important western tributaries have moved the other way. That should matter when we talk about basin-wide shortage as though it were one uniform weather event.

It does not, on its own, tell us anything about allocation, releases or who is using too much water. Rainfall is only the first layer of that argument.

## July upstream, October downstream

The monthly pattern is possibly more useful than the annual trend.

Harangi, Hemavathi, Kabini and the catchment upstream of KRS all peak in July. These headwater areas get roughly two-thirds of their annual rain during June-September.

The whole basin peaks in October. So do the Karnataka portion, Biligundlu, Mettur, Bhavanisagar and Amaravathi. Across the full catchment, June-September supplies about 45% of annual rainfall, while October-December supplies another 37%.

This is the two-monsoon structure of the basin showing up cleanly in the grid. A single "monsoon rainfall" number loses quite a lot of information here.

## The awkward bits

There are three caveats I would keep attached to every chart from this analysis.

First, the pre-1951 IMD series has a suspicious break in parts of the Western Ghats. The Kabini catchment's 1901-1950 average is about 49% higher than its 1951-2000 average. Nearby non-Ghat cells do not show the same break. I do not believe this is climate, so the main analysis begins in 1951 rather than claiming a clean 125-year trend.

Second, catchment boundaries are estimates. The current CWC geometry measures about 85,300 square kilometres, while an older area attribute in the same source says 81,155. HydroBASINS catchments at individual dams differ from reported project areas by roughly 2-9%, partly because the dam may sit inside, rather than exactly at the outlet of, a level-12 polygon. This is precise enough for a 28 km rainfall grid, but it is not survey-grade hydrology.

Third, rainfall is not inflow. To estimate what reaches KRS or Mettur, I would need evapotranspiration, soil moisture, groundwater, withdrawals, return flows, reservoir operations and quite a few things I have probably forgotten. Summing rain and calling it available water would be a very confident category error.

## What I built

The repo now contains:

- a reproducible script to build the basin and checkpoint geometries;
- fractional IMD cell weights for every catchment;
- DuckDB aggregation from 226 million daily rainfall rows into monthly and annual series;
- an R notebook with the maps, trend comparisons and monthly profiles;
- no rainfall data, because the IMD data is not mine to redistribute.

I built most of the plumbing with Codex, then checked the geometry, catchment areas, coverage, aggregation and rendered charts. The useful part of AI-assisted analysis is not that it writes `st_intersection()` faster than I do. It is that I can spend more time arguing with the definition of "upstream of KRS" - which is where the analysis can actually go wrong.

The code is here: <https://github.com/skthewimp/india-rainfall-gridded>

The next step is runoff. That is also the point at which this stops being a neat map exercise and becomes a proper hydrology problem.
