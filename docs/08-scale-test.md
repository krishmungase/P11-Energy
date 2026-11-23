# Step 8: scale test

Owner: Krish Mungase (krishmungase)

The rules ask us to run the same job on a small sample and on the full data, and record the time and the counters. Script: `run_all.py`. Results: `results/scale/scale_results.md` (table) and `results/scale/logs/` (every run's full log).

## Data sets

| Name | What | Size | HDFS blocks |
|---|---|---|---|
| `sample` | 2019 only | 9.4 MB (262,011 rows) | 1 |
| `full` | 2015 to Sep 2020 | 52.9 MB (1,480,855 rows) | 1 |
| `full_32mb` | the same full file, uploaded with 32 MB blocks (Step 2) | 52.9 MB | 2 |
| `full_x5` | the full file repeated 5 times | 264.5 MB (7,404,275 rows) | 2 |

Why `full_x5`: the plan said to make an enlarged copy if the full data still runs too fast to show a difference. It does. A MapReduce job on our laptop spends most of its ~20 seconds starting the ApplicationMaster and the containers, not reading data, so 9 MB and 53 MB take almost the same time. Five copies of the full file give 264.5 MB, which needs 2 blocks of 128 MB, so the job gets 2 map tasks. (We expected 3 at first. But 264,477,150 bytes is 252 MiB, and two blocks hold 2 × 128 MiB = 256 MiB, so it just fits in 2.)

Because every row appears exactly 5 times, the averages from `full_x5` must equal those from `full`, and the record counts must be exactly 5 times larger. That doubles as a correctness check.

## What runs

| Tool | Job | On |
|---|---|---|
| MapReduce | Job A `avgload`, Job B `share` (combiner on, 3 reducers) | sample, full, full_32mb, full_x5 |
| Pig | `pig/peak_and_daily.pig` | sample, full |
| Hive | `hive_avg_load`: GROUP BY on the CSV external table | sample, full, full_x5 |
| Hive | `hive_share_join`: the Q1 join (two GROUP BYs and a JOIN) on the CSV table | sample, full, full_x5 |

Pig runs only on sample and full, because each Pig run is about 5 minutes (13 jobs) and the point is already made by MapReduce and Hive.

## Running it

```bash
.venv/bin/python run_all.py              # about 25 minutes
.venv/bin/python run_all.py --skip-pig   # about 15 minutes
```

The first run creates `/energy/long/full_x5` in HDFS (streamed straight from 5 copies of the local file, without writing a 264 MB file to the laptop disk) and a Hive external table `energy_raw_ext_x5` on it.

## Results

From `results/scale/scale_results.md`.

### MapReduce

| Job | Data | Seconds | Map tasks | Map input records | Map output records | Combine in | Combine out | Reduce input | Shuffle bytes |
|---|---|---|---|---|---|---|---|---|---|
| A avgload | sample | 22.6 | 1 | 262,011 | 87,593 | 87,593 | 10 | 10 | 278 |
| A avgload | full | 23.3 | 1 | 1,480,855 | 494,920 | 494,920 | 59 | 59 | 1,552 |
| A avgload | full_32mb | 28.4 | 2 | 1,480,855 | 494,920 | 494,920 | 69 | 69 | 1,830 |
| A avgload | full_x5 | 28.6 | 2 | 7,404,275 | 2,474,600 | 2,474,600 | 118 | 118 | 3,104 |
| B share | sample | 24.7 | 1 | 262,011 | 262,011 | 262,011 | 120 | 120 | 7,338 |
| B share | full | 25.4 | 1 | 1,480,855 | 1,480,855 | 1,480,855 | 688 | 688 | 41,986 |
| B share | full_32mb | 26.7 | 2 | 1,480,855 | 1,480,855 | 1,480,855 | 688 | 688 | 42,004 |
| B share | full_x5 | 36.6 | 2 | 7,404,275 | 7,404,275 | 7,407,734 | 4,815 | 1,356 | 82,752 |

All runs used 3 reducers.

### Pig and Hive

| Tool | Job | Data | Seconds | MapReduce jobs | Map tasks (total) | HDFS bytes read |
|---|---|---|---|---|---|---|
| Pig | peak_and_daily.pig | sample | 312.5 | 13 | | 9,368,849 |
| Pig | peak_and_daily.pig | full | 307.6 | 13 | | 52,895,811 |
| Hive | avg load (GROUP BY) | sample | 45.0 | 1 | 1 | 9,388,982 |
| Hive | avg load (GROUP BY) | full | 36.7 | 1 | 1 | 52,915,894 |
| Hive | avg load (GROUP BY) | full_x5 | 48.4 | 1 | 1 | 264,512,935 |
| Hive | share (JOIN) | sample | 107.5 | 3 | 4 | 18,796,112 |
| Hive | share (JOIN) | full | 97.9 | 3 | 4 | 105,853,539 |
| Hive | share (JOIN) | full_x5 | 124.3 | 3 | 4 | 529,049,211 |

### What the numbers show

Time barely follows data size. Going from the sample to the full data is 5.7 times more records, and Job A took 23.3 seconds instead of 22.6 (+3%). Going to x5, 28 times the sample, took 28.6 seconds (+27%). Pig took about 5 minutes on both sample and full. The fixed cost of starting a YARN job (around 20 seconds on this laptop) is far bigger than the time spent reading 50 MB. In the Hive and Pig runs the sample was even a few seconds slower than the full data; at this size the run-to-run noise is larger than the effect of the data.

The counters do follow data size exactly. Map input records are 262,011, then 1,480,855, then 7,404,275 (exactly 5 × 1,480,855). The x5 run gives the same 59 averages as the full run, with every hour count exactly 5 times larger, which also confirms the job is correct.

The combiner keeps the shuffle small at every size. Job A's shuffle grew from 278 bytes to 3,104 bytes while the input grew 28 times, because after combining there is only one record per key per map task: 10 keys for the sample, 59 for full, 59 × 2 = 118 for x5 with 2 map tasks.

More map tasks did not help here. The 32 MB-block copy gave 2 map tasks and was slower than the 1-task run (28.4 vs 23.3 seconds), because both tasks run on the same laptop and the second container costs start-up time. With 2 map tasks Job A's combine output also went up from 59 to 69 records, because each map task combines only its own data: a country-year whose rows are split across both blocks is sent once from each task.

In the x5 run of Job B the combiner ran more than once per record. Combine input (7,407,734) is larger than map output (7,404,275). The map output was 437 MB in total (`Map output bytes`), about 218 MB per task, while the in-memory sort buffer is 100 MB by default (`mapreduce.task.io.sort.mb`). So each task spilled to disk several times, and when Hadoop merges the spill files it runs the combiner again on records that were already combined. This is the clearest example in our runs of "the combiner can run 0, 1 or many times".

Hive's join query reads the table twice. Its HDFS bytes read is twice the file size (105.9 MB for the 52.9 MB file), because the generation subquery and the load subquery each scan the whole table. It also runs 3 MapReduce jobs (one per side, one for the join), and so takes about 100 seconds where the single-job GROUP BY takes about 40.

## Screenshots to take

Save them in `screenshots/08-scale/`.

1. `hdfs fsck /energy/long/full_x5 -files -blocks` showing 2 blocks
2. The terminal while `run_all.py` runs (it prints one line per job)
3. `results/scale/scale_results.md`
4. ResourceManager page (http://localhost:8088) during the x5 run, showing 2 map tasks

## Viva questions for this step

Why did the full run take much less than 5.7 times the sample time, with 5.7 times more data?
A job has a fixed start-up cost (YARN starts an ApplicationMaster container, then map and reduce containers, each a new Java process). On this laptop that is around 20 seconds, while reading and processing 50 MB takes only a few seconds. So the time is mostly fixed cost, and the part that grows with data is small.

What changed when you used 32 MB blocks?
The job got 2 map tasks instead of 1, because one split is made per block. On one laptop that does not make it faster: the two tasks share the same CPU and disk, and the extra container costs start-up time. On a cluster the two tasks would run on two machines in parallel.

Why did the x5 run get only 2 map tasks?
The file is 264,477,150 bytes, which is 252 MiB. Two 128 MiB blocks hold 256 MiB, so it fits in 2 blocks, and there is one split per block. In "MB" it looks like more than 256, but HDFS counts in MiB (1 MiB = 1,048,576 bytes).

Why does Hive take longer than the Java job for the same question?
Each Hive query is compiled into one or more MapReduce jobs, plus the time to compile the query and talk to the metastore. The join query needs 3 jobs (one per GROUP BY side, one for the join and window), so it pays the start-up cost three times.

Is this a fair test of Hadoop's speed?
Not really. Hadoop is built for data much larger than one machine's memory, spread over many machines. On a laptop with 264 MB, a single Python script would be faster. The test shows how the work is split (map tasks per block, shuffle sizes, record counts grow linearly) rather than raw speed.
