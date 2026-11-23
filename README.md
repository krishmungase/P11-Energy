# P11: Electricity load and renewable energy in Europe

Big Data Analytics end-semester group project. We take six years of hourly electricity data for 10 European countries and analyse demand, solar and wind with Hadoop tools: HDFS for storage, MapReduce (Java), Pig and Hive for processing, and Python for the charts.

Dataset: Open Power System Data. 2020. Data Package Time series. Version 2020-10-06. https://doi.org/10.25832/time_series/2020-10-06

## Questions

1. Which country has the highest renewable share, and how has it changed over the years?
2. What does the daily load curve look like in summer and in winter?
3. When does wind generation peak, and does that line up with demand?
4. Which hours show the largest changes in load?
5. How strongly is solar generation related to load?

Renewable share = (solar + wind) / load. Answers, with numbers and charts, are in [docs/09-findings.md](docs/09-findings.md).

## Team

| Member | GitHub | Part | Folders | Docs |
|---|---|---|---|---|
| Krishna Mungase | [krishmungase](https://github.com/krishmungase) | Setup, data preparation, HDFS, scale test | `setup/`, `env.sh`, `prep/`, `hdfs/`, `run_all.py` | [00](docs/00-setup.md), [01](docs/01-data.md), [02](docs/02-hdfs.md), [08](docs/08-scale-test.md) |
| Sakshi Deshmukh | [deshmukh-sakshi](https://github.com/deshmukh-sakshi) | MapReduce in Java | `mapreduce/` | [03](docs/03-mapreduce.md) |
| Vaishnavi Bhosale | [Vaishnavi063](https://github.com/Vaishnavi063) | Pig and Hive | `pig/`, `hive/` | [05](docs/05-pig.md), [06](docs/06-hive.md) |
| Snehal Mane | [Sneh913](https://github.com/Sneh913) | Charts, findings, report, slides | `charts/`, `report/`, `slides/` | [07](docs/07-charts.md), [09](docs/09-findings.md) |

## Documentation

Read in this order. Each page says what the step does, how to run it, what we got, what went wrong, which screenshots to take, and the viva questions for that step.

| Step | Page | One line |
|---|---|---|
| 0 | [Setup](docs/00-setup.md) | Hadoop 3.4.2 in pseudo-distributed mode, Pig 0.18.0, Hive 4.2.1, JDK 21 |
| 1 | [Data](docs/01-data.md) | Download, pick 10 countries, wide to long, remove bad values |
| 2 | [HDFS](docs/02-hdfs.md) | Folders, 32 MB block size, fsck, replication 2 on one node |
| 3 | [MapReduce](docs/03-mapreduce.md) | Two Java jobs with combiner, partitioner and counters |
| 5 | [Pig](docs/05-pig.md) | Peak hours and daily generation, 10 Pig operators |
| 4, 6 | [Hive](docs/06-hive.md) | External, managed, partitioned and Parquet/ORC tables; analysis queries |
| 7 | [Charts](docs/07-charts.md) | Charts drawn from Hive and Pig output |
| 8 | [Scale test](docs/08-scale-test.md) | Same jobs on 9 MB, 53 MB and 264 MB |
| | [Findings](docs/09-findings.md) | Answers to the five questions |
| | [Viva notes](docs/10-viva.md) | All likely viva questions in one place |

[PLAN.md](PLAN.md) is the plan we wrote before starting. Where we changed something (countries, formulas), the step's doc says what and why.

## Requirements checklist

| Requirement | Where |
|---|---|
| HDFS: 3+ directories | 6 folders under `/energy`, [docs/02](docs/02-hdfs.md) |
| HDFS: fsck output | `results/hdfs/05_fsck_*.txt` |
| HDFS: replication change | `setrep 2` and back, `results/hdfs/06_*.txt` |
| HDFS: non-default block size | full file uploaded again with 32 MB blocks (2 blocks instead of 1) |
| MapReduce: 2+ jobs in Java | `AvgLoadJob`, `RenewableShareJob` |
| MapReduce: Combiner | `SumCountCombiner`, `SumsCombiner` (shuffle 12.9 MB to 1.5 KB) |
| MapReduce: Partitioner or counters | both: `CountryPartitioner` and `EnergyCounters` |
| Pig: 6+ operators and built-in functions | 10 operators; SUM, MAX, AVG, COUNT, SUBSTRING, ToDate, GetHour |
| Hive: external table | `energy_raw_ext` |
| Hive: managed table | `energy_parquet` |
| Hive: partitioned table | `energy_by_year`, partitioned by year |
| Hive: Parquet or ORC | `energy_parquet` (Parquet), `energy_by_year` (ORC) |
| Hive: join with GROUP BY and aggregation | Q1 in `hive/02_analysis.sql` |
| 3+ charts from Hive or Pig output | 9 charts in `charts/` |
| Scale test with time and counters | `results/scale/scale_results.md` |

## How to run everything

Setup on a new laptop is in [docs/00-setup.md](docs/00-setup.md). After that:

```bash
cd ~/Desktop/BDA/P11-Energy
source env.sh
bash setup/start-hadoop.sh                    # start HDFS + YARN (jps shows 5 daemons)
bash setup/setup-hive.sh                      # first time only

# Step 1: data (not in git, 130 MB download)
mkdir -p data
curl -Lo data/time_series_60min_singleindex.csv \
  https://data.open-power-system-data.org/time_series/2020-10-06/time_series_60min_singleindex.csv
.venv/bin/python prep/reshape.py

bash hdfs/hdfs_commands.sh                    # Step 2
bash mapreduce/run_jobs.sh                    # Step 3
bash pig/run_pig.sh                           # Step 5
bash hive/run_hive.sh hive/01_tables.sql      # Steps 4 + 6
bash hive/run_hive.sh hive/02_analysis.sql
bash hive/export_results.sh
.venv/bin/python charts/make_charts.py        # Step 7
.venv/bin/python run_all.py                   # Step 8

bash setup/stop-hadoop.sh
```

## Folder layout

```text
P11-Energy/
  README.md        this file
  PLAN.md          the original plan
  env.sh           source this first; puts all tools on PATH
  requirements.txt Python packages
  run_all.py       scale test (Step 8)
  docs/            one page per step, plus findings and viva notes
  setup/           Hadoop and Hive config, start/stop scripts
  prep/            reshape.py (wide CSV to long CSV)
  hdfs/            hdfs_commands.sh
  mapreduce/       Java Maven project, run_jobs.sh
  pig/             peak_and_daily.pig, run_pig.sh
  hive/            01_tables.sql, 02_analysis.sql, run and export scripts
  charts/          make_charts.py and the PNG charts
  results/         every output: CSVs, counters, logs, timing tables
  screenshots/     one folder per step (added by each member)
  report/          final report (PDF)
  slides/          P11_Energy_Presentation.pptx (21 slides, speaker notes), the same as PDF, build_slides.js
```

`data/` (the downloaded and reshaped CSVs) is not in git; anyone can rebuild it with the Step 1 commands.
