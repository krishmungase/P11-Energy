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
 * Job B: renewable share per country per month.
 *
 *   share = (avg solar MW + avg wind MW) / avg load MW
 *
 * Each average is taken over the hours that metric has data for. We do not divide plain
 * totals (solar MWh + wind MWh) / load MWh, because Belgium's wind has gaps in 5-25% of
 * hours each month while its load is complete; totals would make its share look too low.
 * When nothing is missing, both formulas give exactly the same number.
 *
 *   input line   2019-06-01 12:00:00,ES,solar,6540.00
 *   map out      key "ES,2019-06"   value solar=6540, wind=0, load=0 (solarHours=1)
 *   combine      key "ES,2019-06"   value the three totals and three hour counts added up
 *   reduce out   ES,2019-06,solar_mwh,wind_mwh,load_mwh,share,solar_hours,wind_hours,load_hours
 *
 * The hour counts are also written out so missing data is visible (a full month has 720-744 hours).
 *
 * Run:  hadoop jar p11-energy-mr.jar share /energy/long/sample /energy/output/mr/share_sample
 */
public class RenewableShareJob extends Configured implements Tool {

    public static class ShareMapper extends Mapper<LongWritable, Text, Text, EnergySumsWritable> {
        private final Text outKey = new Text();
        private final EnergySumsWritable outValue = new EnergySumsWritable();

        @Override
        protected void map(LongWritable offset, Text line, Context context)
                throws IOException, InterruptedException {
            EnergyRecord r = EnergyRecord.parse(line.toString());
            if (r == null) {
                context.getCounter(EnergyCounters.BAD_LINES).increment(1);
                return;
            }
            if (!outValue.setOne(r.metric, r.value)) {
                context.getCounter(EnergyCounters.SKIPPED_OTHER_METRIC).increment(1);
                return;
            }
            switch (r.metric) {
                case "load":  context.getCounter(EnergyCounters.LOAD_RECORDS).increment(1); break;
                case "solar": context.getCounter(EnergyCounters.SOLAR_RECORDS).increment(1); break;
                default:      context.getCounter(EnergyCounters.WIND_RECORDS).increment(1); break;
            }
            outKey.set(r.country + "," + r.yearMonth());
            context.write(outKey, outValue);
        }
    }

    /** Adds the three totals separately. Never divides, so it is safe to run any number of times. */
    public static class SumsCombiner extends Reducer<Text, EnergySumsWritable, Text, EnergySumsWritable> {
        private final EnergySumsWritable total = new EnergySumsWritable();

        @Override
        protected void reduce(Text key, Iterable<EnergySumsWritable> values, Context context)
                throws IOException, InterruptedException {
            total.clear();
            for (EnergySumsWritable v : values) {
                total.add(v);
            }
            context.write(key, total);
        }
    }

    public static class ShareReducer extends Reducer<Text, EnergySumsWritable, Text, NullWritable> {
        private final EnergySumsWritable total = new EnergySumsWritable();
        private final Text line = new Text();

        @Override
        protected void reduce(Text key, Iterable<EnergySumsWritable> values, Context context)
                throws IOException, InterruptedException {
            total.clear();
            for (EnergySumsWritable v : values) {
                total.add(v);
            }
            if (total.getLoadHours() == 0 || total.getLoad() == 0) {
                return;   // no load data for this month: cannot divide
            }
            double avgSolar = total.getSolarHours() > 0 ? total.getSolar() / total.getSolarHours() : 0;
            double avgWind = total.getWindHours() > 0 ? total.getWind() / total.getWindHours() : 0;
            double avgLoad = total.getLoad() / total.getLoadHours();
            double share = (avgSolar + avgWind) / avgLoad;
            line.set(String.format("%s,%.1f,%.1f,%.1f,%.4f,%d,%d,%d",
                    key, total.getSolar(), total.getWind(), total.getLoad(), share,
                    total.getSolarHours(), total.getWindHours(), total.getLoadHours()));
            context.write(line, NullWritable.get());
        }
    }

    @Override
    public int run(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Usage: share [-D options] <input> <output>");
            return 2;
        }
        Job job = Job.getInstance(getConf(), "P11 Job B: renewable share per country per month");
        job.setJarByClass(RenewableShareJob.class);

        job.setMapperClass(ShareMapper.class);
        if (getConf().getBoolean("p11.combiner", true)) {
            job.setCombinerClass(SumsCombiner.class);
        }
        job.setPartitionerClass(CountryPartitioner.class);   // same partitioner as Job A
        job.setReducerClass(ShareReducer.class);
        job.setNumReduceTasks(getConf().getInt("p11.reducers", 3));

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(EnergySumsWritable.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(NullWritable.class);

        FileInputFormat.addInputPath(job, new Path(args[0]));
        FileOutputFormat.setOutputPath(job, new Path(args[1]));
        return job.waitForCompletion(true) ? 0 : 1;
    }
}
