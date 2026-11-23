/*
 * Step 5: Pig.  Peak load hours and daily generation per country.
 *
 * Run (Hadoop must be running):
 *   pig -x mapreduce pig/peak_and_daily.pig                                  -- sample (2019)
 *   pig -x mapreduce -param INPUT=/energy/long/full -param OUTPUT=/energy/output/pig/full pig/peak_and_daily.pig
 *
 * Outputs (CSV, no header) under $OUTPUT:
 *   countries/       list of countries in the data                    (DISTINCT)
 *   peak_hour/       country, timestamp, MW of the single highest-load hour
 *   hourly_profile/  country, hour of day (0-23 UTC), average load MW
 *   peak_hour_of_day/ country, hour of day with the highest average load, MW
 *   daily/           country, day, solar MWh, wind MWh, load MWh, renewable share
 *   top_wind_days/   the 10 days with the most wind energy (any country)
 *
 * Operators used: LOAD, FILTER, SPLIT, FOREACH, DISTINCT, GROUP, ORDER, LIMIT, JOIN, STORE
 * Built-in functions: SUM, MAX, AVG, COUNT, SUBSTRING, ToDate, GetHour
 */

%default INPUT  '/energy/long/sample'
%default OUTPUT '/energy/output/pig/sample'

-- Delete old output first, otherwise STORE fails with "output already exists"
rmf $OUTPUT

-- LOAD: read the long CSV and give each column a name and type
raw = LOAD '$INPUT' USING PigStorage(',')
      AS (ts:chararray, country:chararray, metric:chararray, value:double);

-- FILTER: drop broken lines (value could not be read as a number, so it is null)
clean = FILTER raw BY ts IS NOT NULL AND value IS NOT NULL AND value >= 0;

-- SPLIT: one pass over the data, three relations out
SPLIT clean INTO load_rows  IF metric == 'load',
                 solar_rows IF metric == 'solar',
                 wind_rows  IF metric == 'wind';

-- DISTINCT: which countries are in the file
country_col = FOREACH clean GENERATE country;
countries   = DISTINCT country_col;
STORE countries INTO '$OUTPUT/countries' USING PigStorage(',');


/* ---------- 1a. The single hour with the highest load, per country ---------- */

load_by_country = GROUP load_rows BY country;
peak_hour = FOREACH load_by_country {
    -- nested ORDER + LIMIT: sort this country's hours and keep the top one
    sorted = ORDER load_rows BY value DESC;
    top    = LIMIT sorted 1;
    GENERATE group AS country, FLATTEN(top.ts) AS ts, MAX(load_rows.value) AS peak_mw;
};
STORE peak_hour INTO '$OUTPUT/peak_hour' USING PigStorage(',');


/* ---------- 1b. Which hour of the day has the highest average load ---------- */

-- ToDate turns the text into a date-time (in UTC), GetHour takes the hour 0-23
load_hour = FOREACH load_rows GENERATE
                country,
                GetHour(ToDate(ts, 'yyyy-MM-dd HH:mm:ss', 'UTC')) AS hour,
                value;
by_country_hour = GROUP load_hour BY (country, hour);
hourly_profile  = FOREACH by_country_hour GENERATE
                      FLATTEN(group) AS (country, hour),
                      AVG(load_hour.value) AS avg_load_mw;
hourly_sorted = ORDER hourly_profile BY country, hour;
STORE hourly_sorted INTO '$OUTPUT/hourly_profile' USING PigStorage(',');

profile_by_country = GROUP hourly_profile BY country;
peak_hour_of_day = FOREACH profile_by_country {
    s = ORDER hourly_profile BY avg_load_mw DESC;
    t = LIMIT s 1;
    GENERATE FLATTEN(t);
};
STORE peak_hour_of_day INTO '$OUTPUT/peak_hour_of_day' USING PigStorage(',');


/* ---------- 2. Daily totals per source, joined with daily load ---------- */

-- SUBSTRING(ts, 0, 10) keeps "2019-06-01" from "2019-06-01 12:00:00".
-- Each reading covers one hour, so the sum of MW over a day is MWh.
solar_d = FOREACH solar_rows GENERATE country, SUBSTRING(ts, 0, 10) AS day, value;
wind_d  = FOREACH wind_rows  GENERATE country, SUBSTRING(ts, 0, 10) AS day, value;
load_d  = FOREACH load_rows  GENERATE country, SUBSTRING(ts, 0, 10) AS day, value;

solar_g = GROUP solar_d BY (country, day);
wind_g  = GROUP wind_d  BY (country, day);
load_g  = GROUP load_d  BY (country, day);

solar_daily = FOREACH solar_g GENERATE FLATTEN(group) AS (country, day), SUM(solar_d.value) AS solar_mwh;
wind_daily  = FOREACH wind_g  GENERATE FLATTEN(group) AS (country, day), SUM(wind_d.value)  AS wind_mwh;
load_daily  = FOREACH load_g  GENERATE FLATTEN(group) AS (country, day), SUM(load_d.value)  AS load_mwh,
                                       COUNT(load_d) AS load_hours;

-- JOIN: inner join, so a day is kept only if it has solar, wind and load data
gen_j = JOIN solar_daily BY (country, day), wind_daily BY (country, day);
gen   = FOREACH gen_j GENERATE solar_daily::country AS country, solar_daily::day AS day,
                               solar_mwh, wind_mwh;

all_j = JOIN gen BY (country, day), load_daily BY (country, day);
daily = FOREACH all_j GENERATE
            gen::country AS country, gen::day AS day,
            solar_mwh, wind_mwh, load_mwh,
            (solar_mwh + wind_mwh) / load_mwh AS share,
            load_hours;

daily_sorted = ORDER daily BY country, day;
STORE daily_sorted INTO '$OUTPUT/daily' USING PigStorage(',');

-- ORDER + LIMIT at the top level: the 10 windiest days in any country
by_wind       = ORDER daily BY wind_mwh DESC;
top_wind_days = LIMIT by_wind 10;
STORE top_wind_days INTO '$OUTPUT/top_wind_days' USING PigStorage(',');
