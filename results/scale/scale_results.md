# Scale test results

## Data sets

| data | HDFS path | size (bytes) | blocks |
|---|---|---|---|
| sample | /energy/long/sample | 9,368,464 | 1 |
| full | /energy/long/full | 52,895,430 | 1 |
| full_32mb | /energy/long/full_32mb | 52,895,430 | 2 |
| full_x5 | /energy/long/full_x5 | 264,477,150 | 2 |

## Runs

| tool | job | data | seconds | MR jobs | map tasks | reduce tasks | map input records | map output records | combine in | combine out | reduce input records | shuffle bytes | HDFS bytes read |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MapReduce | avgload | sample | 22.6 |  | 1 | 3 | 262,011 | 87,593 | 87,593 | 10 | 10 | 278 | 9,368,587 |
| MapReduce | share | sample | 24.7 |  | 1 | 3 | 262,011 | 262,011 | 262,011 | 120 | 120 | 7,338 | 9,368,587 |
| MapReduce | avgload | full | 23.3 |  | 1 | 3 | 1,480,855 | 494,920 | 494,920 | 59 | 59 | 1,552 | 52,895,549 |
| MapReduce | share | full | 25.4 |  | 1 | 3 | 1,480,855 | 1,480,855 | 1,480,855 | 688 | 688 | 41,986 | 52,895,549 |
| MapReduce | avgload | full_32mb | 28.4 |  | 2 | 3 | 1,480,855 | 494,920 | 494,920 | 69 | 69 | 1,830 | 52,899,774 |
| MapReduce | share | full_32mb | 26.7 |  | 2 | 3 | 1,480,855 | 1,480,855 | 1,480,855 | 688 | 688 | 42,004 | 52,899,774 |
| MapReduce | avgload | full_x5 | 28.6 |  | 2 | 3 | 7,404,275 | 2,474,600 | 2,474,600 | 118 | 118 | 3,104 | 264,481,496 |
| MapReduce | share | full_x5 | 36.6 |  | 2 | 3 | 7,404,275 | 7,404,275 | 7,407,734 | 4,815 | 1,356 | 82,752 | 264,481,496 |
| Pig | peak_and_daily.pig | sample | 312.5 | 13 |  |  | 262,011 |  |  |  |  |  | 9,368,849 |
| Pig | peak_and_daily.pig | full | 307.6 | 13 |  |  | 1,480,855 |  |  |  |  |  | 52,895,811 |
| Hive | hive_avg_load | sample | 45.0 | 1 | 1 | 1 |  |  |  |  |  |  | 9,388,982 |
| Hive | hive_share_join | sample | 107.5 | 3 | 4 | 3 |  |  |  |  |  |  | 18,796,112 |
| Hive | hive_avg_load | full | 36.7 | 1 | 1 | 1 |  |  |  |  |  |  | 52,915,894 |
| Hive | hive_share_join | full | 97.9 | 3 | 4 | 3 |  |  |  |  |  |  | 105,853,539 |
| Hive | hive_avg_load | full_x5 | 48.4 | 1 | 1 | 2 |  |  |  |  |  |  | 264,512,935 |
| Hive | hive_share_join | full_x5 | 124.3 | 3 | 4 | 5 |  |  |  |  |  |  | 529,049,211 |
