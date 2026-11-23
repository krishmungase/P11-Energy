# Step 1: the dataset and how we reshaped it

Owner: Krishna Mungase (krishmungase)

## The dataset

Open Power System Data (OPSD) collects electricity data for European countries from the grid operators' transparency platform (ENTSO-E) and publishes it as clean CSV files. We use the hourly file.

- File: `time_series_60min_singleindex.csv`, version 2020-10-06
- Size: 130,339,665 bytes (about 130 MB)
- Shape: 50,401 rows (one per hour) by 300 columns
- Time range: 2014-12-31 23:00 to 2020-09-30 23:00, in UTC
- Download: https://data.open-power-system-data.org/time_series/2020-10-06/time_series_60min_singleindex.csv

Citation for the report:

> Open Power System Data. 2020. Data Package Time series. Version 2020-10-06. https://doi.org/10.25832/time_series/2020-10-06

The column names follow the pattern `<country>_<what>`, for example:

| Column | Meaning | Unit |
|---|---|---|
| `utc_timestamp` | start of the hour, in UTC | |
| `DE_load_actual_entsoe_transparency` | electricity used in Germany in that hour | MW |
| `DE_solar_generation_actual` | electricity made by solar panels | MW |
| `DE_wind_generation_actual` | electricity made by wind, onshore plus offshore | MW |
| `DE_wind_onshore_generation_actual` | wind on land only | MW |
| `DE_wind_offshore_generation_actual` | wind at sea only | MW |

MW is power, the rate of use at that moment. Each row covers one hour, so a value of 1,000 MW for one hour is 1,000 MWh of energy. That is why adding up hourly MW values gives MWh.

## Picking the 10 countries

The plan named DE, FR, ES, IT, NL, BE, AT, DK, PL and PT. Before using them we checked two things for each country: how many hours have a value (coverage), and whether the yearly averages look believable. Three problems came up.

| Problem | What we saw | What we did |
|---|---|---|
| Poland, solar | Solar is empty for 92% of hours (coverage 0.083) | Replaced PL with Czech Republic (CZ). CZ has load 99.8%, solar 99.9% and wind 100% coverage. Hungary was the other option but its solar is only 18% filled. |
| Netherlands, 2019-2020 | Solar averages 364 MW in 2018, then 1 MW in 2019 and 14 MW in 2020. Wind also falls, from 1,149 MW in 2018 to 819 MW in 2019. The real Dutch solar fleet kept growing in those years, so the data is broken, not the grid. | Replaced NL with Greece (GR). GR has 100% coverage for all three metrics in every year. |
| Italy, 2015 | Wind is empty for almost every hour of 2015 and solar for 75% | Dropped Italy's 2015 rows for all three metrics. Italy's results start in 2016. |

Final list: **DE, FR, ES, IT, GR, BE, AT, DK, CZ, PT**. It still mixes big grids (DE, FR, IT, ES) with small ones (DK, PT, GR), sunny south (ES, PT, IT, GR) and windy north (DK, DE).

## Building the wind column

Not every country has a ready-made total wind column.

- DE, BE, DK: use `XX_wind_generation_actual`. Where it is empty, use onshore + offshore.
- FR, ES, IT, GR, AT, CZ: no offshore wind farms in this data, so wind = onshore.
- PT: the total and offshore columns only start in June 2020, because Portugal's first offshore wind farm came online then. Before that there was nothing at sea to measure, so we treat an empty PT offshore cell as 0 and use onshore + offshore.

We did not apply the PT rule to Belgium. Belgium has had offshore farms the whole time, so an empty BE offshore cell is a real gap, not a zero. About 8% of BE wind hours are missing for this reason (3,934 hours), spread over every month. Step 3 (Job B) explains how the renewable-share formula handles these gaps.

## Wide to long

The original file is wide: one row per hour, one column per country and metric. Hadoop tools work better with long data, one reading per line, because then every line has the same shape and the mapper does not need to know about 300 columns.

```text
wide (1 row, 300 columns)
utc_timestamp,        ..., DE_load..., DE_solar..., DE_wind..., FR_load..., ...
2019-01-01T00:00:00Z, ..., 43120.5,    0.0,         21340.0,    ...

long (one line per reading)
2019-01-01 00:00:00,DE,load,43120.50
2019-01-01 00:00:00,DE,solar,0.00
2019-01-01 00:00:00,DE,wind,21340.00
```

Format decisions:

- No header line. MapReduce, Pig and Hive would each read a header as a data row, so leaving it out saves skipping it in three places.
- The timestamp is written as `yyyy-MM-dd HH:mm:ss`. Hive can cast this text straight to TIMESTAMP and Pig's `ToDate()` reads it with a simple pattern. The `T` and `Z` of the original would need extra handling in both.
- All times stay in UTC. Hive converts to local time in Step 6, where it matters for daily load curves.
- Empty cells are dropped, not written as 0. A missing reading is unknown, and writing 0 would pull averages down.

## Removing bad values

Two later steps showed that the source data has some readings that cannot be real. We found them because the results looked wrong, then traced them back here.

### Spikes (too high)

After the first Pig run (Step 5), the "highest load hour" for France was 158,000 MW on 2020-07-07 at 17:00 UTC. The hours around it were 49,768 and 46,325 MW, while France's highest real hour in 2015-2020 is 94,492 MW, on a cold winter morning. Denmark had several similar jumps.

A reading is removed as a spike when both are true:

- it is more than 25% above the 99.9th percentile of that country and metric, so it is far outside the normal range, and
- it is more than 30% above the median of the 7 hours around it (3 before, itself, 3 after), so it is a sudden jump that falls back.

We use the median of 7 hours, not just the hour before and after, because Denmark on 2017-05-08 had a spike lasting two hours. With only the neighbours, the second bad hour would hide the first. This rule is applied to all three metrics.

### Dips (too low)

After the first Hive run of question 4 (biggest hourly load changes), the top rises and drops were Spanish hours where load fell from about 32,000 to 21,000 MW for one hour and came straight back. Austria showed whole days at about 2,000 MW, against a normal 7,000.

This check is applied to load only. Solar really does fall to 0 when a cloud passes, and wind can drop fast, but a country's demand does not lose a third in one hour. Three rules, for gaps of different length:

| Rule | Catches |
|---|---|
| below 70% of the median of the 7 hours around it | 1 to 3 bad hours |
| below 50% of the median of the 25 hours around it | blocks of up to about 12 hours |
| the day's average below 50% of the country's normal day (median of all its daily averages); the whole day is removed | whole bad days |

The 50% limits are low on purpose. We first tried 60% for the day rule, and it flagged 6 Italian days: Easter Sundays and Mondays, and Sundays in the April 2020 COVID lockdown, at 56 to 65% of a normal day. Those days are real, so the limit went down to 50%, where only the two broken Austrian days remain.

### What was removed

70 readings in total, all listed in `results/prep_report.md`:

| Country | What | Readings |
|---|---|---|
| FR | load spike: 158,000 MW on 2020-07-07 17:00 | 1 |
| DK | load spikes on 7 different hours, 7,389 to 9,618 MW against a normal 4,100 to 5,400 | 7 |
| DK | wind spike on 2017-05-08 06:00-07:00, same hours as a load spike | 2 |
| DK | load dip on 2019-05-01 15:00-16:00 (about 1,700 MW against 3,300) | 2 |
| ES | one-hour load dips on 2015-03-26, 2015-08-26 and 2018-06-05 | 3 |
| AT | whole days 2015-11-29 and 2015-12-25 (average 1,913 and 2,366 MW) | 48 |
| AT | night block 2015-12-28 23:00 to 2015-12-29 04:00, and 2015-01-21 02:00 | 7 |

The Danish dip on 2019-05-01 is in the sample year, so the sample file lost 2 rows.

## Running it

```bash
cd ~/Desktop/BDA/P11-Energy
mkdir -p data
curl -Lo data/time_series_60min_singleindex.csv \
  https://data.open-power-system-data.org/time_series/2020-10-06/time_series_60min_singleindex.csv
.venv/bin/python prep/reshape.py
```

It takes under a minute and writes:

| File | Rows | Size | Used for |
|---|---|---|---|
| `data/energy_full.csv` | 1,480,855 | 52.9 MB | all real runs |
| `data/energy_sample.csv` | 262,011 | 9.4 MB | 2019 only, for quick tests and the scale test |
| `results/prep_report.md` | | | rows kept and dropped per country, for the report |

The `data/` folder is not on GitHub (the raw file is 130 MB). Anyone can rebuild it with the two commands above.

Of 1,512,000 possible readings (50,400 hours × 10 countries × 3 metrics), 31,075 were dropped as empty and 70 as bad values. Of the 31,075 empty ones, 26,280 are Italy's excluded 2015 (8,760 hours × 3 metrics). Of the other 4,795, 3,934 are Belgian wind gaps, and the rest are small gaps of under 110 hours per country and metric.

Rows per year: 2015 has fewer rows because Italy is excluded, and 2020 stops at the end of September.

| Year | Rows |
|---|---|
| 2015 | 235,783 |
| 2016 | 262,435 |
| 2017 | 262,161 |
| 2018 | 262,014 |
| 2019 | 262,011 |
| 2020 | 196,451 |

## Screenshots to take

Save them in `screenshots/01-data/`.

1. `ls -lh data/` showing the raw file and the two output files
2. The terminal output of `prep/reshape.py` (the tables of dropped and kept rows)
3. `head -5 data/energy_full.csv`

## Viva questions for this step

Why did you convert the data from wide to long?
In long format every line has the same four fields, so a mapper can parse any line the same way and use the country and metric as part of the key. With 300 columns the mapper would need to know which column belongs to which country.

Why did you change the country list from the plan?
We checked coverage first. Poland's solar was 92% empty and the Netherlands' 2019 solar averaged 1 MW, which is not believable. A renewable share built on that data would be wrong, so we swapped in Czech Republic and Greece, which have full data.

How did you find the bad values, and how did you remove them?
The results told us. Pig's peak-hour output showed France at 158,000 MW for one hour, almost twice its real peak, and Hive's biggest-hourly-change query was topped by Spanish hours where load fell by a third and came back. We wrote rules for both directions: a reading far above the normal range and the hours around it is a spike; a load reading far below the hours around it is a dip; a day whose average load is under half of a normal day is a bad day. 70 readings were removed out of 1.48 million.

How do you know the rules do not remove real data?
We printed everything each rule would remove before using it. At first the day rule used 60%, and it caught Italian Easter days and lockdown Sundays, which are real. We lowered it to 50%.

Why drop empty cells instead of writing 0?
Zero is a real value (solar at night is 0). An empty cell means we do not know. Writing 0 would make averages and shares too low.

What is the difference between MW and MWh?
MW is power at one moment. MWh is energy over time. One hour at 1,000 MW is 1,000 MWh, so summing hourly MW values gives MWh.

Are the hours local time?
No, the file is in UTC. For the daily load curve (Step 6) Hive converts each country to its own time zone, because people's habits follow local clock time.
