-- Step 4 + Step 6 (part 1): Hive tables.
-- Run:  bash hive/run_hive.sh hive/01_tables.sql
--
-- Tables made here:
--   energy_raw_ext         EXTERNAL, CSV text, points at /energy/long/full      (full data)
--   energy_raw_ext_sample  EXTERNAL, CSV text, points at /energy/long/sample    (2019 only, for the scale test)
--   energy_parquet         MANAGED, PARQUET, filled from energy_raw_ext, with extra time columns
--   energy_by_year         MANAGED, ORC, PARTITIONED BY (year), filled with dynamic partitioning
--   energy_hourly          MANAGED, PARQUET, one row per country per hour with load/solar/wind side by side

CREATE DATABASE IF NOT EXISTS energy;
USE energy;

-- ---------------------------------------------------------------------------------
-- 1. External tables.
-- EXTERNAL means Hive only remembers where the files are. DROP TABLE removes the table
-- definition but leaves the CSV files in HDFS. Good for raw data that other tools
-- (MapReduce, Pig) also read.
-- ---------------------------------------------------------------------------------
DROP TABLE IF EXISTS energy_raw_ext;
CREATE EXTERNAL TABLE energy_raw_ext (
    ts      STRING,      -- "2019-01-01 00:00:00", UTC
    country STRING,
    metric  STRING,      -- load / solar / wind
    value   DOUBLE       -- MW
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/energy/long/full';

DROP TABLE IF EXISTS energy_raw_ext_sample;
CREATE EXTERNAL TABLE energy_raw_ext_sample (
    ts STRING, country STRING, metric STRING, value DOUBLE
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/energy/long/sample';

SELECT COUNT(*) AS full_rows FROM energy_raw_ext;
DESCRIBE FORMATTED energy_raw_ext;      -- look for "Table Type: EXTERNAL_TABLE"
SELECT * FROM energy_raw_ext LIMIT 5;


-- ---------------------------------------------------------------------------------
-- 2. Managed Parquet table (CREATE TABLE ... AS SELECT).
-- MANAGED means Hive owns the files (under /energy/warehouse). DROP TABLE deletes them.
-- Note: Hive 4 normally turns non-transactional managed tables into external ones
-- (TRANSLATED_TO_EXTERNAL). hive-site.xml switches that off, so this stays MANAGED_TABLE.
-- Parquet stores data by column and compresses it, so a query that reads 2 of 9 columns
-- only reads those 2 from disk.
--
-- We also add time columns here so later queries do not repeat the same date maths.
-- local_ts: the hour in the country's own time zone. All countries except PT and GR
-- use Central European Time, which Europe/Berlin covers (with summer time).
-- ---------------------------------------------------------------------------------
-- Snappy compression for Parquet files. Hive writes Parquet uncompressed unless told.
-- (ORC tables below are compressed with ZLIB by default.)
SET parquet.compression=SNAPPY;

DROP TABLE IF EXISTS energy_parquet;
CREATE TABLE energy_parquet
STORED AS PARQUET
AS
SELECT
    CAST(ts AS TIMESTAMP)                       AS ts,
    country,
    metric,
    value,
    year(CAST(ts AS TIMESTAMP))                 AS yr,
    month(CAST(ts AS TIMESTAMP))                AS mon,
    hour(CAST(ts AS TIMESTAMP))                 AS utc_hour,
    from_utc_timestamp(CAST(ts AS TIMESTAMP),
        CASE country WHEN 'PT' THEN 'Europe/Lisbon'
                     WHEN 'GR' THEN 'Europe/Athens'
                     ELSE 'Europe/Berlin' END)  AS local_ts
FROM energy_raw_ext;

SELECT COUNT(*) AS parquet_rows FROM energy_parquet;
DESCRIBE FORMATTED energy_parquet;      -- look for "Table Type: MANAGED_TABLE"


-- ---------------------------------------------------------------------------------
-- 3. Partitioned ORC table.
-- PARTITIONED BY (year) makes one HDFS folder per year: .../energy_by_year/year=2019/
-- A query with WHERE year = 2019 then reads only that folder (partition pruning).
-- Dynamic partitioning: Hive reads the year from the last SELECT column and creates the
-- folders itself. hive.exec.dynamic.partition.mode=nonstrict is set in hive-site.xml.
-- ---------------------------------------------------------------------------------
DROP TABLE IF EXISTS energy_by_year;
CREATE TABLE energy_by_year (
    ts        TIMESTAMP,
    country   STRING,
    metric    STRING,
    value     DOUBLE,
    mon       INT,
    local_ts  TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS ORC;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

INSERT OVERWRITE TABLE energy_by_year PARTITION (year)
SELECT ts, country, metric, value, mon, local_ts, yr AS year   -- partition column goes last
FROM energy_parquet;

SHOW PARTITIONS energy_by_year;
DESCRIBE FORMATTED energy_by_year;      -- "Partition Information" lists the year column

-- Partition pruning in action: EXPLAIN shows that only the year=2019 folder is read
EXPLAIN DEPENDENCY
SELECT COUNT(*) FROM energy_by_year WHERE year = 2019;


-- ---------------------------------------------------------------------------------
-- 4. Hourly wide table: one row per country and hour, with load, solar and wind as
-- columns. This is a pivot (GROUP BY + CASE). Needed for corr(solar, load), which must
-- compare the solar and load values of the SAME hour.
-- ---------------------------------------------------------------------------------
DROP TABLE IF EXISTS energy_hourly;
CREATE TABLE energy_hourly
STORED AS PARQUET
AS
SELECT
    country,
    ts,
    MAX(local_ts)                                      AS local_ts,
    MAX(yr)                                            AS yr,
    MAX(mon)                                           AS mon,
    MAX(CASE WHEN metric = 'load'  THEN value END)     AS load_mw,
    MAX(CASE WHEN metric = 'solar' THEN value END)     AS solar_mw,
    MAX(CASE WHEN metric = 'wind'  THEN value END)     AS wind_mw
FROM energy_parquet
GROUP BY country, ts;

SELECT COUNT(*) AS hourly_rows FROM energy_hourly;

SHOW TABLES;
