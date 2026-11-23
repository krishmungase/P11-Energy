#!/bin/bash
# Step 3: builds the jar and runs both MapReduce jobs on YARN, with and without the combiner.
#
#   bash mapreduce/run_jobs.sh                 # full data  (/energy/long/full)
#   bash mapreduce/run_jobs.sh sample          # 2019 only  (/energy/long/sample)
#
# For each run it saves:
#   results/mr/logs/<run>.txt     the full Hadoop job log, with all counters
#   results/mr/<run>.csv          the job output, all part-r-* files merged, with a header
#   results/mr/counters_<data>.md a table of the counters that matter for the report
set -e
source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"

DATA="${1:-full}"
INPUT="/energy/long/$DATA"
OUT_HDFS="/energy/output/mr"
OUT_LOCAL="results/mr"
mkdir -p "$OUT_LOCAL/logs"

echo ">> Building the jar"
(cd mapreduce && mvn -q package)
JAR=mapreduce/target/p11-energy-mr.jar

# name           job      combiner  csv header
RUNS=(
  "avgload_${DATA}_combiner   avgload true  country,year,avg_load_mw,hours"
  "avgload_${DATA}_nocombiner avgload false country,year,avg_load_mw,hours"
  "share_${DATA}_combiner     share   true  country,month,solar_mwh,wind_mwh,load_mwh,share,solar_hours,wind_hours,load_hours"
  "share_${DATA}_nocombiner   share   false country,month,solar_mwh,wind_mwh,load_mwh,share,solar_hours,wind_hours,load_hours"
)

for r in "${RUNS[@]}"; do
  read -r NAME JOB COMB HEADER <<< "$r"
  echo ">> $NAME  (job=$JOB, combiner=$COMB, 3 reducers)"
  hdfs dfs -rm -r -f -skipTrash "$OUT_HDFS/$NAME" > /dev/null 2>&1
  START=$(date +%s)
  hadoop jar "$JAR" "$JOB" -D p11.combiner="$COMB" -D p11.reducers=3 \
      "$INPUT" "$OUT_HDFS/$NAME" > "$OUT_LOCAL/logs/$NAME.txt" 2>&1
  END=$(date +%s)
  echo "Wall clock seconds: $((END - START))" >> "$OUT_LOCAL/logs/$NAME.txt"
  # getmerge joins part-r-00000, -00001, -00002 into one local file
  { echo "$HEADER"; hdfs dfs -cat "$OUT_HDFS/$NAME/part-r-*" 2>/dev/null | sort; } > "$OUT_LOCAL/$NAME.csv"
  echo "   done in $((END - START)) s, $(($(wc -l < "$OUT_LOCAL/$NAME.csv") - 1)) output lines"
done

# Pull the interesting counters out of each log into one markdown table
COUNTERS=("Launched map tasks" "Launched reduce tasks" "Map input records" "Map output records"
          "Combine input records" "Combine output records" "Reduce input records"
          "Reduce shuffle bytes" "Reduce output records" "BAD_LINES" "LOAD_RECORDS"
          "SOLAR_RECORDS" "WIND_RECORDS" "SKIPPED_OTHER_METRIC" "Wall clock seconds")
TABLE="$OUT_LOCAL/counters_${DATA}.md"
{
  echo "# MapReduce counters ($DATA data, input $INPUT)"
  echo
  printf "| counter |"; for r in "${RUNS[@]}"; do printf " %s |" "$(echo $r | cut -d' ' -f1)"; done; echo
  printf "|---|"; for r in "${RUNS[@]}"; do printf -- "---|"; done; echo
  for c in "${COUNTERS[@]}"; do
    printf "| %s |" "$c"
    for r in "${RUNS[@]}"; do
      NAME=$(echo $r | cut -d' ' -f1)
      V=$(grep -E "^\s*$c[=:]" "$OUT_LOCAL/logs/$NAME.txt" | head -1 | sed -E 's/.*[=:] ?//')
      printf " %s |" "${V:--}"
    done
    echo
  done
} > "$TABLE"
echo ">> Counters table: $TABLE"
cat "$TABLE"

# Proof that the CountryPartitioner works: which countries ended up in which reducer's file
PARTS="$OUT_LOCAL/partitions_${DATA}.txt"
: > "$PARTS"
for JOBNAME in "avgload_${DATA}_combiner" "share_${DATA}_combiner"; do
  for p in 0 1 2; do
    F="$OUT_HDFS/$JOBNAME/part-r-0000$p"
    echo "$JOBNAME part-r-0000$p: $(hdfs dfs -cat "$F" 2>/dev/null | cut -d, -f1 | sort -u | tr '\n' ' ')" >> "$PARTS"
  done
done
echo ">> Partitions: $PARTS"
cat "$PARTS"
