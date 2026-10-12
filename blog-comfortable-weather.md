# How many comfortable days does your city get?

Last weekend a map was doing the rounds on Twitter. "Number of Days with Comfortable Weather", it said, and it showed South America with central Chile glowing red at 350 days a year and most of Brazil in a sad shade of lavender. The tweet that came with it said "You can't imagine how good life is when you live somewhere with perfect weather all year."

I looked at it a bit closely, and I'm fairly sure the map itself was AI-generated. The colours were too smooth, the internal boundaries didn't correspond to anything real, and there was a footnote saying "approximate regional estimate". So I wouldn't trust any of its numbers.

The question, though, is a good one. And I happen to have IMD's daily gridded rainfall (0.25 degrees, going back to 1901) and temperature (1 degree, from 1951) sitting on my laptop in Parquet form. So I decided to make the India version.

## Comfortable for whom?

The South America map defined a comfortable day as a daily high between 60 and 87°F (about 15.5 to 30.5°C), a dew point of at most 60°F, and cloud cover of at most 50%.

This doesn't travel to India. The cloud cover condition is the most obviously wrong one - in most of India a cloudy day is a relief (a grey July afternoon in Bangalore is about as pleasant as weather gets). And the IMD gridded data has no humidity or cloud cover at all, so that part was moot anyway.

So I went with what I had. A day counts as comfortable if:

- the daily high is between 15 and 30°C
- the overnight low is at least 8°C
- it rains less than 15 mm

The 15 mm is IMD's own boundary between "light" and "moderate" rain. The 8°C floor is there so that north Indian cold-wave weeks don't count as pleasant. I tried 10°C first, and it halved Delhi's count by removing the December and January days that Delhiites actually brag about.

The 30°C ceiling took the most arguing. The median daily high across India's grid cells is 31-33°C, so 30 sits right on the steep part of the distribution, and small changes swing everything. Move the ceiling to 32 and Mumbai goes from about 50 comfortable days a year to more than 130. Anyone who has spent a May in Mumbai will tell you that's absurd. Without humidity data, the 30°C cap is quietly doing humidity's job, screening out the muggy coasts.

The cost is that it's harsh on the dry Deccan. The grid cell around Bangalore has about a hundred days a year with highs between 30 and 32, most of which feel perfectly fine. I decided I could live with that.

## The map

![Comfortable days a year across India, 1995-2024](outputs/comfortable_days_map.png)

Averaged over 1995-2024, a typical grid cell gets about 90 comfortable days a year. The comfortable belts are the Himalaya, the north-east, and south Karnataka running into the Kerala highlands. The worst bits are Tamil Nadu, Telangana and the Gujarat coast. Chennai gets about 33 days. Bangalore's cell gets 178.

Before you take any individual number too seriously, there's a big caveat. The temperature grid is 1 degree, which is about 110 km on a side. Shillong's cell has a median daily high of 29°C, because the cell averages Shillong with the plains of Assam and Bangladesh next to it. Kochi's cell, on the other hand, takes in a large chunk of the Western Ghats, which is why Kochi shows up as a comfortable 201 on the map. Hill stations basically disappear. I could have adjusted temperatures for elevation using a lapse rate, but that's one more assumption stacked on top of the others, and I wanted to keep this honest about its resolution.

## A month gone

The part that surprised me came when I compared periods. Here is 1995-2024 minus 1951-1980.

![Change in comfortable days, 1995-2024 vs 1951-1980](outputs/comfortable_days_change_map.png)

About three-quarters of India has lost comfortable days, and the Deccan has lost about a month of them every year. In a box around the Deccan plateau, the number of days with a high above 30°C went from about 238 a year to 274. That's the whole story there - more hot days.

The north-west went the other way, gaining a little: Jaipur about 15 days, Delhi about 10. When I looked at why, it turned out to be winter nights. Nights below 8°C in the Delhi-Jaipur cells fell from about 54 a year to 41. So the same warming that takes comfortable days away from the south hands a few to the north.

Here are the largest cities, one panel each, with a loess trend through the yearly counts.

![Comfortable days a year in the largest cities, 1951-2024](outputs/city_comfortable_days.png)

Bangalore's trend goes from about 230 comfortable days in 1951 to about 155 now. Hyderabad roughly halves, from about 100 to 54. Chennai, which never had many to begin with, goes from 75 to 26. Delhi, Jaipur and Kanpur are flat or slightly up. Anyone who has lived in Bangalore long enough to complain about it will not be surprised, but it's still something to see it in the data.

(Lucknow is missing from the panels because it shares a 1-degree temperature cell with Kanpur, so its chart looked nearly identical. Nagpur, the next largest city, takes its place.)

## Thirty versus thirty-one

Something about this kept bothering me. Under my rule, a 30.0°C day is comfortable and a 30.1°C day isn't. Nobody experiences weather like that. And given how much of India sits right around 30°C, it was possible that the decline was an artefact of where I had drawn the line.

So I made the thresholds fuzzy. Each condition gets a smooth curve which is 0.5 exactly at the old cut-off and fades out over a few degrees on either side. For the 30°C ceiling, a 28°C day scores about 0.88 and a 32°C day about 0.12. Rain works the same way on a log scale. The day's score is the product of the four. One way to read it is as the share of people whose personal cut-offs the day clears, and if you add up the scores over a year you get "expected comfortable days".

The extremes compress, as you would expect. Chennai goes up from 33 to 45 and Bangalore comes down from 178 to 165, since borderline days now get partial credit both ways. But the fuzzy map correlates at 0.99 with the hard one, and the decline survives. Bangalore goes from about 210 to 148, Chennai from 73 to 40, and the Deccan still loses about four weeks a year. So it wasn't the 30°C line manufacturing the trend.

The widths of those curves are my own judgement calls, though. I didn't fit them to anything, because I don't have anything to fit them to.

## What this doesn't tell you

There's no humidity in any of this, so Mumbai and Chennai look kinder than they feel. The natural next step is ERA5-Land reanalysis, which has dew point at a much finer resolution, but that needs a Copernicus account and a few hours of downloading, which I haven't got around to.

IMD's temperature grid also uses fewer stations from 2008 onwards, which muddies long-run comparisons a bit. And some border cells in J&K and Arunachal only appear from 1969.

All the code, notebooks and charts are [on GitHub](https://github.com/skthewimp/india-rainfall-gridded) (the IMD data isn't - you'll have to download that yourself, and the scripts do it for you). Every grid cell has a comfortable-or-not flag and a fuzzy score for every day since 1951, so if you want to look at your own city, or argue with my thresholds, it's all there.

And if someone has a better definition of a comfortable day in Chennai, I'm all ears.
