-- Runs at the start of every Hive session (hive/run_hive.sh passes it with -i).
-- Hive's map tasks need commons-collections 3 inside the YARN containers, and Hadoop 3.4
-- does not ship it. ADD JAR sends the jar along with every job in this session.
-- (HIVE_AUX_JARS_PATH and hive.aux.jars.path did not work in embedded beeline; we tried.)
ADD JAR ${env:HIVE_HOME}/lib/commons-collections-3.2.2.jar;

-- Joins: Hive normally turns a join with a small table into a "map join". For that it first
-- starts a separate local Java process (MapredLocalTask) to build a hash table of the small
-- table. That child process does not get our env.sh fixes and fails with exit status 1.
-- With this off, Hive does a normal reduce-side join: both tables are shuffled by the join
-- key and matched in the reducer. Slower for tiny tables, but it works and is easy to explain.
SET hive.auto.convert.join=false;
