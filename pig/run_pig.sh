#!/bin/bash
# Step 5: runs pig/peak_and_daily.pig on YARN and copies every output to results/pig/<data>/
#
#   bash pig/run_pig.sh            # full data   -> /energy/output/pig/full
#   bash pig/run_pig.sh sample     # 2019 only   -> /energy/output/pig/sample
#
# Pig's STORE writes files without a header, so we add one here for the charts.
set -e
source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"

DATA="${1:-full}"
OUT_HDFS="/energy/output/pig/$DATA"
OUT_LOCAL="results/pig/$DATA"
mkdir -p "$OUT_LOCAL"

echo ">> Running Pig on /energy/long/$DATA (log: $OUT_LOCAL/pig_log.txt)"
START=$(date +%s)
pig -x mapreduce -param INPUT="/energy/long/$DATA" -param OUTPUT="$OUT_HDFS" \
    pig/peak_and_daily.pig > "$OUT_LOCAL/pig_log.txt" 2>&1
END=$(date +%s)
echo "Wall clock seconds: $((END - START))" | tee -a "$OUT_LOCAL/pig_log.txt"

fetch() {   # fetch <output folder> <header>
  { echo "$2"; hdfs dfs -cat "$OUT_HDFS/$1/part-*" 2>/dev/null; } > "$OUT_LOCAL/$1.csv"
  echo "   $1.csv: $(($(wc -l < "$OUT_LOCAL/$1.csv") - 1)) rows"
}
fetch countries        "country"
fetch peak_hour        "country,ts_utc,peak_load_mw"
fetch hourly_profile   "country,utc_hour,avg_load_mw"
fetch peak_hour_of_day "country,utc_hour,avg_load_mw"
fetch daily            "country,day,solar_mwh,wind_mwh,load_mwh,share,load_hours"
fetch top_wind_days    "country,day,solar_mwh,wind_mwh,load_mwh,share,load_hours"

# The "Job Stats" table Pig prints at the end lists every MapReduce job it ran
sed -n '/^Job Stats/,/^Input(s)/p' "$OUT_LOCAL/pig_log.txt" > "$OUT_LOCAL/job_stats.txt"
echo ">> Pig ran $(grep -c '^job_' "$OUT_LOCAL/job_stats.txt") MapReduce jobs"
