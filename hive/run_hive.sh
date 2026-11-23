#!/bin/bash
# Runs a Hive script with beeline in embedded mode (no HiveServer2 needed).
#   bash hive/run_hive.sh hive/01_tables.sql
#   bash hive/run_hive.sh hive/02_analysis.sql
#   bash hive/run_hive.sh                       # interactive prompt
# Extra beeline options can go after the file, e.g. --hivevar SRC=energy_raw_ext_sample
source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"
if [ $# -eq 0 ]; then
  exec beeline -u jdbc:hive2:// -i hive/init.sql
fi
FILE="$1"; shift
exec beeline -u jdbc:hive2:// --silent=true --showHeader=true \
  --hiveconf hive.server2.logging.operation.level=NONE "$@" -i hive/init.sql -f "$FILE"
