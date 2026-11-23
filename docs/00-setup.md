# Step 0: setup

Owner: Krish Mungase (krishmungase)

This page explains what we installed, how the pieces fit together, and how to start and stop everything. Read it before any other step, because every later command assumes Hadoop is running and `env.sh` has been sourced.

## What runs where

We run Hadoop in pseudo-distributed mode. Every Hadoop service (HDFS and YARN) runs as a separate Java process, but all of them run on one laptop. This is different from local mode (used in CE-03), where a MapReduce job runs inside a single Java process and reads the normal disk instead of HDFS.

| Process | Part of | What it does | Web page |
|---|---|---|---|
| NameNode | HDFS | Keeps the list of files and which blocks belong to each file. Holds no data itself. | http://localhost:9870 |
| DataNode | HDFS | Stores the actual blocks on disk | (shown in the NameNode page) |
| ResourceManager | YARN | Decides which job gets memory and CPU | http://localhost:8088 |
| NodeManager | YARN | Starts the containers (Java processes) that run map and reduce tasks | |
| JobHistoryServer | MapReduce | Keeps the logs and counters of finished jobs | http://localhost:19888 |

Pig and Hive are not services. They are client programs: they turn a Pig script or a SQL query into MapReduce jobs and send those jobs to YARN.

## Versions

| Tool | Version | Where it lives |
|---|---|---|
| macOS on Apple Silicon (arm64) | 27.0.1 | |
| Java (OpenJDK, Microsoft build) | 21.0.8 | `/usr/libexec/java_home -v 21` |
| Apache Hadoop | 3.4.2 | `~/Desktop/BDA/tools/hadoop-3.4.2` |
| Apache Pig | 0.18.0 | `~/Desktop/BDA/tools/pig-0.18.0` |
| Apache Hive | 4.2.1 | `~/Desktop/BDA/tools/apache-hive-4.2.1-bin` |
| Maven (builds the Java MapReduce jar) | 3.9.9 | system |
| Python | 3.14 | `.venv/` inside the project |
| pandas / matplotlib / pyarrow | 3.1.1 / 3.11.2 / 26.0.1 | `.venv/` |

Nothing is installed system-wide. The Apache tools are plain tarballs unpacked into `~/Desktop/BDA/tools`, and `env.sh` puts them on the PATH.

Why these versions: Hadoop 3.4.2 was already set up for CE-03. Pig 0.18.0 is the first Pig release built for Hadoop 3. Hive 4.2.1 is the current Hive release and needs Java 17 or newer, so JDK 21 works for all three tools.

## Folder layout

```
~/Desktop/BDA/
  tools/                      Hadoop, Pig, Hive (not in git)
  P11-Energy/                 this repository
    env.sh                    source this in every new terminal
    setup/
      hadoop-conf/            our Hadoop config (pseudo-distributed)
      hive-site.xml.template  our Hive config (template)
      start-hadoop.sh         starts all 5 daemons
      stop-hadoop.sh          stops them
      setup-hive.sh           one-time Hive setup
    .hdfs-data/               where HDFS stores its blocks on the laptop disk (not in git)
    .hive/                    Hive metastore database (not in git)
    .logs/                    Hadoop, Pig and Hive logs (not in git)
    .venv/                    Python packages (not in git)
```

## Installing on another laptop

These steps are for macOS. Linux is the same apart from the Java path. On Windows, use WSL (Ubuntu) and follow the Linux route.

1. Install JDK 21 (any build, for example Microsoft OpenJDK or Temurin) and Maven.
2. Download and unpack the three tools next to the project:

   ```bash
   mkdir -p ~/Desktop/BDA/tools && cd ~/Desktop/BDA/tools
   curl -LO https://archive.apache.org/dist/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz
   curl -LO https://dlcdn.apache.org/pig/pig-0.18.0/pig-0.18.0.tar.gz
   curl -LO https://dlcdn.apache.org/hive/hive-4.2.1/apache-hive-4.2.1-bin.tar.gz
   for f in *.tar.gz; do tar xzf "$f"; done
   ```

   The project must sit at `~/Desktop/BDA/P11-Energy` (next to `tools/`), because `env.sh` looks for `../tools`.
3. Create the Python environment:

   ```bash
   cd ~/Desktop/BDA/P11-Energy
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   ```

4. Start Hadoop and set up Hive once:

   ```bash
   bash setup/start-hadoop.sh     # the first run also formats the NameNode
   bash setup/setup-hive.sh
   ```

## Everyday use

```bash
cd ~/Desktop/BDA/P11-Energy
source env.sh                 # every new terminal; puts hadoop, hdfs, pig, beeline on PATH
bash setup/start-hadoop.sh    # once after a reboot
jps                           # should list the 5 daemons above
...work...
bash setup/stop-hadoop.sh     # before shutting the laptop down
```

`jps` lists running Java processes. If one of the five is missing, look at its log in `.logs/hadoop/`, for example `.logs/hadoop/hadoop-krishna-datanode-*.log`.

## Our config, line by line

The default config inside `tools/hadoop-3.4.2/etc/hadoop` is empty, which means local mode. We did not edit it. We keep our own copy in `setup/hadoop-conf/`, and `env.sh` points Hadoop to it with `HADOOP_CONF_DIR`. That way the old CE-03 project still runs in local mode.

`core-site.xml`
- `fs.defaultFS = hdfs://localhost:9000`: paths like `/energy/raw` now mean HDFS, not the laptop disk.
- `hadoop.tmp.dir = ${env.P11_HDFS_DATA}`: HDFS keeps its files in `.hdfs-data/` inside the project. The default is `/tmp`, which macOS clears on reboot, and then HDFS loses everything.
- `hadoop.proxyuser.*`: lets Hive run jobs on our behalf.

`hdfs-site.xml`
- `dfs.replication = 1`: there is only one DataNode, so only one copy of each block can exist. The default of 3 would leave every block "under-replicated".
- `dfs.blocksize = 134217728` (128 MB): the normal default, written out so it is easy to see. Step 2 uploads one file with 32 MB blocks to show the difference.
- `dfs.permissions.enabled = false`: no permission errors between Hive, Pig and our user.

`mapred-site.xml`
- `mapreduce.framework.name = yarn`: jobs go to YARN instead of running in local mode.
- `mapreduce.application.classpath` and the three `*.env` settings: tell the task containers where Hadoop's MapReduce jars are. Without these, tasks fail with "Could not find or load main class MRAppMaster".
- Memory per container is 1024 MB, so several tasks fit on an 8 GB laptop.

`yarn-site.xml`
- `yarn.nodemanager.aux-services = mapreduce_shuffle`: turns on the shuffle service that moves map output to reducers.
- `yarn.nodemanager.resource.memory-mb = 4096`: YARN may use 4 GB of the laptop's 8 GB.
- `disk-health-checker...max-disk-utilization-per-disk-percentage = 98`: our disk is about 93% full. By default YARN marks the node "unhealthy" above 90% and then runs no jobs at all.
- `vmem-check-enabled = false`: stops YARN from killing Java tasks over virtual memory, which Java on macOS over-reports.

`hive-site.xml.template` is explained in the Hive doc (Step 6). `setup/setup-hive.sh` copies it to `setup/hive-conf/hive-site.xml` and fills in the project path.

## Problems we hit and how we fixed them

These go into the report's "problems" section.

1. `start-dfs.sh` failed with "ssh: connect to host localhost port 22: Connection refused". The start scripts log in to every worker over SSH, even when the worker is the same laptop, and Remote Login is off on our Macs. Fix: `setup/start-hadoop.sh` starts each daemon directly with `hdfs --daemon start namenode` and so on, which needs no SSH.
2. YARN's disk check. The laptop disk is about 93% full, and YARN refuses to run containers on a disk above 90%. We raised the limit to 98%.
3. Pig and Hive jobs failed with `ClassNotFoundException: org.apache.commons.collections...`. Hadoop 3.4 ships only commons-collections 4, while Pig 0.18 and Hive 4.2.1 still use version 3 in some places. The job's driver found the class but the map tasks inside YARN did not. Fix: for Pig, `PIG_CLASSPATH` plus `-Dpig.additional.jars` in `env.sh`. For Hive, an `ADD JAR` in `hive/init.sql` (we tried `HIVE_AUX_JARS_PATH` and `hive.aux.jars.path` first; neither reached the tasks in embedded beeline mode).
4. Hive's schematool said "Failed to load driver org.apache.derby.jdbc.EmbeddedDriver". Derby 10.17, which comes with Hive 4.2.1, moved that class into a jar Hive does not include. Fix: use `org.apache.derby.iapi.jdbc.AutoloadedDriver`, which is in `derby.jar`.
5. Hive's schematool did not understand `${env:P11_ROOT}` in the metastore path. Fix: keep a template and let `setup-hive.sh` write the real path.
6. `beeline` crashed with "Unable to create a terminal". Its terminal library loaded Hadoop's old JNA 5.2 jar, which has no Apple Silicon code. Fix: `-Dorg.jline.terminal.type=dumb -Dorg.jline.terminal.providers=exec,dumb` in `HADOOP_CLIENT_OPTS`.
7. Hive 4 removed the old `hive` command line. We use `beeline -u jdbc:hive2://`, which starts Hive inside the beeline process (embedded mode), so no separate HiveServer2 is needed. `hive/run_hive.sh` wraps this.

## Screenshots to take

Save them in `screenshots/00-setup/`.

1. `java -version` and `hadoop version` in the terminal
2. Output of `bash setup/start-hadoop.sh` with `jps` showing all 5 daemons
3. NameNode web page (http://localhost:9870), Overview tab, showing 1 live DataNode
4. ResourceManager web page (http://localhost:8088), Nodes page, showing 1 healthy node
5. `pig -version` and `beeline -u jdbc:hive2:// -e "show databases;"`

## Viva questions for this step

What is pseudo-distributed mode, and how is it different from local mode?
All Hadoop daemons run as separate processes on one machine and talk over network ports, so the setup behaves like a real cluster with one node. In local mode there are no daemons: a job runs in one Java process and reads the normal file system.

What do the NameNode and the DataNode do?
The NameNode stores metadata: file names, folders, and which blocks make up each file and where they are. The DataNode stores the blocks. If the NameNode is lost, the blocks are still on disk but nobody knows which file they belong to.

What do the ResourceManager and the NodeManager do?
The ResourceManager is YARN's master. It hands out containers (memory plus CPU) to jobs. Each NodeManager runs on a worker machine, starts the containers, and reports back. Here we have one of each.

Why is replication set to 1?
Replication means how many DataNodes hold a copy of each block. We have one DataNode, so a second copy has nowhere to go.

Why did you not use start-dfs.sh?
It uses SSH to start daemons on every worker, and SSH to localhost is off on our Macs. `hdfs --daemon start` starts the same daemons without SSH.

Where is the HDFS data physically stored?
In `.hdfs-data/dfs/data/` on the laptop disk, as `blk_...` files. HDFS is a layer over normal disks; it splits files into blocks and tracks them.
