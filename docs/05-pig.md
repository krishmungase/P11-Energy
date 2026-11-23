# Step 5: Pig

Owner: Vaishnavi Bhosale (Vaishnavi063)

Pig is a scripting language for Hadoop. You describe a data flow step by step (load, filter, group, join, store), and Pig turns it into MapReduce jobs. Compared with writing Java, a 100-line Pig script replaces several MapReduce programs.

Script: `pig/peak_and_daily.pig`. Runner: `pig/run_pig.sh`.

## What the script computes

| Output folder | Contents | Used for |
|---|---|---|
| `countries/` | the distinct countries in the data | a check that all 10 are there |
| `peak_hour/` | each country's single highest-load hour | question 4 context, and how we found the bad data |
| `hourly_profile/` | average load for each hour of the day (UTC), per country | |
| `peak_hour_of_day/` | the hour of the day with the highest average load | question 2 |
| `daily/` | per country and day: solar MWh, wind MWh, load MWh, renewable share | chart 6 |
| `top_wind_days/` | the 10 days with the most wind energy, any country | question 3 |

Outputs go to `/energy/output/pig/full/` in HDFS. `run_pig.sh` copies each one to `results/pig/full/<name>.csv` and adds a header line, because Pig's `STORE` writes none.

## Operators and functions used

The rules ask for at least 6 operators and some built-in functions. The script uses 10 operators:

| Operator | Where in the script | What it does there |
|---|---|---|
| `LOAD` | `raw = LOAD '$INPUT' USING PigStorage(',') AS (...)` | reads the CSV and names and types the 4 columns |
| `FILTER` | `clean = FILTER raw BY ... value >= 0` | drops lines whose value is missing or negative |
| `SPLIT` | `SPLIT clean INTO load_rows IF ..., solar_rows IF ..., wind_rows IF ...` | one pass over the data, three relations out |
| `FOREACH ... GENERATE` | many places | picks and computes columns, like SELECT in SQL |
| `DISTINCT` | `countries = DISTINCT country_col` | removes duplicate countries |
| `GROUP` | `GROUP load_rows BY country`, `GROUP load_hour BY (country, hour)` | collects rows with the same key into a bag |
| `ORDER` | inside a nested FOREACH, and `ORDER daily BY wind_mwh DESC` | sorts |
| `LIMIT` | `LIMIT sorted 1`, `LIMIT by_wind 10` | keeps the first n rows |
| `JOIN` | `JOIN solar_daily BY (country, day), wind_daily BY (country, day)`, then with `load_daily` | matches rows from two relations on a key |
| `STORE` | 6 times | writes a relation to HDFS |

Built-in functions: `SUM`, `MAX`, `AVG`, `COUNT` (aggregates over a bag), `SUBSTRING` (cuts "2019-06-01" out of "2019-06-01 12:00:00"), `ToDate` (text to a date-time, in UTC), `GetHour` (hour 0 to 23 from a date-time).

### The parts that need a second look

Nested FOREACH. To find each country's highest hour, we group by country and then, inside the FOREACH, sort that country's bag and keep the first row:

```pig
peak_hour = FOREACH load_by_country {
    sorted = ORDER load_rows BY value DESC;
    top    = LIMIT sorted 1;
    GENERATE group AS country, FLATTEN(top.ts) AS ts, MAX(load_rows.value) AS peak_mw;
};
```

`group` is the name Pig gives to the grouping key. `FLATTEN` turns a bag with one tuple into plain columns.

The join. A day is kept only if it has solar, wind and load data, because `JOIN` is an inner join. After a join, two columns can have the same name (`country` from both sides), so Pig names them `solar_daily::country` and `wind_daily::country`, and we pick one.

`$INPUT` and `$OUTPUT` are parameters. `%default` gives them values for the sample run, and `-param INPUT=...` on the command line overrides them. `rmf $OUTPUT` at the top deletes old output first, because STORE fails if the folder exists.

## How Pig turned the script into jobs

Pig printed a "Job Stats" table at the end of the run (`results/pig/full/job_stats.txt`). The full-data run started 13 MapReduce jobs. Some things worth pointing out:

- The first job carries many aliases at once (`MULTI_QUERY`). Pig noticed that several branches read the same input, and computed them in one pass instead of reading the file once per branch.
- Jobs marked `COMBINER`: Pig added a combiner by itself for `SUM`, `COUNT` and `AVG`, because those can be computed partly on the map side. In Java we had to write the combiner ourselves.
- Jobs marked `SAMPLER` followed by `ORDER_BY`: a global ORDER needs two jobs. The first samples the data to choose split points, so that each reducer gets a sorted range; the second does the sort.
- Jobs marked `HASH_JOIN`: our two JOINs. Their map count is 2 because they read two inputs.

## Running it

```bash
bash pig/run_pig.sh            # full data, about 5 minutes
bash pig/run_pig.sh sample     # 2019 only, about 5 minutes too
```

Both take about the same time. With 13 jobs, most of the time is spent starting and finishing jobs on YARN (around 20 seconds each), not on processing the data.

To try lines one by one, start the interactive shell, called Grunt:

```bash
source env.sh
pig -x mapreduce
grunt> raw = LOAD '/energy/long/sample' USING PigStorage(',') AS (ts:chararray, country:chararray, metric:chararray, value:double);
grunt> DESCRIBE raw;
grunt> few = LIMIT raw 5;
grunt> DUMP few;
```

`DESCRIBE` prints the schema. `DUMP` runs the job and prints the result. `ILLUSTRATE few;` shows a small example of each step, which is useful in the demo.

## Problem we hit

Pig 0.18 failed with `ClassNotFoundException: org.apache.commons.collections.buffer.CircularFifoBuffer`. Hadoop 3.4 only ships commons-collections 4, while Pig still uses version 3. The first fix (adding the jar to `PIG_CLASSPATH`) let the job driver run, but the map tasks inside YARN still failed, because they do not see our local classpath. The working fix in `env.sh` also passes `-Dpig.additional.jars=...`, which ships the jar to every task.

## Results

Full data, 1,480,915 rows, 304 seconds, 13 MapReduce jobs.

Single highest-load hour per country (`peak_hour.csv`, times in UTC):

| Country | Hour (UTC) | Load (MW) |
|---|---|---|
| FR | 2018-02-28 08:00 | 94,492 |
| DE | 2017-12-13 16:00 | 77,549 |
| IT | 2019-07-25 14:00 | 53,824 |
| ES | 2017-01-18 19:00 | 41,015 |
| BE | 2015-01-22 17:00 | 13,670 |
| CZ | 2018-02-28 08:00 | 11,142 |
| AT | 2018-12-13 16:00 | 10,803 |
| GR | 2015-07-30 10:00 | 9,749 |
| PT | 2020-01-13 19:00 | 8,850 |
| DK | 2019-11-04 07:00 | 6,750 |

Most peaks are on winter days. France and Czechia peak in the same hour, 28 February 2018, during a cold wave across Europe; France heats many homes with electricity. Italy and Greece peak in July, when air conditioning runs.

This table is also how we found bad data. On the first run France's peak was 158,000 MW on 2020-07-07, with about 48,000 MW in the hours before and after, and Denmark's was 9,618 MW. We traced both to single-hour spikes in the source data and removed them in `prep/reshape.py` (see `docs/01-data.md`). The run above is on the cleaned data.

Hour of the day with the highest average load (`peak_hour_of_day.csv`, UTC):

| Country | Peak hour (UTC) | Local time |
|---|---|---|
| AT, BE, CZ | 9 | 10:00 to 11:00 |
| DE, FR | 10 | 11:00 to 12:00 |
| ES | 11 | 12:00 to 13:00 |
| DK | 16 | 17:00 to 18:00 |
| IT | 17 | 18:00 to 19:00 |
| GR | 17 | 19:00 to 20:00 |
| PT | 19 | 19:00 to 20:00 |

(Local time shown for winter; add one more hour in summer.) The central European countries peak in the late morning, when offices and industry run. Denmark, Italy, Greece and Portugal peak in the evening, when people are home, cooking and lighting.

The 10 windiest days (`top_wind_days.csv`) are all in Germany, the biggest wind fleet. The top one is 2020-02-11 with 1,034,085 MWh of wind in one day, right after storm Sabine (also called Ciara) crossed Germany on 9 and 10 February. On 2020-02-22 wind and solar covered 83% of German load.

From `daily.csv` (20,629 country-days): Denmark's average daily share is 46%, and on 2020-05-16 Danish wind and solar produced 131% of Danish load. A share above 100% means the country made more than it used and exported the rest.

Note: the daily share here divides plain totals (solar MWh + wind MWh) / load MWh. For a day with missing wind hours (Belgium) this is a little too low. MapReduce Job B and Hive use per-metric averages to avoid that; for the chart of daily shares in Pig we show Denmark, Germany and France, which have almost no gaps.

## Screenshots to take

Save them in `screenshots/05-pig/`.

1. The end of `bash pig/run_pig.sh`, showing "Success!" and the Job Stats table
2. `cat results/pig/full/peak_hour.csv` and `peak_hour_of_day.csv`
3. `cat results/pig/full/top_wind_days.csv`
4. The ResourceManager page (http://localhost:8088) with the 13 Pig jobs, whose names start with "PigLatin:peak_and_daily.pig"
5. A Grunt session with `DESCRIBE` and `DUMP`

## Viva questions for this step

What is the difference between Pig and MapReduce?
MapReduce is the engine. Pig is a language on top: Pig Latin describes the steps, and Pig compiles them into MapReduce jobs. A GROUP becomes a shuffle, a FILTER happens in the mapper, a JOIN becomes a job that reads both inputs.

What is a relation, a bag and a tuple?
A tuple is one row, like (DE, 2019-01-01, 43120.5). A bag is a collection of tuples. A relation is the outer bag that a statement produces, like `raw` or `clean`. After `GROUP`, each row holds the key and a bag of all rows with that key.

What does SPLIT do, and why not three FILTERs?
SPLIT sends each row to one or more output relations based on conditions, in one pass. Three FILTERs would describe three passes, although Pig's optimizer can often merge them.

Why does ORDER need two jobs?
To sort across several reducers, each reducer must get one range of keys. Pig first runs a small sampling job to find where to cut the ranges, then the real sort job.

Is Pig lazy?
Yes. Statements only build a plan. Nothing runs until `STORE` or `DUMP`. That is why Pig can see the whole script and merge steps (the MULTI_QUERY job).

Why is the hour in Pig in UTC, but in Hive in local time?
`ToDate(ts, format, 'UTC')` keeps the time zone of the data. We did the local-time conversion only in Hive (Step 6), where the daily load curves are drawn. In Pig's peak_hour_of_day, Central European countries show their peak at 9 to 10 UTC, which is 10 to 12 local time.
