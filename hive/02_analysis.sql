-- Step 6 (part 2): Hive queries that answer the five project questions.
-- Run after 01_tables.sql:   bash hive/run_hive.sh hive/02_analysis.sql
--
-- Every query writes its result as CSV into /energy/output/hive/<name>/ with
-- INSERT OVERWRITE DIRECTORY. hive/export_results.sh copies them to results/hive/ with
-- a header line, and the charts are drawn from those files.
--
-- Hours: "local hour" means the country's own clock time (local_ts from 01_tables.sql).
-- Daily habits follow the clock on the wall, not UTC.

USE energy;


-- =================================================================================
-- Q1. Which country has the highest renewable share, and how did it change by year?
--
-- This is the required "join with GROUP BY and aggregation":
--   g = average solar and wind per country-year   (GROUP BY on the partitioned ORC table)
--   l = average load per country-year             (GROUP BY)
--   JOIN g and l on country and year, then share = (solar + wind) / load
-- RANK() OVER (PARTITION BY year ...) gives 1 to the highest share in each year.
--
-- Same formula as MapReduce Job B: averages per metric, so missing hours of one
-- metric (Belgian wind) do not count as zero.
-- WHERE metric = ... and the year partitions mean Hive reads only what it needs.
-- =================================================================================
INSERT OVERWRITE DIRECTORY '/energy/output/hive/share_yearly'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country, year, avg_solar_mw, avg_wind_mw, avg_load_mw, share,
       RANK() OVER (PARTITION BY year ORDER BY share DESC) AS rank_in_year
FROM (
    SELECT g.country,
           g.year,
           ROUND(g.avg_solar, 1)                                  AS avg_solar_mw,
           ROUND(g.avg_wind, 1)                                   AS avg_wind_mw,
           ROUND(l.avg_load, 1)                                   AS avg_load_mw,
           ROUND((g.avg_solar + g.avg_wind) / l.avg_load, 4)      AS share
    FROM (
        SELECT country, year,
               AVG(CASE WHEN metric = 'solar' THEN value END) AS avg_solar,
               AVG(CASE WHEN metric = 'wind'  THEN value END) AS avg_wind
        FROM energy_by_year
        WHERE metric IN ('solar', 'wind')
        GROUP BY country, year
    ) g
    JOIN (
        SELECT country, year, AVG(value) AS avg_load
        FROM energy_by_year
        WHERE metric = 'load'
        GROUP BY country, year
    ) l
    ON g.country = l.country AND g.year = l.year
) s
ORDER BY year, rank_in_year;

-- Same join per month (used to check MapReduce Job B, which computes the same thing)
INSERT OVERWRITE DIRECTORY '/energy/output/hive/share_monthly'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT g.country, g.year, g.mon,
       ROUND((g.avg_solar + g.avg_wind) / l.avg_load, 4) AS share
FROM (
    SELECT country, year, mon,
           AVG(CASE WHEN metric = 'solar' THEN value END) AS avg_solar,
           AVG(CASE WHEN metric = 'wind'  THEN value END) AS avg_wind
    FROM energy_by_year
    WHERE metric IN ('solar', 'wind')
    GROUP BY country, year, mon
) g
JOIN (
    SELECT country, year, mon, AVG(value) AS avg_load
    FROM energy_by_year
    WHERE metric = 'load'
    GROUP BY country, year, mon
) l
ON g.country = l.country AND g.year = l.year AND g.mon = l.mon
ORDER BY g.country, g.year, g.mon;


-- =================================================================================
-- Q2. What does the daily load curve look like in summer and in winter?
-- Average load for each local hour of the day, summer (Jun-Aug) vs winter (Dec-Feb).
-- =================================================================================
INSERT OVERWRITE DIRECTORY '/energy/output/hive/load_curve_season'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       CASE WHEN month(local_ts) IN (6, 7, 8) THEN 'summer' ELSE 'winter' END AS season,
       hour(local_ts)              AS local_hour,
       ROUND(AVG(load_mw), 1)      AS avg_load_mw
FROM energy_hourly
WHERE load_mw IS NOT NULL
  AND month(local_ts) IN (6, 7, 8, 12, 1, 2)
GROUP BY country,
         CASE WHEN month(local_ts) IN (6, 7, 8) THEN 'summer' ELSE 'winter' END,
         hour(local_ts)
ORDER BY country, season, local_hour;


-- =================================================================================
-- Q3. When does wind generation peak, and does that line up with demand?
-- (a) by month of the year, (b) by local hour of the day.
-- Only hours that have both wind and load are used, so both averages cover the same hours.
-- =================================================================================
INSERT OVERWRITE DIRECTORY '/energy/output/hive/wind_load_by_month'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       month(local_ts)           AS month_of_year,
       ROUND(AVG(wind_mw), 1)    AS avg_wind_mw,
       ROUND(AVG(load_mw), 1)    AS avg_load_mw
FROM energy_hourly
WHERE wind_mw IS NOT NULL AND load_mw IS NOT NULL
GROUP BY country, month(local_ts)
ORDER BY country, month_of_year;

INSERT OVERWRITE DIRECTORY '/energy/output/hive/wind_load_by_hour'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       hour(local_ts)            AS local_hour,
       ROUND(AVG(wind_mw), 1)    AS avg_wind_mw,
       ROUND(AVG(load_mw), 1)    AS avg_load_mw
FROM energy_hourly
WHERE wind_mw IS NOT NULL AND load_mw IS NOT NULL
GROUP BY country, hour(local_ts)
ORDER BY country, local_hour;


-- =================================================================================
-- Q4. Which hours show the largest changes in load?
-- LAG(load_mw) OVER (PARTITION BY country ORDER BY ts) gives the load of the row
-- before, inside the same country. We keep a change only if that row is exactly one
-- hour earlier; across a gap in the data the "previous row" could be days before.
-- =================================================================================
DROP TABLE IF EXISTS load_changes;
CREATE TABLE load_changes STORED AS PARQUET AS
SELECT country, ts, local_ts, load_mw, prev_load_mw,
       load_mw - prev_load_mw                                    AS change_mw,
       ROUND(100.0 * (load_mw - prev_load_mw) / prev_load_mw, 2) AS change_pct
FROM (
    SELECT country, ts, local_ts, load_mw,
           LAG(load_mw) OVER (PARTITION BY country ORDER BY ts) AS prev_load_mw,
           LAG(ts)      OVER (PARTITION BY country ORDER BY ts) AS prev_ts
    FROM energy_hourly
    WHERE load_mw IS NOT NULL
) x
WHERE prev_ts IS NOT NULL
  AND unix_timestamp(ts) - unix_timestamp(prev_ts) = 3600;

-- (a) the 20 biggest rises and the 20 biggest drops, in MW (big grids dominate here)
INSERT OVERWRITE DIRECTORY '/energy/output/hive/top_load_changes'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT * FROM (
    SELECT 'rise' AS direction, country, CAST(local_ts AS STRING) AS local_time,
           hour(local_ts) AS local_hour, prev_load_mw, load_mw, change_mw, change_pct
    FROM load_changes ORDER BY change_mw DESC LIMIT 20
) r
UNION ALL
SELECT * FROM (
    SELECT 'drop' AS direction, country, CAST(local_ts AS STRING) AS local_time,
           hour(local_ts) AS local_hour, prev_load_mw, load_mw, change_mw, change_pct
    FROM load_changes ORDER BY change_mw ASC LIMIT 20
) d;

-- (b) for each country and local hour: average change in % of load.
-- Percent, so small and large countries can be compared.
INSERT OVERWRITE DIRECTORY '/energy/output/hive/load_change_by_hour'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       hour(local_ts)                  AS local_hour,
       ROUND(AVG(change_pct), 2)       AS avg_change_pct,
       ROUND(AVG(ABS(change_pct)), 2)  AS avg_abs_change_pct,
       ROUND(MAX(change_pct), 2)       AS max_rise_pct,
       ROUND(MIN(change_pct), 2)       AS max_drop_pct
FROM load_changes
GROUP BY country, hour(local_ts)
ORDER BY country, local_hour;


-- =================================================================================
-- Q5. How strongly is solar generation related to load?
-- corr() is the Pearson correlation: +1 = rise together, 0 = no straight-line link,
-- -1 = one rises when the other falls. Wind vs load is added for comparison.
-- =================================================================================
INSERT OVERWRITE DIRECTORY '/energy/output/hive/correlation'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       ROUND(corr(solar_mw, load_mw), 3)                         AS corr_solar_load,
       ROUND(corr(wind_mw, load_mw), 3)                          AS corr_wind_load,
       COUNT(*)                                                  AS hours_used
FROM energy_hourly
WHERE solar_mw IS NOT NULL AND wind_mw IS NOT NULL AND load_mw IS NOT NULL
GROUP BY country
ORDER BY corr_solar_load DESC;

-- Correlation by season, because summer and winter behave differently
INSERT OVERWRITE DIRECTORY '/energy/output/hive/correlation_season'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT country,
       CASE WHEN month(local_ts) IN (6, 7, 8) THEN 'summer'
            WHEN month(local_ts) IN (12, 1, 2) THEN 'winter'
            ELSE 'spring_autumn' END                    AS season,
       ROUND(corr(solar_mw, load_mw), 3)                AS corr_solar_load,
       COUNT(*)                                         AS hours_used
FROM energy_hourly
WHERE solar_mw IS NOT NULL AND load_mw IS NOT NULL
GROUP BY country,
         CASE WHEN month(local_ts) IN (6, 7, 8) THEN 'summer'
              WHEN month(local_ts) IN (12, 1, 2) THEN 'winter'
              ELSE 'spring_autumn' END
ORDER BY country, season;

-- Raw hourly pairs for one country and year, for the scatter plot
INSERT OVERWRITE DIRECTORY '/energy/output/hive/scatter_de_2019'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT CAST(local_ts AS STRING), solar_mw, load_mw
FROM energy_hourly
WHERE country = 'DE' AND yr = 2019 AND solar_mw IS NOT NULL AND load_mw IS NOT NULL;
