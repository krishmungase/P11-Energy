package p11;

import java.util.Arrays;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.util.ToolRunner;

/**
 * Entry point of the jar. The first word picks the job:
 *
 *   hadoop jar p11-energy-mr.jar avgload [-D ...] <input> <output>
 *   hadoop jar p11-energy-mr.jar share   [-D ...] <input> <output>
 *
 * ToolRunner reads the "-D name=value" options into the job Configuration, which is how
 * we change the number of reducers or turn the combiner off without recompiling.
 */
public class Main {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("Usage: hadoop jar p11-energy-mr.jar (avgload|share) [-D opts] <in> <out>");
            System.exit(2);
        }
        String[] rest = Arrays.copyOfRange(args, 1, args.length);
        int code;
        switch (args[0]) {
            case "avgload": code = ToolRunner.run(new Configuration(), new AvgLoadJob(), rest); break;
            case "share":   code = ToolRunner.run(new Configuration(), new RenewableShareJob(), rest); break;
            default:
                System.err.println("Unknown job: " + args[0] + " (use avgload or share)");
                code = 2;
        }
        System.exit(code);
    }
}
