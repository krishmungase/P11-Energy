package p11;

import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Partitioner;

/**
 * Decides which reducer gets each key.
 *
 * Keys look like "DE,2019" (Job A) or "DE,2019-01" (Job B). The default HashPartitioner
 * hashes the whole key, so DE,2019 and DE,2020 could land on different reducers and
 * Germany would be split across output files.
 *
 * We hash only the country part, so every key of one country goes to the same reducer
 * and each part-r-0000N file holds complete countries.
 *
 * With 1 reducer this class still runs, but it always returns 0, so it has no effect.
 * That is why we run the jobs with 3 reducers.
 */
public class CountryPartitioner<V> extends Partitioner<Text, V> {

    @Override
    public int getPartition(Text key, V value, int numReducers) {
        String k = key.toString();
        int comma = k.indexOf(',');
        String country = comma > 0 ? k.substring(0, comma) : k;
        // & Integer.MAX_VALUE removes the minus sign, because hashCode() can be negative
        return (country.hashCode() & Integer.MAX_VALUE) % numReducers;
    }
}
