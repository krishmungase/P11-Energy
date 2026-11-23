# Viva preparation

The viva can ask any member about any part. Each step's page ends with questions about that step. This page has the general questions that cut across steps, and a short list of the numbers worth remembering. Answers are short on purpose: say them in your own words.

## Numbers to remember

| What | Number |
|---|---|
| Raw file | 130 MB, 50,401 hourly rows, 300 columns, 2015 to Sep 2020 |
| Long file | 1,480,855 rows, 52.9 MB (sample, 2019 only: 262,011 rows, 9.4 MB) |
| Countries | DE, FR, ES, IT, GR, BE, AT, DK, CZ, PT (PL and NL swapped out for bad data) |
| Bad values removed | 70 (10 spikes, 60 load dips; e.g. France 158,000 MW for one hour, highest real hour 94,492) |
| HDFS | 1 block at 128 MB, 2 blocks at 32 MB; replication 2 gives "under-replicated" on one node |
| Combiner effect (Job A) | reducer input 494,920 to 59 records; shuffle 12.9 MB to 1.5 KB |
| Pig | 10 operators, 13 MapReduce jobs, about 5 minutes |
| Hive | 6 year partitions; CSV 52.9 MB, Parquet 8.3 MB, ORC 5.6 MB; Hive and MapReduce monthly shares identical |

Answers (details in [09-findings.md](09-findings.md)):

| Question | Short answer |
|---|---|
| 1. Highest share | Denmark every year, 43% (2015) to 50% (2019). Germany grew most, 23% to 34%. Czechia lowest, about 4%. |
| 2. Load curve | Winter: two peaks, late morning and early evening (17:00 to 20:00). Summer: one midday peak. France uses 34% less in summer (electric heating); Spain, Italy, Greece about the same (air conditioning). |
| 3. Wind vs demand | By season they match: wind strongest in winter like demand (monthly correlation 0.87 to 0.96 in BE, CZ, DE, DK, FR). Within a day they do not: wind weakest in the morning, strongest at night. Greece is the exception, with summer winds. |
| 4. Largest changes | The morning ramp into 06:00 to 08:00 (up to +14% on average in Italy and Denmark). 16 of the 20 largest rises are German Monday mornings. Drops are late evening. |
| 5. Solar vs load | Weak: r = 0.12 to 0.36, France -0.03. In summer alone 0.43 to 0.64. |

## Big picture

What is Hadoop?
A framework for storing and processing data that is too big for one machine. HDFS stores files split into blocks across many machines; YARN hands out CPU and memory; MapReduce is the programming model that runs on YARN. Pig and Hive are higher-level tools that generate MapReduce jobs.

Why use Hadoop for 130 MB, which fits in Excel?
The project is about learning the tools. The same scripts would run unchanged on 130 GB across 100 machines. The scale test (docs/08) shows how time grows with data size.

What is the flow of a MapReduce job?
Input files are cut into splits (one per block by default). One map task per split reads records and emits key-value pairs. The optional combiner shrinks map output locally. The partitioner decides which reducer gets each key. Shuffle and sort move the data and group it by key. Each reducer gets one key with all its values and writes output. Output is one `part-r-NNNNN` file per reducer.

What is the difference between Hadoop 1 and Hadoop 2/3?
Hadoop 1 had a JobTracker that both scheduled jobs and managed resources, and could run only MapReduce. Hadoop 2 split this into YARN (ResourceManager, NodeManagers) so other engines (Tez, Spark) can share the cluster.

What is data locality?
Moving the computation to the data instead of the data to the computation. YARN tries to run a map task on the DataNode that holds its block. The job counter "Data-local map tasks" shows how often this worked.

What happens if a DataNode dies?
The NameNode stops receiving its heartbeats (every 3 seconds) and after about 10 minutes marks it dead. Blocks that now have fewer copies than the replication factor are copied again from the remaining copies. With replication 1, as on our laptop, those blocks would be lost.

What happens if the NameNode dies?
The cluster stops: nobody knows which blocks form which file. Production clusters run a standby NameNode (high availability). The "Secondary NameNode" is not a backup; it only merges the edit log into the file system image.

What is a split vs a block?
A block is how HDFS stores the file (physical). A split is how MapReduce divides the input for map tasks (logical). By default one split equals one block, but a record that crosses a block boundary is read whole by the split where it starts.

## Comparing the tools

When would you use MapReduce, Pig or Hive?
MapReduce in Java gives full control (our custom partitioner, Writables, counters) but needs much code. Pig suits step-by-step data flows and cleaning. Hive suits people who know SQL and questions that are naturally queries (joins, group by, window functions). All three ran on the same YARN cluster and the same HDFS files.

Did the tools agree?
Yes. Hive's average load per country-year equals MapReduce Job A (for example Germany 2019: 55,990.26 MW in both). Hive's monthly share equals Job B. Both also match a pandas calculation on the same file.

Why are Pig and Hive slower than our Java jobs for similar work?
They run several MapReduce jobs per script or query (Pig: 13 for our script), and each job costs about 15 to 20 seconds of YARN start-up on a laptop. Our Java jobs are one job each.

## Our choices

Why did you remove some countries?
We checked data coverage before starting. Poland's solar was 92% empty; the Netherlands' 2019 solar averaged 1 MW. A share built on that would be wrong. We swapped in Czech Republic and Greece, which have complete data.

Why average-based renewable share instead of totals?
Belgium is missing some wind hours each month but no load hours. Totals would treat missing wind as zero. Averaging each metric over the hours it has avoids that. With no gaps both formulas give the same answer.

Why local time in Hive?
Daily habits follow the local clock. In UTC, the Greek evening peak would appear two hours early.

What would you do with more time?
Use the ENTSO-E data for 2021 onwards to see the effect of the 2022 energy crisis; add electricity prices (also in the OPSD file) to see how prices move with wind and solar; run on a real multi-node cluster so replication and data locality can be shown properly.
