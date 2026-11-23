package p11;

/**
 * Our own (custom) Hadoop counters. Hadoop adds them up across all map tasks and
 * prints them at the end of the job, under the group "p11.EnergyCounters".
 *
 * In a mapper:  context.getCounter(EnergyCounters.BAD_LINES).increment(1);
 */
public enum EnergyCounters {
    BAD_LINES,          // line could not be parsed (wrong field count, bad number, ...)
    LOAD_RECORDS,       // metric = load
    SOLAR_RECORDS,      // metric = solar
    WIND_RECORDS,       // metric = wind
    SKIPPED_OTHER_METRIC // valid line, but this job does not need that metric (Job A skips solar/wind)
}
