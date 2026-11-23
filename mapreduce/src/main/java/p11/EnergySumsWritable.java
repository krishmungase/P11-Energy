package p11;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;

import org.apache.hadoop.io.Writable;

/**
 * Three running totals (solar, wind, load) plus how many hours went into each.
 * Used by Job B (renewable share per month).
 *
 * The mapper fills only one slot per record. A solar reading of 120 MW becomes
 * solar=120, wind=0, load=0, solarHours=1. The combiner and reducer just add slots.
 *
 * Since each reading is one hour, a sum of MW values is energy in MWh.
 */
public class EnergySumsWritable implements Writable {
    private double solar, wind, load;
    private long solarHours, windHours, loadHours;

    public EnergySumsWritable() { }

    public void clear() {
        solar = wind = load = 0;
        solarHours = windHours = loadHours = 0;
    }

    /** Put one reading into the right slot. Returns false for an unknown metric. */
    public boolean setOne(String metric, double value) {
        clear();
        switch (metric) {
            case "solar": solar = value; solarHours = 1; return true;
            case "wind":  wind = value;  windHours = 1;  return true;
            case "load":  load = value;  loadHours = 1;  return true;
            default: return false;
        }
    }

    /** Add another object's totals into this one (used by combiner and reducer). */
    public void add(EnergySumsWritable o) {
        solar += o.solar;
        wind += o.wind;
        load += o.load;
        solarHours += o.solarHours;
        windHours += o.windHours;
        loadHours += o.loadHours;
    }

    public double getSolar() { return solar; }
    public double getWind() { return wind; }
    public double getLoad() { return load; }
    public long getSolarHours() { return solarHours; }
    public long getWindHours() { return windHours; }
    public long getLoadHours() { return loadHours; }

    @Override
    public void write(DataOutput out) throws IOException {
        out.writeDouble(solar);
        out.writeDouble(wind);
        out.writeDouble(load);
        out.writeLong(solarHours);
        out.writeLong(windHours);
        out.writeLong(loadHours);
    }

    @Override
    public void readFields(DataInput in) throws IOException {
        solar = in.readDouble();
        wind = in.readDouble();
        load = in.readDouble();
        solarHours = in.readLong();
        windHours = in.readLong();
        loadHours = in.readLong();
    }
}
