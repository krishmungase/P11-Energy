# Step 7: charts

Owner: Snehal Mane (Sneh913)

All charts are drawn by one script, `charts/make_charts.py`, from the CSV files that Hive and Pig wrote. No chart reads the raw data, so every number on a chart comes out of a Hadoop job.

```bash
.venv/bin/python charts/make_charts.py     # a few seconds; writes charts/*.png
```

It needs `results/hive/*.csv` (from `bash hive/export_results.sh`) and `results/pig/full/daily.csv` (from `bash pig/run_pig.sh`).

## The charts

| File | Question | Drawn from | Kind |
|---|---|---|---|
| `1_share_by_year.png` | 1 | Hive `share_yearly.csv` | heatmap with values |
| `2_load_curve_summer_winter.png` | 2 | Hive `load_curve_season.csv` | 10 small line charts |
| `3a_wind_vs_load_by_month.png` | 3 | Hive `wind_load_by_month.csv` | 10 small line charts, indexed |
| `3b_wind_vs_load_by_hour.png` | 3 | Hive `wind_load_by_hour.csv` | 10 small line charts, indexed |
| `4a_load_change_by_hour.png` | 4 | Hive `load_change_by_hour.csv` (LAG) | heatmap, red/blue |
| `4b_top_load_changes_by_hour.png` | 4 | Hive `top_load_changes.csv` (LAG) | two bar charts |
| `5a_scatter_solar_load_DE_2019.png` | 5 | Hive `scatter_de_2019.csv` | scatter plot |
| `5b_correlation_solar_load.png` | 5 | Hive `correlation.csv` (corr) | bar chart |
| `6_pig_daily_share.png` | 1 | Pig `daily.csv` | line chart, 30-day average |

The rules ask for at least 3 charts from Hive or Pig output; we have 9, at least one per question, and one from Pig.

## Design choices

These are the decisions we made so the charts are easy to read, in print as well.

Ten countries on one line chart is too many. Ten colours cannot all be told apart, especially by colour-blind readers, and the lines cross. So we used two other forms. A heatmap (chart 1, 4a) puts countries in rows and years or hours in columns, and writes the value in each cell. Small multiples (charts 2, 3a, 3b) give each country its own small panel with the same axes, so the eye compares shapes.

No chart has two y-axes. Wind (a few GW) and load (tens of GW) do not fit on one scale, and a second axis on the right makes any two lines look related or unrelated depending on how the axes are scaled. Charts 3a and 3b instead divide each series by its own average, so 100 means "average", 130 means "30% above average", and both lines share one axis.

Colours: blue (`#2a78d6`) and orange (`#eb6834`) for the two-series charts, the same pair everywhere (winter/summer, wind/load). The pair was checked with a colour-blindness simulator: the colour difference is 24.7 under the worst type of colour blindness, against a target of at least 8. Chart 6 adds green as a third colour. The heatmap for share uses shades of one colour (light = low, dark = high). The heatmap for change uses two colours with grey in the middle (blue = falling, grey = no change, red = rising), because the sign matters there.

Every value that matters is written on the chart (the percentages in chart 1, the correlations in chart 5b), so the chart can be read without guessing from the colour.

## Problems we hit

- Chart 4b first showed counts like 2.5 and 17.5 on the y-axis, which make no sense for a number of hours. Fixed with an integer-only axis.
- In chart 5b, France's label (-0.03) sat on top of its bar, because the bar is negative. Labels for negative bars now go on the left.
- Chart 6 started at 100% for Denmark in January 2015, because a 30-day average over the first day is just one day. The line now starts only when at least 20 of the 30 days have data. (With 30 of 30, a single missing German day in February 2015 cut a hole in the line.)
- Before the data cleaning (docs/01), chart 4b was all Spanish one-hour dips. The chart is how we noticed.

## Screenshots to take

Save them in `screenshots/07-charts/`: the terminal running `make_charts.py`, and the `charts/` folder. The PNG files themselves go into the report.

## Viva questions for this step

Where does the data for the charts come from?
From the CSV files Hive and Pig wrote to HDFS, copied to `results/` by our export scripts. The chart script only draws; it does no analysis.

Why a heatmap and not a line chart for the yearly share?
Ten lines in ten colours are hard to tell apart. A heatmap shows all 59 numbers at once, written in the cells, and the colour shows the pattern (Denmark dark at the top, Czechia light at the bottom, everything getting darker to the right).

Why are wind and load "indexed" in chart 3?
They have very different sizes. Dividing each by its own average puts both around 100, so you can see when each is above or below its normal level, on one axis. A second y-axis would let us make the lines look as close or as far apart as we liked.

What does the scatter plot show?
Each dot is one hour of 2019 in Germany. The column of dots at 0 GW solar is the night. In daylight, more solar goes with higher load, but loosely: r = 0.31. The two clouds (around 65 GW and 50 GW load) are working days and weekends.
