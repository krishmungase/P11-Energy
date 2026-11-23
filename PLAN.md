# P11: Electricity load and renewable energy in Europe

Project plan for the BDA end-semester group project.

## 1. What the project is about

The Open Power System Data (OPSD) project publishes hourly electricity data for European countries. For each hour and each country, the file tells us three things we care about:

- load: how much electricity people used (demand), in MW
- solar generation: how much electricity came from solar panels, in MW
- wind generation: how much came from wind turbines, in MW

The file covers roughly 2015 to 2020. It has about 50,000 rows (one per hour) and more than 300 columns (one column per country per measurement).

A grid operator wants to understand demand and solar/wind output in 10 countries. We have to answer five questions:

1. Which country has the highest renewable share, and how has it changed over the years?
2. What does the daily load curve look like in summer and in winter?
3. When does wind generation peak, and does that line up with demand?
4. Which hours show the largest changes in load?
5. How strongly is solar generation related to load?

Here, renewable share means (solar + wind) / load.

The analysis is simple. The point of the project is to do it with Hadoop tools: HDFS for storage, MapReduce, Pig and Hive for processing, then charts on top of the results.

## 2. Rules we must follow

From the instructions, every group must show all of the following. This list is our checklist.

| Area | What we must show |
|---|---|
| HDFS | 3 or more directories, `fsck` output, one replication change, one file with a non-default block size |
| MapReduce | 2 or more jobs in Java (we are a CE group), with one Combiner and one Partitioner or custom counters. We will do all three. |
| Pig | 6 or more operators from LOAD, FILTER, FOREACH, GROUP, JOIN, ORDER, LIMIT, DISTINCT, UNION, SPLIT, plus built-in functions |
| Hive | One external table, one managed table, one partitioned table, one Parquet or ORC table, one join with GROUP BY and aggregation |
| Charts | 3 or more charts, made from Hive or Pig output |
| Scale test | Same job on a small sample and on the full data, with time and counters recorded |
| Submission | One PDF report, all code, screenshots of every step, GitHub repo, presentation, demo, viva |

The dataset must be cited in the report.

## 3. Tools and setup

What is already on the laptop:

- Hadoop 3.4.2 in `~/Desktop/BDA/tools/hadoop-3.4.2` (used in CE-03)
- JDK 21 (Hadoop runs on it, as in CE-03)
- Python 3

What we still need:

- Apache Hive (with the default embedded Derby metastore, which is enough for one machine)
- Apache Pig
- Python libraries: pandas, matplotlib, pyarrow

Hadoop will run in pseudo-distributed mode, which means all the Hadoop services (NameNode, DataNode, ResourceManager, NodeManager) run on one laptop. That counts as "your own setup".

Hive and Pig versions will be picked during setup based on what works with our Java and Hadoop versions. If a version clash comes up, we install an extra JDK just for that tool and point it there. Every install step goes into `setup/` so anyone in the group can repeat it.

## 4. Choosing the 10 countries

Not every country has all three columns (load, solar, wind). The first script will list the countries that do, and we pick 10 from that list. The likely picks are:

Germany (DE), France (FR), Spain (ES), Italy (IT), Netherlands (NL), Belgium (BE), Austria (AT), Denmark (DK), Poland (PL), Portugal (PT)

These give a good mix: big and small grids, sunny south and windy north. If one of them is missing data, we swap it for another, such as Czech Republic (CZ) or Hungary (HU), and write down why in the report.

Columns we take for each country `XX`:

- `XX_load_actual_entsoe_transparency`
- `XX_solar_generation_actual`
- `XX_wind_generation_actual` (or onshore + offshore added together where the total is missing)

## 5. Step-by-step work

### Step 1: Get and reshape the data (Python)

1. Download `time_series_60min_singleindex.csv` from https://data.open-power-system-data.org/time_series/ and note the version date.
2. Script `prep/reshape.py` keeps only `utc_timestamp` and our 30 or so columns.
3. It turns the wide table into a long one, with one row per reading:

   ```
   timestamp,country,metric,value
   2019-01-01T00:00:00Z,DE,load,43120.5
   2019-01-01T00:00:00Z,DE,solar,0.0
   2019-01-01T00:00:00Z,DE,wind,21340.0
   ```

4. Empty cells are dropped. The script prints how many rows were dropped per country, and that number goes in the report.
5. It writes two files:
   - `energy_sample.csv`: one year only (2019), for quick tests
   - `energy_full.csv`: all years

Output: about 1.5 to 2 million rows in the full file.

### Step 2: HDFS

Commands we run and take screenshots of:

1. Start Hadoop (`start-dfs.sh`, `start-yarn.sh`) and show `jps`.
2. Make directories:
   ```
   /energy/raw        original wide CSV
   /energy/long       reshaped long CSV (sample and full)
   /energy/output     results from MapReduce and Pig
   /energy/warehouse  Hive tables
   ```
3. Upload files with `hdfs dfs -put`.
4. Upload the full file once more with a 32 MB block size instead of the default 128 MB: `hdfs dfs -D dfs.blocksize=33554432 -put ...`
5. Run `hdfs fsck /energy -files -blocks -locations` and show the block count for both uploads.
6. Change replication with `hdfs dfs -setrep -w 2 ...` and run `fsck` again to show the change. On one machine the second copy cannot be placed, so `fsck` will report it as under-replicated. That is expected, and the report says so.

### Step 3: MapReduce in Java

Both jobs read the long CSV from HDFS. One Maven project, folder `mapreduce/`.

**Job A: average load per country per year**

- Mapper: reads a line and keeps it only if metric is `load`. It emits key `country,year` and value `sum=value, count=1`.
- Combiner: adds up the sums and counts on the map side. It does not divide. (This is the same lesson as CE-03: dividing in the combiner gives wrong averages.)
- Partitioner: sends all keys of the same country to the same reducer, so each output file holds whole countries.
- Reducer: adds the sums and counts and divides once to get the average.
- Counters: number of bad lines skipped, number of load records read, number of other records skipped.

**Job B: renewable share per country per month**

- Mapper: key `country,yyyy-mm`, value carries the reading in the right slot (solar, wind or load).
- Combiner: adds solar, wind and load totals separately.
- Reducer: share = (solar + wind) / load for that month.
- The same Partitioner and counters are reused.

We run each job with 2 or more reducers so the Partitioner actually has work to do.

### Step 4: Convert to Parquet

Done in Hive (Step 6): an external table reads the CSV, and `CREATE TABLE ... STORED AS PARQUET AS SELECT ...` writes the Parquet copy. We show the file sizes of CSV and Parquet side by side in HDFS.

### Step 5: Pig

Script `pig/peak_and_daily.pig`:

1. Peak load hour per country: the single hour with the highest load, plus the hour of the day (0 to 23) that has the highest average load.
2. Daily total generation per source: total solar and total wind per country per day.

Operators we will use: LOAD, FILTER, FOREACH, GROUP, ORDER, LIMIT, SPLIT (split rows into load, solar and wind), JOIN (daily generation with daily load), DISTINCT (list of countries). That is 9, more than the 6 needed.

Built-in functions: SUM, MAX, AVG, SUBSTRING, ToDate, GetHour.

Outputs are stored in `/energy/output/pig/`.

### Step 6: Hive

Script `hive/energy.sql`:

1. External table `energy_raw_ext` on the CSV in `/energy/long`.
2. Managed table `energy_parquet`, Parquet format, filled from the external table.
3. Partitioned table `energy_by_year`, partitioned by `year`, stored as ORC, filled with dynamic partitioning. We show `SHOW PARTITIONS`.
4. Join with GROUP BY: a monthly generation table joined to a monthly load table on country and month, grouped to get the share.
5. Ranking: `RANK() OVER (PARTITION BY year ORDER BY share DESC)` to rank countries by renewable share in each year.
6. Biggest hourly load changes: `LAG(value) OVER (PARTITION BY country ORDER BY ts)` gives the previous hour, then we take the difference and pick the top 20 jumps and drops.
7. Extra queries for the questions:
   - average load by hour of day for summer (Jun to Aug) and winter (Dec to Feb)
   - average wind by month and by hour, compared with average load
   - `corr(solar, load)` per country

Each query's output is saved as a CSV for the charts.

### Step 7: Charts (Python, matplotlib)

Planned charts, all built from Hive or Pig output files:

1. Line chart: renewable share per country per year (question 1)
2. Two line charts side by side: hourly load curve, summer vs winter (question 2)
3. Line chart: average wind and average load by month (question 3)
4. Bar chart: top hourly load changes, and the hours of day where they happen (question 4)
5. Scatter plot of solar vs load for one country, plus a bar chart of the correlation for all 10 (question 5)

That is 5 or more charts. Only 3 are required.

### Step 8: Scale test

- Run MapReduce Job A, Job B, the Pig script and two Hive queries on the sample file and then on the full file.
- Record wall-clock time and the key counters (map input records, map output records, combine input/output records, reduce input records, shuffle bytes).
- If the full data still runs too fast to show a difference, we make an enlarged copy (the full file repeated 5 times) and run that too.
- Results go in one table in the report.

A Python script `run_all.py` will run the jobs and collect time and counters automatically, the same way `run_experiment.py` worked in CE-03.

## 6. Folder and GitHub layout

```
P11-Energy/
  README.md          how to set up and run everything
  PLAN.md            this file
  setup/             install notes and config files for Hadoop, Hive, Pig
  prep/              reshape.py
  hdfs/              hdfs_commands.sh
  mapreduce/         Java code (Maven project)
  pig/               Pig scripts
  hive/              Hive scripts
  charts/            make_charts.py and the chart images
  results/           output CSVs, timing table, counters
  screenshots/       one folder per step
  report/            report source and final PDF
  slides/            presentation
```

The raw dataset itself does not go on GitHub because it is too large. The README links to it instead.

## 7. Seven-day timeline

| Day | Work |
|---|---|
| 1 | Install Hive and Pig, start Hadoop, download data, run `reshape.py` |
| 2 | HDFS steps and screenshots. Start the Java MapReduce jobs. |
| 3 | Finish and test both MapReduce jobs on the sample, then on the full data |
| 4 | Pig script, Parquet conversion, Hive tables |
| 5 | Hive analysis queries, scale test, all charts |
| 6 | Write the report, make the slides, clean up GitHub |
| 7 | Practice the demo and viva. Fix anything left over. |

If the group has 4 people, one possible split:

- Person 1: setup, HDFS, scale test
- Person 2: MapReduce (Java)
- Person 3: Pig and Hive
- Person 4: charts, report, slides

Everyone should still be able to explain every part, because the viva can ask anyone anything.

## 8. The report

Planned sections:

1. Title page (group members, PRNs, problem P11)
2. Problem statement
3. Dataset (source, version, citation, columns used, countries chosen and why)
4. Setup (machine, versions, pseudo-distributed mode)
5. Data preparation (wide to long, rows dropped)
6. HDFS (directories, block size, replication, fsck)
7. MapReduce (design of both jobs, combiner, partitioner, counters, output)
8. Pig (script walkthrough, output)
9. Hive (tables, partitions, Parquet, queries, output)
10. Answers to the five questions, each backed by a table or chart
11. Scale test results
12. Problems we hit and how we fixed them
13. Conclusion (short, only what we found)
14. References

Dataset citation (to be checked against the version we download):

> Open Power System Data. 2020. Data Package Time series. Version 2020-10-06. https://doi.org/10.25832/time_series/2020-10-06

## 9. Writing style for the report and slides

The report should read like students wrote it after doing the work. Rules we will follow, based on Wikipedia's "Signs of AI writing" page:

- Use plain, specific sentences. Write "Germany's share rose from 25% in 2015 to 38% in 2019", not "Germany showcases a remarkable transformation".
- Avoid filler words such as delve, crucial, pivotal, robust, seamless, showcase, underscore, landscape, tapestry, testament, leverage, and "plays a vital role".
- Don't open with "In today's world..." and don't end sections with summary lines like "Overall, this highlights...".
- Don't use "not only X but also Y" or groups of three adjectives just for rhythm.
- Keep em dashes rare. Use commas, full stops or brackets.
- Use bold sparingly and keep bullet lists short. Most of the report should be normal paragraphs.
- Write headings in sentence case, not Title Case Everywhere.
- Every claim needs a number, table or chart from our own output behind it.
- Mention real problems we hit (a failed job, a Java version clash, missing data). Real reports have these.
- Use no emojis, no "I hope this helps", no "As an AI".

## 10. Viva preparation

We will keep a short list of likely questions with answers in our own words, for example:

- What is a block? Why is the default 128 MB?
- What happens when replication is set to 2 on a single node?
- Why can't the combiner divide when computing an average?
- What does the Partitioner do, and what happens with 1 reducer?
- Difference between an external and a managed table in Hive. What happens on DROP?
- Why is Parquet faster for these queries than CSV?
- What does LAG do?
- Why did the full run take less than 10 times the sample time, even with about 6 times more data?
