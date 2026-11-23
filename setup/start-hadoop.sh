#!/bin/bash
# Starts all Hadoop daemons on this laptop (pseudo-distributed mode).
# We use "--daemon start" instead of start-dfs.sh because start-dfs.sh needs
# ssh to localhost, and Remote Login is off on our Macs.
set -e
source "$(dirname "$0")/../env.sh"

# First run only: format the NameNode (creates an empty HDFS)
if [ ! -d "$P11_HDFS_DATA/dfs/name" ]; then
  echo ">> First run: formatting NameNode"
  hdfs namenode -format -nonInteractive
fi

hdfs --daemon start namenode
hdfs --daemon start datanode
yarn --daemon start resourcemanager
yarn --daemon start nodemanager
mapred --daemon start historyserver

sleep 5
hdfs dfsadmin -safemode wait
jps
echo
echo "NameNode UI:        http://localhost:9870"
echo "ResourceManager UI: http://localhost:8088"
echo "Job history UI:     http://localhost:19888"
