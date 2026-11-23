# Steps 4 and 6: Hive (tables, Parquet and analysis)

Owner: Vaishnavi Bhosale (Vaishnavi063)

Hive lets us query files in HDFS with SQL. A query is compiled into MapReduce jobs and run on YARN, like Pig. The table definitions (column names, types, file locations) live in a small database called the metastore; the data itself stays in HDFS.

| File | What it does |
|---|---|
| `hive/init.sql` | runs at the start of every session; adds one jar the YARN tasks need |
| `hive/run_hive.sh` | runs a script with beeline in embedded mode |
| `hive/01_tables.sql` | creates all tables (Step 4 Parquet conversion is part of it) |
| `hive/02_analysis.sql` | the queries for the five questions |
| `hive/export_results.sh` | copies results to `results/hive/*.csv`, compares formats |
| `setup/hive-site.xml.template` | Hive config (explained below) |

## Running it

```bash
bash hive/run_hive.sh hive/01_tables.sql      # about 4 minutes
bash hive/run_hive.sh hive/02_analysis.sql    # about 12 minutes
bash hive/export_results.sh                   # about 2 minutes
bash hive/run_hive.sh                         # interactive prompt, for the demo
```

Hive 4 has no `hive` shell any more. `beeline -u jdbc:hive2://` (note: nothing after the `//`) starts Hive inside the beeline process itself, so we do not need a separate HiveServer2 service.

## The tables

| Table | Kind | Format | Location in HDFS | Rows |
|---|---|---|---|---|
| `energy_raw_ext` | external | CSV text | `/energy/long/full` | 1,480,855 |
| `energy_raw_ext_sample` | external | CSV text | `/energy/long/sample` | 262,011 |
| `energy_parquet` | managed | Parquet (Snappy) | `/energy/warehouse/energy.db/energy_parquet` | 1,480,855 |
| `energy_by_year` | managed, partitioned by `year` | ORC | `/energy/warehouse/energy.db/energy_by_year/year=2015 ... year=2020` | 1,480,855 |
| `energy_hourly` | managed | Parquet | `/energy/warehouse/energy.db/energy_hourly` | 495,172 |
| `load_changes` | managed | Parquet | made by `02_analysis.sql` | 494,875 |

### External vs managed

`energy_raw_ext` is `CREATE EXTERNAL TABLE ... LOCATION '/energy/long/full'`. Hive only records where the files are. `DROP TABLE energy_raw_ext` removes the definition and leaves the CSV in HDFS, which matters because MapReduce and Pig read the same files.

`energy_parquet` is a plain `CREATE TABLE ... AS SELECT`. Hive owns the files and puts them under the warehouse folder. `DROP TABLE energy_parquet` deletes the table and its files.

`DESCRIBE FORMATTED <table>` shows which kind a table is, in the line `Table Type: EXTERNAL_TABLE` or `MANAGED_TABLE` (see `results/hive/01_tables_output.txt`).

Problem we hit: on the first run, `DESCRIBE FORMATTED energy_parquet` said `EXTERNAL_TABLE` with `TRANSLATED_TO_EXTERNAL = TRUE`, although we never wrote EXTERNAL. Hive 4 converts every managed table that is not transactional (ACID) into an external table with `external.table.purge = TRUE`, so that DROP still deletes the files. The rules ask for a managed table, so `hive-site.xml` turns this off with `metastore.metadata.transformer.class` set to a blank value. Our first try used a wrong property name (`metastore.metastore.transformer.class`) and had no effect; we found the right name in the Hive metastore jar.

### Parquet (Step 4)

`energy_parquet` is created from the external CSV table with `CREATE TABLE ... STORED AS PARQUET AS SELECT`. While copying, it also adds columns that the queries need again and again: the timestamp as a real `TIMESTAMP`, year, month, UTC hour, and `local_ts`, the time in the country's own time zone:

```sql
from_utc_timestamp(CAST(ts AS TIMESTAMP),
    CASE country WHEN 'PT' THEN 'Europe/Lisbon'
                 WHEN 'GR' THEN 'Europe/Athens'
                 ELSE 'Europe/Berlin' END) AS local_ts
```

The other eight countries all use Central European Time, which `Europe/Berlin` covers, including the switch to summer time.

Parquet stores data column by column instead of row by row. A query that needs 2 of the 8 columns reads only those 2 from disk. Values in one column are similar (the `country` column is the same 10 strings over and over), so they compress well. `parquet.compression=SNAPPY` turns on compression; Hive writes Parquet uncompressed unless told.

Size of the same 1,480,855 rows in HDFS (`results/hive/format_sizes.md`), and the same query on each table (`results/hive/format_query_time.md`: average solar per country):

| Table | Format | Size on HDFS | vs CSV | Query time | HDFS bytes read by the query |
|---|---|---|---|---|---|
| `energy_raw_ext` | CSV text | 52,895,430 bytes (52.9 MB) | 1× | 39 s | 52,914,772 |
| `energy_parquet` | Parquet, Snappy | 8,314,526 bytes (8.3 MB) | 6.4× smaller | 37 s | 6,669,456 |
| `energy_by_year` | ORC, ZLIB | 5,557,070 bytes (5.6 MB) | 9.5× smaller | 38 s | 5,150,739 |

The Parquet copy is 6.4 times smaller although it has 4 more columns than the CSV. The query on CSV read the whole file (52.9 MB). The same query on Parquet read 6.7 MB, and on ORC 5.2 MB, because it only needs the `country`, `metric` and `value` columns.

The query time hardly changes (37 to 39 seconds), because on one laptop most of the time is Hive compiling the query and YARN starting containers, not reading 50 MB. With data a thousand times larger, reading 8 times less would decide the time.

### Partitioned ORC table

```sql
CREATE TABLE energy_by_year (...) PARTITIONED BY (year INT) STORED AS ORC;
INSERT OVERWRITE TABLE energy_by_year PARTITION (year)
SELECT ts, country, metric, value, mon, local_ts, yr AS year FROM energy_parquet;
```

The partition column is not stored inside the files. Each year becomes a folder: `energy_by_year/year=2015/`, `year=2016/` and so on. `SHOW PARTITIONS energy_by_year` lists 6 partitions.

This is dynamic partitioning: `PARTITION (year)` without a value tells Hive to take the year from the last column of the SELECT and create the folders itself. It needs `hive.exec.dynamic.partition.mode=nonstrict` (set in `hive-site.xml`). The alternative, static partitioning, would need one INSERT per year with `PARTITION (year=2019)`.

Partition pruning: a query with `WHERE year = 2019` reads only the `year=2019` folder. `EXPLAIN DEPENDENCY` shows it:

```text
{"input_tables":[{"tablename":"energy@energy_by_year", ...}],
 "input_partitions":[{"partitionName":"energy@energy_by_year@year=2019"}]}
```

Only one of the six partitions is listed.

### The hourly wide table

`energy_hourly` has one row per country and hour, with load, solar and wind as three columns. It is made with a pivot:

```sql
SELECT country, ts,
       MAX(CASE WHEN metric = 'load'  THEN value END) AS load_mw,
       MAX(CASE WHEN metric = 'solar' THEN value END) AS solar_mw,
       MAX(CASE WHEN metric = 'wind'  THEN value END) AS wind_mw
FROM energy_parquet GROUP BY country, ts;
```

Correlation (question 5) and hour-to-hour changes (question 4) both need the values of the same hour side by side, which the long format does not give.

## The analysis queries

All in `hive/02_analysis.sql`. Each writes its result to `/energy/output/hive/<name>/` with `INSERT OVERWRITE DIRECTORY ... ROW FORMAT DELIMITED FIELDS TERMINATED BY ','`, and `export_results.sh` copies them to `results/hive/<name>.csv`.

### Q1: join with GROUP BY, and RANK

The rules ask for a join with GROUP BY and aggregation. Question 1 needs exactly that:

```sql
SELECT ..., RANK() OVER (PARTITION BY year ORDER BY share DESC) AS rank_in_year
FROM (
  SELECT g.country, g.year, (g.avg_solar + g.avg_wind) / l.avg_load AS share ...
  FROM (SELECT country, year,
               AVG(CASE WHEN metric = 'solar' THEN value END) AS avg_solar,
               AVG(CASE WHEN metric = 'wind'  THEN value END) AS avg_wind
        FROM energy_by_year WHERE metric IN ('solar','wind')
        GROUP BY country, year) g
  JOIN (SELECT country, year, AVG(value) AS avg_load
        FROM energy_by_year WHERE metric = 'load'
        GROUP BY country, year) l
  ON g.country = l.country AND g.year = l.year
) s
```

Two grouped subqueries (generation and load per country-year), joined on country and year. The share uses averages per metric, the same formula as MapReduce Job B (see `docs/03-mapreduce.md` for why). `RANK()` is a window function: it numbers the countries inside each year by share, without collapsing the rows the way GROUP BY would.

`share_monthly` is the same join per month. We used it to check MapReduce Job B: for all 678 country-months, Hive's share and Job B's share are identical to 4 decimals. The yearly average load also matches Job A (difference at most 0.05 MW, from Hive rounding to 1 decimal).

### Q4: LAG

```sql
LAG(load_mw) OVER (PARTITION BY country ORDER BY ts) AS prev_load_mw
```

For each row, LAG gives the value from the row before it, inside the same country, in time order. `load_mw - prev_load_mw` is then the change from the previous hour. Where the data has a gap, the "row before" can be days earlier, so we also take `LAG(ts)` and keep a change only if the two timestamps are exactly 3600 seconds apart.

The result is stored as the table `load_changes`, and two queries read it: the 20 biggest rises and drops in MW, and the average change in percent for each country and local hour. Percent, because a 1,000 MW jump is normal for Germany and huge for Denmark.

### Q5: corr()

`corr(solar_mw, load_mw)` is Hive's built-in Pearson correlation, computed per country over every hour that has both values.

## Results

All files are in `results/hive/`. The charts in `charts/` are drawn from them, and [docs/09-findings.md](09-findings.md) explains what they mean. A few direct results:

Renewable share by year (`share_yearly.csv`), in percent, with Hive's rank in that year:

| Country | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 (Jan-Sep) |
|---|---|---|---|---|---|---|
| DK | 43.4 (1) | 39.1 (1) | 46.7 (1) | 44.4 (1) | 50.4 (1) | 53.6 (1) |
| DE | 23.4 (4) | 22.8 (4) | 28.2 (2) | 30.0 (2) | 33.8 (2) | 38.6 (2) |
| PT | 24.7 (2) | 26.3 (2) | 25.8 (3) | 25.9 (3) | 28.8 (3) | 25.4 (4) |
| ES | 24.4 (3) | 23.9 (3) | 23.8 (4) | 23.9 (4) | 26.7 (4) | 29.9 (3) |
| GR | 14.0 | 14.5 | 15.3 | 16.2 | 18.2 | 23.0 |
| AT | 9.6 | 10.0 | 12.4 | 12.3 | 14.8 | 14.9 |
| BE | 9.4 | 9.0 | 9.9 | 11.8 (7) | 14.4 | 19.9 |
| IT | no data | 12.3 | 12.8 | 11.8 (7) | 13.3 | 15.5 |
| FR | 5.7 | 5.8 | 6.7 | 7.8 | 9.4 | 11.8 |
| CZ | 4.5 | 4.0 | 4.1 | 4.4 | 4.4 | 5.2 |

In 2018 Belgium and Italy both have a share of 0.1182 to 4 decimals, so RANK() gives both of them 7 and the next country (France) gets 9. ROW_NUMBER() would have given 7 and 8 and picked the order at random.

Top hourly load changes (`top_load_changes.csv`): 19 of the 20 biggest rises are in Germany and 18 of them happen into 06:00 local time. 16 of the 20 are on a Monday, when industry starts up again after the weekend, for example +10,539 MW (+21.5%) into 2019-11-18 06:00. The biggest drops are spread over the evening and night.

Correlation of hourly solar and load (`correlation.csv`): from 0.36 (Greece) down to -0.03 (France). In summer alone (`correlation_season.csv`) it is 0.43 to 0.64 in every country.

## hive-site.xml, the parts that matter

| Setting | Value | Why |
|---|---|---|
| `javax.jdo.option.ConnectionURL` | `jdbc:derby:;databaseName=<project>/.hive/metastore_db;create=true` | metastore in an embedded Derby database inside the project folder |
| `javax.jdo.option.ConnectionDriverName` | `org.apache.derby.iapi.jdbc.AutoloadedDriver` | Derby 10.17 moved the usual `EmbeddedDriver` class into a jar Hive does not ship |
| `hive.metastore.warehouse.dir` | `/energy/warehouse` | managed tables go into our HDFS folder from Step 2 |
| `hive.execution.engine` | `mr` | run on MapReduce; Tez is not installed. Hive prints a warning that MR is deprecated. |
| `hive.exec.dynamic.partition.mode` | `nonstrict` | allow dynamic partitioning |
| `metastore.metadata.transformer.class` | blank | keep managed tables managed (see above) |

`setup/setup-hive.sh` writes the real `hive-site.xml` from the template, because the metastore path has to be absolute and is different on every laptop.

## Problems we hit

1. Managed tables became external (Hive 4 behaviour), described above.
2. Map tasks failed with `ClassNotFoundException: org.apache.commons.collections.CollectionUtils`. Same cause as in Pig: Hadoop 3.4 has no commons-collections 3. `HIVE_AUX_JARS_PATH` and `hive.aux.jars.path` did not get the jar to the tasks in embedded beeline mode. `ADD JAR` in `hive/init.sql` did.
3. beeline would not start ("Unable to create a terminal") on Apple Silicon. Fixed in `env.sh`, see `docs/00-setup.md`.
4. beeline's `-i` option takes several files, so `-i init.sql --silent=true` treated `--silent=true` as a file name. `run_hive.sh` puts `-i` last.
5. The first Q1 join failed with `return code 1 from org.apache.hadoop.hive.ql.exec.mr.MapredLocalTask`. Hive had turned the join into a map join: it starts a separate local Java process to load the smaller side into a hash table, then sends that table to every map task, so the join needs no reducer. That child process did not get our `env.sh` fixes and exited with status 1. We set `hive.auto.convert.join=false` in `hive/init.sql`, so Hive does a common (reduce-side) join: both sides are shuffled by the join key and matched in the reducer, just like a GROUP BY.

## Screenshots to take

Save them in `screenshots/06-hive/`.

1. `SHOW TABLES;` in the interactive prompt
2. `DESCRIBE FORMATTED energy_raw_ext;` showing EXTERNAL_TABLE, and the same for `energy_parquet` showing MANAGED_TABLE
3. `SHOW PARTITIONS energy_by_year;` and `hdfs dfs -ls /energy/warehouse/energy.db/energy_by_year`
4. `EXPLAIN DEPENDENCY SELECT COUNT(*) FROM energy_by_year WHERE year = 2019;`
5. `results/hive/format_sizes.md` (CSV vs Parquet vs ORC) and `format_query_time.md`
6. The Q1 query running, with its MapReduce stages, and its result
7. The LAG query result (`top_load_changes.csv`) and `correlation.csv`

## Viva questions for this step

What is the difference between an external and a managed table? What happens on DROP?
For an external table Hive stores only the definition and the location. DROP removes the definition; the files stay. For a managed table Hive owns the files in its warehouse folder, and DROP deletes them too.

What is the metastore?
A small database (Derby, here) with the table names, columns, types, file formats, locations and partitions. Hive asks it how to read the files. The data itself is in HDFS.

Why is Parquet faster and smaller than CSV?
It stores each column together, so a query reads only the columns it uses, and similar values in a column compress well. It also stores min and max values per block, so some blocks can be skipped. CSV must be read in full and every number parsed from text.

What is a partition, and what is partition pruning?
A partition is a sub-folder per value of the partition column, like `year=2019`. When a query filters on that column, Hive reads only the matching folders. That is pruning.

Static vs dynamic partitioning?
Static: you name the partition in the INSERT, `PARTITION (year=2019)`, one INSERT per value. Dynamic: `PARTITION (year)`, and Hive takes the value from the data and creates each folder.

What is a map join, and why did you turn it off?
In a map join the smaller table is loaded into memory on every map task, so rows are matched in the mappers and no shuffle is needed. It is faster when one side is small. Hive builds that in-memory table in a separate local process first, and on our setup that process crashed. With `hive.auto.convert.join=false`, Hive uses a reduce-side join: both tables are sent through the shuffle by join key and matched in the reducer.

What does LAG do?
It returns the value of a column from the previous row in a window. `PARTITION BY country` keeps countries apart, `ORDER BY ts` defines "previous". LEAD gives the next row.

What is the difference between RANK and ROW_NUMBER?
On a tie, RANK gives both rows the same number and skips the next (1, 1, 3). ROW_NUMBER always counts 1, 2, 3.

Why is the hour converted to local time?
People follow the clock on the wall. In UTC, Greece's evening peak would look two hours earlier than it is.
