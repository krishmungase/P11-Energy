# Step 3: MapReduce in Java

Owner: Sakshi Deshmukh (deshmukh-sakshi)

Two MapReduce jobs written in Java, as the rules require for CE groups. Both read the long CSV from HDFS. Together they use a Combiner, a custom Partitioner and custom counters.

| Job | Question it helps answer | Key | Output |
|---|---|---|---|
| A: `avgload` | Average load per country per year | `DE,2019` | `DE,2019,55990.26,8760` |
| B: `share` | Renewable share per country per month (question 1) | `DE,2019-01` | `DE,2019-01,745020.0,14695533.0,45828272.0,0.3369,744,744,744` |

## Files

All Java code is in `mapreduce/src/main/java/p11/`.

| File | What it is |
|---|---|
| `Main.java` | Entry point. The first argument picks the job: `avgload` or `share`. |
| `EnergyRecord.java` | Splits one CSV line into timestamp, country, metric, value. Returns null for a bad line. Both jobs use it, so the "valid line" rule is in one place. |
| `AvgLoadJob.java` | Job A: mapper, combiner, reducer and the job setup |
| `RenewableShareJob.java` | Job B: mapper, combiner, reducer and the job setup |
| `SumCountWritable.java` | Value type for Job A: a (sum, count) pair |
| `EnergySumsWritable.java` | Value type for Job B: solar, wind and load sums plus an hour count for each |
| `CountryPartitioner.java` | Sends all keys of one country to the same reducer |
| `EnergyCounters.java` | Our custom counters |
| `pom.xml` | Maven build file. Hadoop is a `provided` dependency: it is already on the cluster, so it is not packed into our jar. |
| `run_jobs.sh` | Builds the jar and runs both jobs with and without the combiner, then writes the counter table |
| `testdata/bad_lines.csv` | 8 hand-written lines, 4 of them broken, to show the BAD_LINES counter |

## Job A: average load per country per year

```text
input line    2019-01-01 00:00:00,DE,load,43120.50
                     |
mapper        keeps only metric = load
              emits  key "DE,2019"  value (sum=43120.50, count=1)
                     |
combiner      on the map side, adds pairs with the same key
              ("DE,2019", (1.0e8, 2000)) + ("DE,2019", (0.9e8, 1800)) -> ("DE,2019", (1.9e8, 3800))
              does NOT divide
                     |
partitioner   picks the reducer from the country only ("DE")
                     |
shuffle/sort  all values for "DE,2019" reach one reducer
                     |
reducer       adds all sums and counts, divides once
              writes  DE,2019,55990.26,8760
```

### Why the combiner must not divide

A combiner is a mini-reducer that runs on the map side before the shuffle. It cuts the amount of data sent over the network. Hadoop may run it 0, 1 or many times, so the final answer must be the same no matter how often it runs.

Averages break this rule. Suppose one map task sees the load values 1, 2, 3 and another sees 5. If each combiner sent an average, the reducer would get 2 and 5 and answer 3.5. The correct average of 1, 2, 3, 5 is 2.75. Sums and counts do not have this problem: (6, 3) + (5, 1) = (11, 4), and 11 / 4 = 2.75. So the mapper and combiner pass (sum, count) pairs, and only the reducer divides. This is the same lesson as CE-03.

The combiner's input and output types must also match the mapper's output types (`Text`, `SumCountWritable`), because Hadoop may feed combiner output into the combiner again.

## Job B: renewable share per country per month

The mapper puts each reading into the right slot of an `EnergySumsWritable`: a solar reading of 120 MW becomes solar=120, wind=0, load=0, solarHours=1. The combiner adds all six numbers (three sums, three hour counts) slot by slot. The reducer then computes

```text
share = (average solar MW + average wind MW) / average load MW
```

where each average is that metric's sum divided by its own hour count.

### Why averages and not plain totals

The simple formula would be (solar MWh + wind MWh) / load MWh. That is wrong when one metric has missing hours and another does not. Belgium's wind data has gaps in 5 to 25% of hours every month (see `docs/01-data.md`), while its load is complete. In July 2019 Belgium has 649 wind hours but 744 load hours. With totals, the 95 missing wind hours count as zero wind, and the share comes out at 12.8%. With averages, each metric is judged only on the hours it has, and the share is 13.6%.

When no hours are missing, both formulas give exactly the same number, because all three averages divide by the same hour count.

The output also includes the three hour counts, so anyone reading it can see which months have gaps.

## The Partitioner

By default Hadoop uses `HashPartitioner`, which hashes the whole key. `DE,2019` and `DE,2020` would then likely go to different reducers, and Germany's rows would be spread over several output files.

`CountryPartitioner` hashes only the part before the comma:

```java
String country = key.substring(0, key.indexOf(','));
return (country.hashCode() & Integer.MAX_VALUE) % numReducers;
```

`& Integer.MAX_VALUE` clears the sign bit. `hashCode()` can be negative, and a negative partition number would crash the job.

We run with 3 reducers. With 1 reducer every key goes to partition 0 anyway, so the partitioner would have no visible effect.

Which reducer each country gets (worked out by hand, and it matches the output files):

| Country | `hashCode()` | % 3 | Output file |
|---|---|---|---|
| BE | 2115 | 0 | part-r-00000 |
| GR | 2283 | 0 | part-r-00000 |
| CZ | 2167 | 1 | part-r-00001 |
| IT | 2347 | 1 | part-r-00001 |
| AT | 2099 | 2 | part-r-00002 |
| DE | 2177 | 2 | part-r-00002 |
| DK | 2183 | 2 | part-r-00002 |
| ES | 2222 | 2 | part-r-00002 |
| FR | 2252 | 2 | part-r-00002 |
| PT | 2564 | 2 | part-r-00002 |

For a two-letter string, `hashCode()` is first letter × 31 + second letter. For "AT": 65 × 31 + 84 = 2099, and 2099 % 3 = 2.

The split is uneven (2, 2 and 6 countries) because 10 keys are too few for a hash to spread evenly. With thousands of keys it evens out. Uneven partitions are called skew; one reducer then does most of the work. Here the data is small enough that it does not matter. Both jobs give the same mapping (`results/mr/partitions_full.txt`).

## Counters

Counters are numbers that every task can add to; Hadoop adds them up across all tasks and prints the totals at the end of the job. We use them to check the data without writing extra code.

| Counter | Meaning |
|---|---|
| `BAD_LINES` | line could not be parsed: wrong number of fields, value not a number, or a negative value |
| `LOAD_RECORDS`, `SOLAR_RECORDS`, `WIND_RECORDS` | valid readings of each metric |
| `SKIPPED_OTHER_METRIC` | valid line that this job does not need (Job A skips solar and wind) |

Hadoop prints a counter only if its value is above 0. Our cleaned data has no bad lines, so BAD_LINES does not appear in the real runs. To show that it works, we ran Job A on `testdata/bad_lines.csv`:

```text
2019-01-01 00:00:00,DE,load,40000.00       good
2019-01-01 01:00:00,DE,load,42000.00       good
2019-01-01 00:00:00,DE,solar,0.00          good, but skipped by Job A
2019-01-01 00:00:00,FR,load,not_a_number   bad: value is text
this line is broken                        bad: 1 field
2019-01-01 02:00:00,DE,load                bad: 3 fields
2019-01-01 03:00:00,DE,load,-5.00          bad: negative
2019-01-01 00:00:00,FR,load,60000.00       good
```

Result (`results/mr/logs/badlines_demo.txt`): BAD_LINES=4, LOAD_RECORDS=3, SKIPPED_OTHER_METRIC=1, and the output `DE,2019,41000.00,2` and `FR,2019,60000.00,1`.

## How to run

Hadoop must be running and the data must be in HDFS (Steps 0 to 2).

```bash
cd ~/Desktop/BDA/P11-Energy
bash mapreduce/run_jobs.sh          # full data, about 2 minutes for all 4 runs
bash mapreduce/run_jobs.sh sample   # 2019 only
```

To run one job by hand:

```bash
source env.sh
cd mapreduce && mvn -q package && cd ..
hadoop jar mapreduce/target/p11-energy-mr.jar avgload /energy/long/full /energy/output/mr/my_run
hdfs dfs -cat /energy/output/mr/my_run/part-r-*
```

Options go right after the job name:

- `-D p11.reducers=3` sets the number of reducers (default 3). We use our own setting name because Hadoop's `mapreduce.job.reduces` already has a default of 1, so our code could not tell whether the user had set it. Our first version read `mapreduce.job.reduces` with a fallback of 3 and always got 1 reducer. The counters showed "Launched reduce tasks=1", which is how we found the bug.
- `-D p11.combiner=false` turns the combiner off.

The output folder must not exist yet. Hadoop refuses to overwrite it, so that a finished result is never lost by accident. `run_jobs.sh` deletes it first.

## Results on the full data

From `results/mr/counters_full.md`:

| Counter | A, combiner | A, no combiner | B, combiner | B, no combiner |
|---|---|---|---|---|
| Launched map tasks | 1 | 1 | 1 | 1 |
| Launched reduce tasks | 3 | 3 | 3 | 3 |
| Map input records | 1,480,915 | 1,480,915 | 1,480,915 | 1,480,915 |
| Map output records | 494,980 | 494,980 | 1,480,915 | 1,480,915 |
| Combine input records | 494,980 | 0 | 1,480,915 | 0 |
| Combine output records | 59 | 0 | 688 | 0 |
| Reduce input records | 59 | 494,980 | 688 | 1,480,915 |
| Reduce shuffle bytes | 1,552 | 12,869,706 | 41,986 | 90,336,443 |
| Reduce output records | 59 | 59 | 678 | 678 |
| Wall clock (s) | 21 | 22 | 24 | 24 |

What the numbers say:

- The combiner cut Job A's shuffle from 12.9 MB to 1.5 KB, and the records reaching the reducers from 494,980 to 59. For Job B, from 90.3 MB to 42 KB.
- The time saved is small (0 to 1 seconds), because everything runs on one laptop and the "network" is the local disk. Most of the 20 seconds is YARN starting containers. On a real cluster, sending 90 MB instead of 42 KB between machines would matter much more.
- 59 output rows = 10 countries × 6 years, minus Italy 2015. 678 = 10 countries × 69 months (Jan 2015 to Sep 2020), minus Italy's 12 months of 2015.
- 1 map task, because `energy_full.csv` is 52.9 MB and fits in one 128 MB block. The scale test (Step 8) also runs on the 32 MB-block copy, which gives 2 map tasks.
- Job B's combiner produced 688 records although there are only 678 keys. The mapper's output buffer filled up and was written to disk (spilled) more than once, and the combiner runs on each spill separately. A month whose records were split across two spills therefore comes out of the combiner twice. The reducer adds them, so the answer is still right. This is a real example of "the combiner may run more than once".

### Checks

- Job A output matches a pandas calculation on the same file to within 0.005 MW (the output is rounded to 2 decimals). The hour counts match exactly.
- Job B shares match pandas to within 0.00005 (4 decimals in the output).
- Hive's `AVG(value)` for 2019 gives the same averages as Job A (for example DE 55,990.3, FR 53,383.2).
- Combiner on and off give identical Job A output. Job B differs in one value: Denmark's May 2019 solar total is 136,375.9 MWh with the combiner and 136,375.8 without it. Computers add `double` numbers with tiny rounding errors, and the result depends on the order of the additions. The combiner changes that order. The share is the same to 4 decimals.

Sample of Job A output (`results/mr/avgload_full_combiner.csv`):

| Country | Year | Avg load (MW) | Hours |
|---|---|---|---|
| DE | 2015 | 54,736.99 | 8,760 |
| DE | 2016 | 55,441.19 | 8,784 |
| DE | 2017 | 56,177.68 | 8,760 |
| DE | 2018 | 56,951.51 | 8,760 |
| DE | 2019 | 55,990.26 | 8,760 |
| DE | 2020 | 53,047.85 | 6,576 |

2016 has 8,784 hours because it is a leap year. 2020 stops at the end of September. The drop in 2020 is partly the COVID lockdowns in spring.

## Screenshots to take

Save them in `screenshots/03-mapreduce/`.

1. `mvn package` finishing, and `ls -l mapreduce/target/p11-energy-mr.jar`
2. The end of a job run in the terminal, showing the Map-Reduce Framework counters and the `p11.EnergyCounters` group
3. ResourceManager page (http://localhost:8088) with the finished jobs listed
4. Job history page (http://localhost:19888) for one job, Counters tab
5. `hdfs dfs -ls /energy/output/mr/avgload_full_combiner` showing 3 part files, and `hdfs dfs -cat` of each one showing whole countries per file
6. The BAD_LINES demo counters
7. `results/mr/counters_full.md` (combiner vs no combiner)

## Viva questions for this step

What does the mapper do in Job A?
It reads one line, checks that it is valid, keeps it only if the metric is load, and emits the key "country,year" with the value (load, 1).

What is a combiner and when is it safe to use?
A reducer that runs on the map side before the shuffle, to shrink the data sent to reducers. It is safe when the operation gives the same result no matter how the values are grouped and in what order: sum, count, max and min are safe; average and median are not. Its input and output types must equal the map output types.

Why can't the combiner compute the average?
An average of averages is wrong when groups have different sizes. avg(1, 2, 3) = 2, avg(5) = 5, and avg(2, 5) = 3.5, but the real average is 2.75. So we pass sums and counts and divide only once, in the reducer.

How much did the combiner help?
Job A: reducer input fell from 494,980 records to 59, and shuffle bytes from 12.9 MB to 1.5 KB. Job B: 1,480,915 to 688 records, 90.3 MB to 42 KB.

Why are there 688 combine output records but only 678 keys?
The map output was spilled to disk more than once, and the combiner runs once per spill. A key split across two spills comes out twice. The reducer adds both, so the result is still correct.

What does your partitioner do, and what happens with 1 reducer?
It sends all keys of one country to the same reducer, by hashing only the country. With 1 reducer every key goes to reducer 0 regardless, so it changes nothing.

Why is the partition split 2, 2 and 6?
Only 10 different countries get hashed, so the hash cannot spread them evenly. That is called partition skew.

Why is there only 1 map task?
One map task per input split, and one split per HDFS block by default. The 52.9 MB file is a single 128 MB block.

What are counters used for?
To count events across all tasks, like bad lines or records per metric, without writing extra output. Hadoop adds them up from all tasks and shows the totals in the job log and the web UI.

Why is Hadoop "provided" in pom.xml?
The cluster already has the Hadoop jars, so we compile against them but do not pack them into our jar. Our jar is 19 KB.

Why did you write your own Writable classes?
Hadoop sends values between machines in its own binary format. A custom class must say how to write its fields (`write`) and read them back in the same order (`readFields`). We need a pair (sum, count) and a group of six numbers, which no built-in type provides.
