#!/bin/bash
# Copies every Hive result from /energy/output/hive/ to results/hive/<name>.csv with a header,
# then compares the storage formats (size on HDFS, and time for the same query).
#
#   bash hive/export_results.sh
set -e
source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"
OUT=results/hive
mkdir -p "$OUT"

fetch() {   # fetch <name> <header>
  { echo "$2"; hdfs dfs -cat "/energy/output/hive/$1/*" 2>/dev/null; } > "$OUT/$1.csv"
  echo "   $1.csv: $(($(wc -l < "$OUT/$1.csv") - 1)) rows"
}
echo ">> Exporting Hive results"
fetch share_yearly        "country,year,avg_solar_mw,avg_wind_mw,avg_load_mw,share,rank_in_year"
fetch share_monthly       "country,year,month,share"
fetch load_curve_season   "country,season,local_hour,avg_load_mw"
fetch wind_load_by_month  "country,month_of_year,avg_wind_mw,avg_load_mw"
fetch wind_load_by_hour   "country,local_hour,avg_wind_mw,avg_load_mw"
fetch top_load_changes    "direction,country,local_time,local_hour,prev_load_mw,load_mw,change_mw,change_pct"
fetch load_change_by_hour "country,local_hour,avg_change_pct,avg_abs_change_pct,max_rise_pct,max_drop_pct"
fetch correlation         "country,corr_solar_load,corr_wind_load,hours_used"
fetch correlation_season  "country,season,corr_solar_load,hours_used"
fetch scatter_de_2019     "local_time,solar_mw,load_mw"

echo ">> Storage size of the same data in three formats"
WH=$(hdfs dfs -ls -d /energy/warehouse/energy.db 2>/dev/null | awk '{print $NF}')
{
  echo "| table | format | HDFS path | size (bytes) |"
  echo "|---|---|---|---|"
  for row in "energy_raw_ext|CSV text|/energy/long/full" \
             "energy_parquet|Parquet|$WH/energy_parquet" \
             "energy_by_year|ORC, partitioned by year|$WH/energy_by_year"; do
    IFS='|' read -r T F P <<< "$row"
    S=$(hdfs dfs -du -s "$P" 2>/dev/null | awk '{print $1}')
    echo "| $T | $F | $P | $S |"
  done
} > "$OUT/format_sizes.md"
cat "$OUT/format_sizes.md"
hdfs dfs -ls -R "$WH/energy_by_year" 2>/dev/null | grep "year=" | grep "^d" > "$OUT/partition_folders.txt" || true

format_of() {
  if [ "$1" = energy_raw_ext ]; then echo CSV
  elif [ "$1" = energy_parquet ]; then echo Parquet
  else echo ORC; fi
}

echo ">> Same query on CSV, Parquet and ORC (average solar per country)"
{
  echo "| table | format | seconds | HDFS bytes read |"
  echo "|---|---|---|---|"
  for T in energy_raw_ext energy_parquet energy_by_year; do
    START=$(date +%s)
    LOG=$(beeline -u jdbc:hive2:// --silent=true -i hive/init.sql \
      -e "USE energy; SELECT country, AVG(value) FROM $T WHERE metric='solar' GROUP BY country;" 2>&1)
    END=$(date +%s)
    # Hive prints "Stage-Stage-1: Map: 1  Reduce: 1   HDFS Read: 52897589 ..." at the end
    READ=$(echo "$LOG" | grep -oE "HDFS Read: [0-9]+" | head -1 | grep -oE "[0-9]+")
    echo "| $T | $(format_of "$T") | $((END - START)) | $READ |"
  done
} > "$OUT/format_query_time.md"
cat "$OUT/format_query_time.md"
