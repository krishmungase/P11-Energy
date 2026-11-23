# Usage:  source env.sh
# Puts hadoop, hdfs, yarn, mapred, pig, hive and beeline on PATH for this project.
# Nothing is installed system-wide. All tools live in ~/Desktop/BDA/tools.

P11_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOLS="$(cd "$P11_ROOT/../tools" && pwd)"
export P11_ROOT

# Hadoop 3.4.2 and Hive 4.2.1 both run on JDK 21
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"

export HADOOP_HOME="$TOOLS/hadoop-3.4.2"
# Our own config (pseudo-distributed). The default config in $HADOOP_HOME is left alone,
# so the older CE-03 project still runs in local mode.
export HADOOP_CONF_DIR="$P11_ROOT/setup/hadoop-conf"
export P11_HDFS_DATA="$P11_ROOT/.hdfs-data"     # NameNode + DataNode files on local disk
export HADOOP_LOG_DIR="$P11_ROOT/.logs/hadoop"
export HADOOP_PID_DIR="$P11_ROOT/.logs/pids"

export PIG_HOME="$TOOLS/pig-0.18.0"
# Pig 0.18 needs commons-collections 3. Hadoop 3.4 only ships commons-collections4, so
# without this jar Pig fails with "ClassNotFoundException ... CircularFifoBuffer".
# It is needed in two places: on our side (PIG_CLASSPATH) and inside the YARN task
# containers (pig.additional.jars ships it with every job).
CC3_JAR="$PIG_HOME/lib/hadoop3-runtime/commons-collections-3.2.2.jar"
export PIG_CLASSPATH="$HADOOP_CONF_DIR:$CC3_JAR"
export PIG_OPTS="-Dpig.additional.jars=$CC3_JAR -Dpig.logfile=$P11_ROOT/.logs/pig/"

export HIVE_HOME="$TOOLS/apache-hive-4.2.1-bin"
export HIVE_CONF_DIR="$P11_ROOT/setup/hive-conf"
# Beeline's terminal library (jline) otherwise picks up Hadoop's old JNA 5.2 jar, which has
# no Apple Silicon (arm64) code, and stops with "Unable to create a terminal".
# derby.stream.error.file keeps Derby's derby.log out of the project root.
export HADOOP_CLIENT_OPTS="-Dorg.jline.terminal.type=dumb -Dorg.jline.terminal.providers=exec,dumb -Dderby.stream.error.file=$P11_ROOT/.logs/hive/derby.log"

mkdir -p "$P11_ROOT/.logs/hadoop" "$P11_ROOT/.logs/pig" "$P11_ROOT/.logs/hive"

export PATH="$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PIG_HOME/bin:$HIVE_HOME/bin:$P11_ROOT/.venv/bin:$PATH"
