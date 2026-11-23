package p11;

import java.io.IOException;

import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.util.Tool;

/**
 * Job A: average load (MW) per country per year.
 *
 *   input line   2019-01-01 00:00:00,DE,load,43120.50
 *   map out      key "DE,2019"   value (43120.50, 1)
 *   combine      key "DE,2019"   value (sum of a few thousand values, how many)
 *   reduce out   DE,2019,57328.41,8760      (country, year, average MW, hours)
 *
 * Run:  hadoop jar p11-energy-mr.jar avgload /energy/long/sample /energy/output/mr/avgload_sample
 * Options (put them right after "avgload"):
 *   -D p11.reducers=3            number of reducers (default 3). We use our own name because
 *                                mapreduce.job.reduces already defaults to 1 in Hadoop.
 *   -D p11.combiner=false        turn the combiner off, to compare counters
 */
public class AvgLoadJob extends Configured implements Tool {

    /** Reads one line, keeps it only if it is a load reading. */
    public static class LoadMapper extends Mapper<LongWritable, Text, Text, SumCountWritable> {
        // Reuse the same objects for every line. Creating new ones each time is slower.
        private final Text outKey = new Text();
        private final SumCountWritable outValue = new SumCountWritable();

        @Override
        protected void map(LongWritable offset, Text line, Context context)
                throws IOException, InterruptedException {
            EnergyRecord r = EnergyRecord.parse(line.toString());
            if (r == null) {
                context.getCounter(EnergyCounters.BAD_LINES).increment(1);
                return;
            }
            if (!r.metric.equals("load")) {
                context.getCounter(EnergyCounters.SKIPPED_OTHER_METRIC).increment(1);
                return;
            }
            context.getCounter(EnergyCounters.LOAD_RECORDS).increment(1);
            outKey.set(r.country + "," + r.year());
            outValue.set(r.value, 1);
            context.write(outKey, outValue);
        }
    }

    /**
     * Runs on the map side, before the shuffle. Adds sums and counts but does NOT divide.
     * Input and output types are the same (Text, SumCountWritable), which a combiner needs,
     * because Hadoop may run it 0, 1 or many times.
     */
    public static class SumCountCombiner extends Reducer<Text, SumCountWritable, Text, SumCountWritable> {
        private final SumCountWritable result = new SumCountWritable();

        @Override
        protected void reduce(Text key, Iterable<SumCountWritable> values, Context context)
                throws IOException, InterruptedException {
            double sum = 0;
            long count = 0;
            for (SumCountWritable v : values) {
                sum += v.getSum();
                count += v.getCount();
            }
            result.set(sum, count);
            context.write(key, result);
        }
    }

    /** Adds all (sum, count) pairs for one country-year and divides once. */
    public static class AvgReducer extends Reducer<Text, SumCountWritable, Text, NullWritable> {
        private final Text line = new Text();

        @Override
        protected void reduce(Text key, Iterable<SumCountWritable> values, Context context)
                throws IOException, InterruptedException {
            double sum = 0;
            long count = 0;
            for (SumCountWritable v : values) {
                sum += v.getSum();
                count += v.getCount();
            }
            double avg = sum / count;
            // Output one CSV line: country,year,avg_load_mw,hours
            line.set(String.format("%s,%.2f,%d", key, avg, count));
            context.write(line, NullWritable.get());
        }
    }

    @Override
    public int run(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Usage: avgload [-D options] <input> <output>");
            return 2;
        }
        Job job = Job.getInstance(getConf(), "P11 Job A: average load per country per year");
        job.setJarByClass(AvgLoadJob.class);

        job.setMapperClass(LoadMapper.class);
        if (getConf().getBoolean("p11.combiner", true)) {
            job.setCombinerClass(SumCountCombiner.class);
        }
        job.setPartitionerClass(CountryPartitioner.class);
        job.setReducerClass(AvgReducer.class);
        job.setNumReduceTasks(getConf().getInt("p11.reducers", 3));

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(SumCountWritable.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(NullWritable.class);

        FileInputFormat.addInputPath(job, new Path(args[0]));
        FileOutputFormat.setOutputPath(job, new Path(args[1]));
        return job.waitForCompletion(true) ? 0 : 1;
    }
}
