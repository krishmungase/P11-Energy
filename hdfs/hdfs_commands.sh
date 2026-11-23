#!/bin/bash
# Step 2: HDFS. Creates the folders, uploads the data, and shows block size, fsck and replication.
# Take a screenshot of the terminal after each section (the "=====" headers make it easy).
# Every output is also saved in results/hdfs/ so it can be pasted into the report.
#
# Run from the project folder, with Hadoop already started (setup/start-hadoop.sh):
#   bash hdfs/hdfs_commands.sh

source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"
OUT=results/hdfs
mkdir -p "$OUT"

section() { echo; echo "===== $1 ====="; }

section "1. Running Hadoop daemons (jps)"
jps | tee "$OUT/01_jps.txt"

section "2. Make directories"
# -p creates parent folders too and does not fail if the folder already exists
hdfs dfs -mkdir -p /energy/raw /energy/long/sample /energy/long/full /energy/long/full_32mb \
                   /energy/output /energy/warehouse
hdfs dfs -ls -R /energy | tee "$OUT/02_dirs.txt"

section "3. Upload files (default 128 MB block size)"
# -f overwrites if the file is already there, so the script can be run again
hdfs dfs -put -f data/time_series_60min_singleindex.csv /energy/raw/
hdfs dfs -put -f data/energy_sample.csv /energy/long/sample/
hdfs dfs -put -f data/energy_full.csv   /energy/long/full/
hdfs dfs -ls -R /energy/raw /energy/long | tee "$OUT/03_put.txt"

section "4. Upload the full file again with a 32 MB block size"
# 33554432 bytes = 32 * 1024 * 1024. -D only changes the setting for this one command.
hdfs dfs -D dfs.blocksize=33554432 -put -f data/energy_full.csv /energy/long/full_32mb/
# %o = block size, %r = replication, %b = file size in bytes, %n = name
hdfs dfs -stat "blocksize=%o replication=%r bytes=%b name=%n" \
  /energy/long/full/energy_full.csv /energy/long/full_32mb/energy_full.csv \
  /energy/raw/time_series_60min_singleindex.csv | tee "$OUT/04_blocksize.txt"

section "5. fsck: blocks of the 128 MB copy vs the 32 MB copy"
hdfs fsck /energy/long/full -files -blocks -locations 2>/dev/null | tee "$OUT/05_fsck_128mb.txt"
hdfs fsck /energy/long/full_32mb -files -blocks -locations 2>/dev/null | tee "$OUT/05_fsck_32mb.txt"
hdfs fsck /energy 2>/dev/null | tee "$OUT/05_fsck_all.txt"

section "6. Change replication of the sample file from 1 to 2"
# No -w here. -w waits until the 2nd copy exists, and with one DataNode it never will,
# so the command would hang forever.
hdfs dfs -setrep 2 /energy/long/sample/energy_sample.csv | tee "$OUT/06_setrep.txt"
hdfs dfs -stat "replication=%r name=%n" /energy/long/sample/energy_sample.csv | tee -a "$OUT/06_setrep.txt"
# fsck now reports the file as under-replicated: it wants 2 copies but only 1 DataNode exists
hdfs fsck /energy/long/sample -files -blocks -locations 2>/dev/null | tee "$OUT/06_fsck_after_setrep.txt"

section "7. Set it back to 1 so fsck is healthy again"
hdfs dfs -setrep 1 /energy/long/sample/energy_sample.csv
hdfs fsck /energy/long/sample 2>/dev/null | grep -E "Status|Under-replicated" | tee "$OUT/07_fsck_restored.txt"

section "8. Disk usage"
hdfs dfs -du -h /energy | tee "$OUT/08_du.txt"
hdfs dfsadmin -report 2>/dev/null | head -20 | tee "$OUT/08_report.txt"
