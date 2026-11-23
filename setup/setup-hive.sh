#!/bin/bash
# One-time Hive setup. Run after setup/start-hadoop.sh.
#  1. writes setup/hive-conf/hive-site.xml from the template (puts in this laptop's path)
#  2. creates the Derby metastore (the database of table definitions)
#  3. creates the HDFS folders Hive needs
set -e
source "$(dirname "$0")/../env.sh"
cd "$P11_ROOT"

mkdir -p setup/hive-conf .hive .logs/hive
sed "s#@P11_ROOT@#$P11_ROOT#g" setup/hive-site.xml.template > setup/hive-conf/hive-site.xml
echo ">> wrote setup/hive-conf/hive-site.xml"

hdfs dfs -mkdir -p /tmp/hive /energy/warehouse
hdfs dfs -chmod -R 777 /tmp/hive

if [ -d .hive/metastore_db ]; then
  echo ">> metastore already exists (.hive/metastore_db), skipping schematool"
else
  schematool -dbType derby -initSchema
fi
echo ">> Hive ready. Try:  beeline -u jdbc:hive2:// -e 'show databases;'"
