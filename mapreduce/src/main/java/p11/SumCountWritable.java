package p11;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;

import org.apache.hadoop.io.Writable;

/**
 * A (sum, count) pair that Hadoop can send between mapper, combiner and reducer.
 *
 * Why not send the average directly? Because an average of averages is wrong when the
 * groups have different sizes. Example: avg(1,2,3) = 2 and avg(5) = 5, and avg(2,5) = 3.5,
 * but the true average of 1,2,3,5 is 2.75. Sums and counts can be added in any order,
 * so the combiner can add them safely and only the reducer divides.
 */
public class SumCountWritable implements Writable {
    private double sum;
    private long count;

    public SumCountWritable() {
        // Hadoop needs an empty constructor to create the object before readFields()
    }

    public SumCountWritable(double sum, long count) {
        this.sum = sum;
        this.count = count;
    }

    public double getSum() { return sum; }
    public long getCount() { return count; }

    public void set(double sum, long count) {
        this.sum = sum;
        this.count = count;
    }

    /** Called when Hadoop sends this object over the network or writes it to disk. */
    @Override
    public void write(DataOutput out) throws IOException {
        out.writeDouble(sum);
        out.writeLong(count);
    }

    /** Must read the fields in exactly the same order as write() wrote them. */
    @Override
    public void readFields(DataInput in) throws IOException {
        sum = in.readDouble();
        count = in.readLong();
    }

    @Override
    public String toString() {
        return sum + "," + count;
    }
}
