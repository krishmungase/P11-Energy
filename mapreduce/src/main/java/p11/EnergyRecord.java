package p11;

/**
 * One line of energy_full.csv / energy_sample.csv, already split into fields.
 *
 * Line format (no header):
 *   2019-01-01 00:00:00,DE,load,43120.50
 *   timestamp          ,country,metric,value
 *
 * Both jobs use parse() so the "is this line valid?" rule lives in one place.
 */
public class EnergyRecord {
    public final String timestamp;   // "2019-01-01 00:00:00" (UTC)
    public final String country;     // "DE"
    public final String metric;      // "load", "solar" or "wind"
    public final double value;       // MW for that hour

    private EnergyRecord(String timestamp, String country, String metric, double value) {
        this.timestamp = timestamp;
        this.country = country;
        this.metric = metric;
        this.value = value;
    }

    /** "2019" */
    public String year() {
        return timestamp.substring(0, 4);
    }

    /** "2019-01" */
    public String yearMonth() {
        return timestamp.substring(0, 7);
    }

    /**
     * Returns null for any line we cannot use: wrong number of fields, a timestamp that is
     * too short, or a value that is not a number. The mapper counts these as BAD_LINES.
     */
    public static EnergyRecord parse(String line) {
        String[] f = line.split(",");
        if (f.length != 4 || f[0].length() < 19 || f[1].isEmpty()) {
            return null;
        }
        try {
            double v = Double.parseDouble(f[3]);
            if (Double.isNaN(v) || v < 0) {
                return null;   // negative MW is not possible for load/solar/wind
            }
            return new EnergyRecord(f[0], f[1], f[2], v);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
