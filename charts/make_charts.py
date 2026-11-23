#!/usr/bin/env python3
"""
Step 7: draws every chart for the report from the Hive and Pig output files.

Input  results/hive/*.csv   (made by hive/export_results.sh)
       results/pig/full/*.csv (made by pig/run_pig.sh)
Output charts/*.png        (150 dpi, for the report and slides)

Run:   .venv/bin/python charts/make_charts.py

Design rules we follow (so the charts are easy to read and print):
- No chart has two y-axes. When two measures have different units or sizes
  (wind MW vs load MW), we index both to 100 = their own yearly average.
- Ten countries in one line chart are hard to tell apart by colour, so we use
  small multiples (one small panel per country) or a heatmap instead.
- Two-series charts use the same blue and orange everywhere, checked for
  colour-blind safety.
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")                     # draw to files, no window
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm
from matplotlib.ticker import MaxNLocator

ROOT = Path(__file__).resolve().parent.parent
HIVE = ROOT / "results" / "hive"
PIG = ROOT / "results" / "pig" / "full"
OUT = ROOT / "charts"

# Colours (validated: colour-blind distance 24.7, normal-vision 33.6, both >= 3:1 contrast)
BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, INK_2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
# Sequential blue ramp (light -> dark) and a blue <-> red diverging ramp with a grey middle
SEQ = LinearSegmentedColormap.from_list("seq", ["#cde2fb", "#86b6ef", "#3987e5", "#1c5cab", "#0d366b"])
DIV = LinearSegmentedColormap.from_list("div", ["#1c5cab", "#86b6ef", "#f0efec", "#f0a0a0", "#c0392b"])

COUNTRY_NAMES = {"AT": "Austria", "BE": "Belgium", "CZ": "Czechia", "DE": "Germany",
                 "DK": "Denmark", "ES": "Spain", "FR": "France", "GR": "Greece",
                 "IT": "Italy", "PT": "Portugal"}

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK_2, "xtick.color": INK_2, "ytick.color": INK_2,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6,
    "axes.spines.top": False, "axes.spines.right": False,
    "font.size": 9, "axes.titlesize": 10, "axes.titleweight": "bold", "axes.titlecolor": INK,
    "lines.linewidth": 2, "legend.frameon": False,
})


def save(fig, name):
    path = OUT / name
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"   {path.relative_to(ROOT)}")


def small_multiples(nrows=2, ncols=5, **kw):
    fig, axes = plt.subplots(nrows, ncols, figsize=(13, 5.2), **kw)
    return fig, axes.flatten()


# ---------------------------------------------------------------------------------
# Chart 1 (Q1): renewable share per country per year, as a heatmap with values
# ---------------------------------------------------------------------------------
def chart_share_yearly():
    df = pd.read_csv(HIVE / "share_yearly.csv")
    grid = df.pivot(index="country", columns="year", values="share") * 100
    order = grid[2019].sort_values(ascending=False).index     # highest share in 2019 on top
    grid = grid.loc[order]

    fig, ax = plt.subplots(figsize=(8, 5))
    im = ax.imshow(grid.values, cmap=SEQ, vmin=0, vmax=np.nanmax(grid.values), aspect="auto")
    ax.set_xticks(range(len(grid.columns)), [str(c) for c in grid.columns])
    ax.set_yticks(range(len(grid.index)), [f"{COUNTRY_NAMES[c]} ({c})" for c in grid.index])
    ax.grid(False)
    for i in range(grid.shape[0]):
        for j in range(grid.shape[1]):
            v = grid.values[i, j]
            if np.isnan(v):
                ax.text(j, i, "no data", ha="center", va="center", color=INK_2, fontsize=7)
            else:
                ax.text(j, i, f"{v:.0f}%", ha="center", va="center", fontsize=8,
                        color="white" if v > 0.55 * np.nanmax(grid.values) else INK)
    ax.set_title("Renewable share (solar + wind) / load, by year")
    ax.set_xlabel("Year (2020 = January to September)")
    cb = fig.colorbar(im, ax=ax, shrink=0.8)
    cb.set_label("share of load (%)")
    cb.outline.set_visible(False)
    save(fig, "1_share_by_year.png")


# ---------------------------------------------------------------------------------
# Chart 2 (Q2): daily load curve, summer vs winter, one panel per country
# ---------------------------------------------------------------------------------
def chart_load_curve():
    df = pd.read_csv(HIVE / "load_curve_season.csv")
    countries = sorted(df.country.unique())
    fig, axes = small_multiples(sharex=True)
    for ax, c in zip(axes, countries):
        d = df[df.country == c]
        for season, colour in (("winter", BLUE), ("summer", ORANGE)):
            s = d[d.season == season].sort_values("local_hour")
            ax.plot(s.local_hour, s.avg_load_mw / 1000, color=colour, label=season.capitalize())
        ax.set_title(COUNTRY_NAMES[c])
        ax.set_xticks([0, 6, 12, 18, 23])
    for ax in axes[::5]:
        ax.set_ylabel("average load (GW)")
    for ax in axes[5:]:
        ax.set_xlabel("local hour")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", ncol=2, bbox_to_anchor=(1, 1.02))
    fig.suptitle("Daily load curve: winter (Dec-Feb) vs summer (Jun-Aug), 2015-2020",
                 x=0.01, ha="left", fontweight="bold", color=INK)
    fig.tight_layout()
    save(fig, "2_load_curve_summer_winter.png")


# ---------------------------------------------------------------------------------
# Chart 3 (Q3): wind and load by month, both indexed to 100 = yearly average
# ---------------------------------------------------------------------------------
def chart_wind_vs_load_month():
    df = pd.read_csv(HIVE / "wind_load_by_month.csv")
    countries = sorted(df.country.unique())
    fig, axes = small_multiples(sharex=True, sharey=True)
    for ax, c in zip(axes, countries):
        d = df[df.country == c].sort_values("month_of_year")
        ax.axhline(100, color=INK_2, linewidth=0.8)
        ax.plot(d.month_of_year, 100 * d.avg_wind_mw / d.avg_wind_mw.mean(), color=BLUE, label="Wind")
        ax.plot(d.month_of_year, 100 * d.avg_load_mw / d.avg_load_mw.mean(), color=ORANGE, label="Load")
        ax.set_title(COUNTRY_NAMES[c])
        ax.set_xticks([1, 4, 7, 10], ["Jan", "Apr", "Jul", "Oct"])
    for ax in axes[::5]:
        ax.set_ylabel("index (100 = yearly average)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", ncol=2, bbox_to_anchor=(1, 1.02))
    fig.suptitle("Wind generation and load by month (each indexed to its own yearly average)",
                 x=0.01, ha="left", fontweight="bold", color=INK)
    fig.tight_layout()
    save(fig, "3a_wind_vs_load_by_month.png")


def chart_wind_vs_load_hour():
    df = pd.read_csv(HIVE / "wind_load_by_hour.csv")
    countries = sorted(df.country.unique())
    fig, axes = small_multiples(sharex=True, sharey=True)
    for ax, c in zip(axes, countries):
        d = df[df.country == c].sort_values("local_hour")
        ax.axhline(100, color=INK_2, linewidth=0.8)
        ax.plot(d.local_hour, 100 * d.avg_wind_mw / d.avg_wind_mw.mean(), color=BLUE, label="Wind")
        ax.plot(d.local_hour, 100 * d.avg_load_mw / d.avg_load_mw.mean(), color=ORANGE, label="Load")
        ax.set_title(COUNTRY_NAMES[c])
        ax.set_xticks([0, 6, 12, 18, 23])
    for ax in axes[::5]:
        ax.set_ylabel("index (100 = daily average)")
    for ax in axes[5:]:
        ax.set_xlabel("local hour")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", ncol=2, bbox_to_anchor=(1, 1.02))
    fig.suptitle("Wind generation and load by hour of day (each indexed to its own average)",
                 x=0.01, ha="left", fontweight="bold", color=INK)
    fig.tight_layout()
    save(fig, "3b_wind_vs_load_by_hour.png")


# ---------------------------------------------------------------------------------
# Chart 4 (Q4): which hours have the largest load changes
# ---------------------------------------------------------------------------------
def chart_load_change_heatmap():
    df = pd.read_csv(HIVE / "load_change_by_hour.csv")
    grid = df.pivot(index="country", columns="local_hour", values="avg_change_pct")
    grid = grid.loc[sorted(grid.index)]
    lim = np.nanmax(np.abs(grid.values))
    fig, ax = plt.subplots(figsize=(11, 4.6))
    im = ax.imshow(grid.values, cmap=DIV, norm=TwoSlopeNorm(0, -lim, lim), aspect="auto")
    ax.set_xticks(range(24), [str(h) for h in range(24)])
    ax.set_yticks(range(len(grid.index)), [COUNTRY_NAMES[c] for c in grid.index])
    ax.grid(False)
    ax.set_xlabel("local hour (change from the hour before into this hour)")
    ax.set_title("Average hour-to-hour change in load (% of load). Red = load rising, blue = falling")
    cb = fig.colorbar(im, ax=ax, shrink=0.85)
    cb.set_label("average change (%)")
    cb.outline.set_visible(False)
    save(fig, "4a_load_change_by_hour.png")


def chart_top_changes():
    df = pd.read_csv(HIVE / "top_load_changes.csv")
    fig, axes = plt.subplots(1, 2, figsize=(11, 3.6), sharey=True)
    for ax, direction, colour, title in ((axes[0], "rise", ORANGE, "20 largest rises"),
                                         (axes[1], "drop", BLUE, "20 largest drops")):
        d = df[df.direction == direction]
        counts = d.local_hour.value_counts().reindex(range(24), fill_value=0)
        ax.bar(counts.index, counts.values, color=colour, width=0.8)
        ax.set_title(f"{title}: hour of day they happened")
        ax.set_xticks([0, 3, 6, 9, 12, 15, 18, 21])
        ax.set_xlabel("local hour")
        ax.grid(axis="x", visible=False)
        ax.yaxis.set_major_locator(MaxNLocator(integer=True))   # counts are whole hours
        ax.set_ylim(0, 22)
        top_c = ", ".join(f"{c} {n}" for c, n in d.country.value_counts().items())
        ax.text(0.98, 0.95, f"countries: {top_c}", transform=ax.transAxes, va="top", ha="right",
                fontsize=8, color=INK_2)
    axes[0].set_ylabel("number of hours")
    fig.tight_layout()
    save(fig, "4b_top_load_changes_by_hour.png")


# ---------------------------------------------------------------------------------
# Chart 5 (Q5): solar vs load
# ---------------------------------------------------------------------------------
def chart_scatter():
    df = pd.read_csv(HIVE / "scatter_de_2019.csv")
    r = np.corrcoef(df.solar_mw, df.load_mw)[0, 1]
    fig, ax = plt.subplots(figsize=(6.5, 4.6))
    ax.scatter(df.solar_mw / 1000, df.load_mw / 1000, s=6, color=BLUE, alpha=0.25, linewidths=0)
    ax.set_xlabel("solar generation (GW)")
    ax.set_ylabel("load (GW)")
    ax.set_title(f"Germany 2019: solar vs load, every hour (r = {r:.2f}, n = {len(df):,})")
    save(fig, "5a_scatter_solar_load_DE_2019.png")


def chart_correlation():
    df = pd.read_csv(HIVE / "correlation.csv").sort_values("corr_solar_load")
    fig, ax = plt.subplots(figsize=(7, 4.4))
    ax.barh([COUNTRY_NAMES[c] for c in df.country], df.corr_solar_load, color=BLUE, height=0.65)
    for y, v in enumerate(df.corr_solar_load):
        # label just outside the end of the bar, on the left for negative values
        ax.text(v + (0.01 if v >= 0 else -0.01), y, f"{v:.2f}", va="center",
                ha="left" if v >= 0 else "right", fontsize=8, color=INK)
    ax.axvline(0, color=INK_2, linewidth=0.8)
    ax.set_xlim(min(0, df.corr_solar_load.min()) - 0.08, 0.5)
    ax.set_xlabel("correlation between hourly solar and hourly load (Pearson r)")
    ax.set_title("How strongly solar output moves with demand, 2015-2020")
    ax.grid(axis="y", visible=False)
    save(fig, "5b_correlation_solar_load.png")


# ---------------------------------------------------------------------------------
# Chart 6 (Pig output): daily renewable share, 30-day rolling mean, three countries
# ---------------------------------------------------------------------------------
def chart_pig_daily():
    df = pd.read_csv(PIG / "daily.csv", parse_dates=["day"])
    pick = [("DK", BLUE), ("DE", ORANGE), ("FR", "#1baf7a")]   # first three categorical slots
    fig, ax = plt.subplots(figsize=(10, 4))
    for c, colour in pick:
        d = df[df.country == c].sort_values("day").set_index("day")
        # min_periods: draw a point only when at least 20 of the 30 days have data
        roll = d.share.rolling("30D", min_periods=20).mean() * 100
        ax.plot(roll.index, roll.values, color=colour, linewidth=1.6, label=COUNTRY_NAMES[c])
        roll = roll.dropna()
        ax.text(roll.index[-1], roll.values[-1], f"  {COUNTRY_NAMES[c]}", va="center",
                fontsize=8, color=INK)
    ax.set_ylabel("renewable share of load (%)")
    ax.set_title("Daily renewable share from the Pig job, 30-day rolling average")
    ax.legend(loc="upper left")
    save(fig, "6_pig_daily_share.png")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    print("Drawing charts:")
    chart_share_yearly()
    chart_load_curve()
    chart_wind_vs_load_month()
    chart_wind_vs_load_hour()
    chart_load_change_heatmap()
    chart_top_changes()
    chart_scatter()
    chart_correlation()
    chart_pig_daily()
