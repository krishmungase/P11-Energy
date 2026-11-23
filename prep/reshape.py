#!/usr/bin/env python3
"""
Step 1 of the project: turn the wide OPSD file into a long file that Hadoop tools can read easily.

Input  (wide, ~50,000 rows x 300 columns):
    utc_timestamp, ..., DE_load_actual_entsoe_transparency, DE_solar_generation_actual, ...

Output (long, one reading per line, NO header line):
    2019-01-01 00:00:00,DE,load,43120.5
    2019-01-01 00:00:00,DE,solar,0.0
    2019-01-01 00:00:00,DE,wind,21340.0

Why no header? MapReduce, Pig and Hive would all treat the header as a data row,
so leaving it out saves us from skipping it in three places.

Why "yyyy-MM-dd HH:mm:ss" and not "2019-01-01T00:00:00Z"? Hive can cast this format
straight to TIMESTAMP and Pig's ToDate() can parse it with a simple pattern.
All times are UTC (the original column is utc_timestamp).

Usage:
    python prep/reshape.py                      # reads data/time_series_60min_singleindex.csv
    python prep/reshape.py --input other.csv --outdir data
Writes:
    data/energy_full.csv     all years (2015 to Sep 2020)
    data/energy_sample.csv   2019 only, for quick tests
    results/prep_report.md   rows kept / dropped per country (goes in the report)
"""
import argparse
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent

# The 10 countries from PLAN.md section 4, with two swaps made after checking the data
# (see docs/03-data.md):
#   Poland (PL) -> Czech Republic (CZ): PL solar is empty for 92% of hours.
#   Netherlands (NL) -> Greece (GR): NL solar falls to ~1 MW average in 2019 and NL wind
#   also drops, while the real NL solar fleet kept growing. The 2019-2020 NL data is broken.
COUNTRIES = ["DE", "FR", "ES", "IT", "GR", "BE", "AT", "DK", "CZ", "PT"]

# Country-years we leave out completely (all three metrics), because one metric is
# almost empty and a share computed from it would be wrong.
#   Italy 2015: wind is empty for ~100% of hours and solar for 75%.
EXCLUDE_YEARS = {("IT", 2015)}

# Portugal's offshore wind column only starts in June 2020, because its first offshore
# wind farm came online then. Before that there was nothing to measure, so for PT an
# empty offshore cell means 0 MW. For other countries (e.g. BE) an empty offshore cell
# is a real gap, so we do not fill it.
OFFSHORE_EMPTY_MEANS_ZERO = {"PT"}
SAMPLE_YEAR = 2019


def wind_series(df, c):
    """Total wind for country c.

    Some countries have a ready-made total column (XX_wind_generation_actual).
    Where that is missing we add onshore + offshore. Countries with no offshore
    column (FR, ES, IT, GR, AT, CZ have no sea wind farms in this data) use onshore only.
    """
    total = f"{c}_wind_generation_actual"
    on = f"{c}_wind_onshore_generation_actual"
    off = f"{c}_wind_offshore_generation_actual"

    if off in df.columns:
        offshore = df[off].fillna(0) if c in OFFSHORE_EMPTY_MEANS_ZERO else df[off]
        built = df[on] + offshore         # NaN if either part is missing
    else:
        built = df[on]

    if total in df.columns:
        if c in OFFSHORE_EMPTY_MEANS_ZERO:
            return df[total].fillna(built), "onshore + offshore (offshore empty before Jun 2020 = 0)"
        return df[total].fillna(built), "total column, gaps filled with onshore+offshore"
    if off in df.columns:
        return built, "onshore + offshore"
    return built, "onshore only (no offshore column)"


def find_spikes(long):
    """Return the rows that are single-hour data errors.

    The Pig job's "peak load hour" showed France at 158,000 MW on 2020-07-07 17:00,
    between 49,768 and 46,325 MW in the hours around it. France's real peak is about
    90,000 MW, in winter. Denmark had similar one- or two-hour jumps.

    A reading counts as a spike when BOTH are true:
      - it is more than 25% above the 99.9th percentile of that country and metric
        (so it is far outside the normal range), and
      - it is more than 30% above the median of the 7 hours around it (3 before,
        itself, 3 after), so it is a sudden jump that falls back again.
    The median ignores up to 3 bad values in the window, so a 2-hour spike is caught too.
    Real load never triples for one hour; real wind cannot exceed installed capacity.
    """
    s = long.sort_values(["country", "metric", "timestamp"])
    g = s.groupby(["country", "metric"])["value"]
    p999 = g.transform(lambda v: v.quantile(0.999))
    median7 = g.transform(lambda v: v.rolling(7, center=True, min_periods=3).median())
    mask = (s["value"] > 1.25 * p999) & (s["value"] > 1.3 * median7)
    return s[mask].assign(median7=median7[mask], reason="spike: far above normal range and the 7 hours around it")


def find_load_dips(long):
    """Return load readings that drop far too low (data errors the other way).

    The first Hive run of question 4 showed Spain's load falling from 32,876 to 21,218 MW
    for one hour and jumping back, and Austria at about 1,000 MW for a whole day
    (normal is about 7,000). Real load does not lose a third of its value for one hour.

    Only load is checked: solar really does drop to 0 when a cloud passes or at sunset,
    and wind really can fall fast. Three rules, each for a different length of gap:
      short dip:  below 70% of the median of the 7 hours around it   (1-3 bad hours)
      long dip:   below 50% of the median of the 25 hours around it  (up to ~12 bad hours)
      bad day:    the day's average is below 50% of the country's normal day
                  (the median of all daily averages); all hours of that day are dropped
    The 50% limits are low on purpose. Italy's quietest real days (Easter, and the
    April 2020 lockdown) sit at 56-65% of a normal day and must stay in the data.
    """
    s = long[long["metric"] == "load"].sort_values(["country", "timestamp"]).copy()
    g = s.groupby("country")["value"]
    median7 = g.transform(lambda v: v.rolling(7, center=True, min_periods=3).median())
    median25 = g.transform(lambda v: v.rolling(25, center=True, min_periods=7).median())
    day = s["timestamp"].dt.strftime("%Y-%m-%d")
    day_mean = s.groupby([s["country"], day])["value"].transform("mean")
    normal_day = s.groupby([s["country"], day])["value"].mean().groupby(level=0).median()
    country_normal = s["country"].map(normal_day)

    short = s["value"] < 0.7 * median7
    long_ = s["value"] < 0.5 * median25
    bad_day = day_mean < 0.5 * country_normal
    mask = short | long_ | bad_day
    reason = pd.Series("", index=s.index)
    reason[short] = "dip: below 70% of the 7 hours around it"
    reason[long_ & ~short] = "dip: below 50% of the 25 hours around it"
    reason[bad_day] = "bad day: daily average below 50% of a normal day"
    return s[mask].assign(median7=median7[mask], reason=reason[mask])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=ROOT / "data" / "time_series_60min_singleindex.csv")
    ap.add_argument("--outdir", default=ROOT / "data")
    args = ap.parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"Reading {args.input} ...")
    df = pd.read_csv(args.input, low_memory=False)
    print(f"Wide file: {df.shape[0]:,} rows x {df.shape[1]} columns")

    ts = pd.to_datetime(df["utc_timestamp"], utc=True)
    # The file starts at 2014-12-31 23:00 UTC (that is midnight in Central Europe).
    # We drop that single 2014 hour so every year we report is a real year.
    keep = ts.dt.year >= 2015
    df, ts = df[keep], ts[keep]

    # Build one small long table per country and metric, then stack them
    parts, notes = [], []
    for c in COUNTRIES:
        wind, how = wind_series(df, c)
        series = {
            "load": df[f"{c}_load_actual_entsoe_transparency"],
            "solar": df[f"{c}_solar_generation_actual"],
            "wind": wind,
        }
        for metric, s in series.items():
            s = s.copy()
            for (xc, xy) in EXCLUDE_YEARS:
                if xc == c:
                    s[ts.dt.year == xy] = float("nan")   # counted as dropped below
            parts.append(pd.DataFrame({"timestamp": ts, "country": c, "metric": metric, "value": s}))
        notes.append((c, how))

    long = pd.concat(parts, ignore_index=True)
    total_rows = len(long)

    # Count empty cells per country and metric before dropping them
    missing = long["value"].isna().groupby([long["country"], long["metric"]]).sum().unstack()
    long = long.dropna(subset=["value"])
    print(f"Long rows before drop: {total_rows:,}  after drop: {len(long):,}")

    # Bad values: upward spikes in any metric first, then load dips on what is left
    spikes = find_spikes(long)
    long = long.drop(spikes.index)
    dips = find_load_dips(long)
    long = long.drop(dips.index)
    bad = pd.concat([spikes, dips])
    print(f"Bad values removed: {len(spikes)} spikes, {len(dips)} load dips")

    long["timestamp"] = long["timestamp"].dt.strftime("%Y-%m-%d %H:%M:%S")
    long = long.sort_values(["timestamp", "country", "metric"])

    full_path = outdir / "energy_full.csv"
    sample_path = outdir / "energy_sample.csv"
    long.to_csv(full_path, index=False, header=False, float_format="%.2f")
    sample = long[long["timestamp"].str.startswith(str(SAMPLE_YEAR))]
    sample.to_csv(sample_path, index=False, header=False, float_format="%.2f")

    # A small markdown report for the project report
    kept = long.groupby(["country", "metric"]).size().unstack()
    years = long.assign(year=long["timestamp"].str[:4]).groupby("year").size()
    lines = [
        "# Data preparation report",
        "",
        f"Source file: `{Path(args.input).name}`, {df.shape[0]:,} hourly rows used (2015-01-01 to the end of the file).",
        f"Long rows possible: {total_rows:,}. Rows dropped (empty cell, or a country-year we excluded): "
        f"{total_rows - len(long) - len(bad):,}. Bad values removed: {len(bad)} "
        f"({len(spikes)} spikes, {len(dips)} load dips). "
        f"Rows kept: {len(long):,}.",
        "",
        f"`energy_full.csv`: {len(long):,} rows, {full_path.stat().st_size / 1e6:.1f} MB",
        f"`energy_sample.csv` ({SAMPLE_YEAR} only): {len(sample):,} rows, {sample_path.stat().st_size / 1e6:.1f} MB",
        "",
        "## Rows dropped per country (empty cells; IT also includes all of 2015, which we excluded)",
        "",
        "| country | load | solar | wind | how wind was built |",
        "|---|---|---|---|---|",
    ]
    for c, how in notes:
        m = missing.loc[c]
        lines.append(f"| {c} | {int(m['load'])} | {int(m['solar'])} | {int(m['wind'])} | {how} |")
    lines += ["", "## Rows kept per country", "", "| country | load | solar | wind |", "|---|---|---|---|"]
    for c in COUNTRIES:
        k = kept.loc[c]
        lines.append(f"| {c} | {int(k['load'])} | {int(k['solar'])} | {int(k['wind'])} |")
    lines += ["", "## Bad values removed", "",
              "Whole bad days (every load hour of the day removed):", ""]
    bd = bad[bad["reason"].str.startswith("bad day")]
    for (c, d), grp in bd.groupby([bd["country"], bd["timestamp"].dt.strftime("%Y-%m-%d")]):
        lines.append(f"- {c} {d}: {len(grp)} hours, average {grp['value'].mean():,.0f} MW")
    lines += ["", "Single readings:", "",
              "| timestamp (UTC) | country | metric | value | median of the 7 hours around it | reason |",
              "|---|---|---|---|---|---|"]
    for _, r in bad[~bad["reason"].str.startswith("bad day")].sort_values(
            ["country", "metric", "timestamp"]).iterrows():
        lines.append(f"| {r.timestamp:%Y-%m-%d %H:%M} | {r.country} | {r.metric} | "
                     f"{r.value:,.0f} | {r.median7:,.0f} | {r.reason} |")
    lines += ["", "## Rows per year", "", "| year | rows |", "|---|---|"]
    lines += [f"| {y} | {n:,} |" for y, n in years.items()]

    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results" / "prep_report.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
