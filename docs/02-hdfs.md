# Step 2: HDFS

Owner: Krish Mungase (krishmungase)

This step puts our data into HDFS and shows the HDFS features the rules ask for: at least 3 directories, `fsck` output, one replication change, and one file with a non-default block size.

Script: `hdfs/hdfs_commands.sh`. Every command's output is also saved in `results/hdfs/`.

## A short reminder of how HDFS stores a file

HDFS cuts every file into blocks, 128 MB each by default. The last block is only as big as the data left over. Each block is stored on one or more DataNodes; the number of copies is the replication factor. The NameNode keeps the list of which blocks make up which file and where each copy lives.

Bigger blocks mean fewer blocks, so the NameNode has less to track and a job starts fewer map tasks. Smaller blocks mean more map tasks, which helps only if there are enough machines to run them in parallel.

## Folders

```text
/energy/raw          the original wide CSV from OPSD
/energy/long/sample  energy_sample.csv (2019 only)
/energy/long/full    energy_full.csv (all years), 128 MB blocks
/energy/long/full_32mb  the same file again, uploaded with 32 MB blocks
/energy/output       results of MapReduce (output/mr) and Pig (output/pig)
/energy/warehouse    Hive's managed tables
```

`sample` and `full` sit in separate folders because MapReduce, Pig and Hive all take a folder as input. Pointing a job at `/energy/long/sample` reads only the sample.

## Running it

Hadoop must be running (`bash setup/start-hadoop.sh`). Then:

```bash
cd ~/Desktop/BDA/P11-Energy
bash hdfs/hdfs_commands.sh
```

It takes about 25 seconds. The script can be run again safely: `mkdir -p` does not fail on existing folders and `put -f` overwrites files.

## What each section does and what we got

### 1. jps

Lists the running Java processes. We expect NameNode, DataNode, ResourceManager, NodeManager and JobHistoryServer.

### 2. Make the folders

```bash
hdfs dfs -mkdir -p /energy/raw /energy/long/sample /energy/long/full /energy/long/full_32mb \
                   /energy/output /energy/warehouse
hdfs dfs -ls -R /energy
```

### 3. Upload with the default block size

```bash
hdfs dfs -put -f data/time_series_60min_singleindex.csv /energy/raw/
hdfs dfs -put -f data/energy_sample.csv /energy/long/sample/
hdfs dfs -put -f data/energy_full.csv   /energy/long/full/
```

### 4. Upload again with a 32 MB block size

```bash
hdfs dfs -D dfs.blocksize=33554432 -put -f data/energy_full.csv /energy/long/full_32mb/
hdfs dfs -stat "blocksize=%o replication=%r bytes=%b name=%n" <files>
```

`-D dfs.blocksize=...` changes the block size for this one command only. 33,554,432 bytes is 32 × 1024 × 1024. Block size is fixed per file when the file is written; changing the setting later does not re-cut existing files.

### 5. fsck

```bash
hdfs fsck /energy/long/full      -files -blocks -locations
hdfs fsck /energy/long/full_32mb -files -blocks -locations
hdfs fsck /energy
```

`fsck` asks the NameNode about the health of files: how many blocks each has, how many copies, and where they are. Unlike Linux `fsck`, it only reports; it does not repair anything.

Results (from `results/hdfs/04_blocksize.txt` and `05_fsck_*.txt`):

| File | Size (bytes) | Block size | Blocks | Block lengths |
|---|---|---|---|---|
| `/energy/long/full/energy_full.csv` | 52,895,430 | 128 MB | 1 | 52,895,430 |
| `/energy/long/full_32mb/energy_full.csv` | 52,895,430 | 32 MB | 2 | 33,554,432 + 19,340,998 |
| `/energy/raw/time_series_60min_singleindex.csv` | 130,339,665 | 128 MB | 1 | 130,339,665 |

The same 52.9 MB file is 1 block with the default size and 2 blocks with 32 MB blocks. The second block holds only the remaining 19.3 MB; HDFS does not pad it to 32 MB, so a small last block wastes no disk space.

The raw file is 130.3 MB, which looks bigger than 128 MB, but 128 MB here means 128 × 1024 × 1024 = 134,217,728 bytes. 130,339,665 is less than that, so it fits in one block.

Status for the whole `/energy` tree: HEALTHY, 0 under-replicated blocks.

### 6. Replication change

```bash
hdfs dfs -setrep 2 /energy/long/sample/energy_sample.csv
hdfs fsck /energy/long/sample -files -blocks -locations
```

`-stat` confirms the file's target replication is now 2. `fsck` then reports:

```text
replicated: replication=2, 1 block(s):  Under replicated ...
Target Replicas is 2 but found 1 live replica(s)
 Under-replicated blocks:   1 (100.0 %)
 Missing replicas:          1 (50.0 %)
 Status: HEALTHY
```

This is expected. We asked for 2 copies, but there is only one DataNode, and HDFS never puts two copies of the same block on the same DataNode (that would not protect against losing the machine). So the second copy has nowhere to go. The status is still HEALTHY because the data is not lost: one complete copy exists. HDFS reports HEALTHY until a block has no copies at all ("missing") or is "corrupt".

On a real cluster with 2 or more DataNodes, the NameNode would notice the under-replicated block and tell a DataNode to copy it, and fsck would show 0 under-replicated blocks after a few seconds.

We did not use `-setrep -w 2`. The `-w` flag waits until the new replication is reached, and with one DataNode that never happens, so the command would hang forever.

### 7. Back to replication 1

```bash
hdfs dfs -setrep 1 /energy/long/sample/energy_sample.csv
```

fsck is back to 0 under-replicated blocks.

### 8. Disk usage

`hdfs dfs -du -h /energy` prints two numbers per folder: the file size and the disk space used including all copies. With replication 1 both are the same. With replication 3 the second number would be three times the first.

| Folder | Size |
|---|---|
| `/energy/raw` | 124.3 MB |
| `/energy/long` | 109.8 MB (sample + full + the 32 MB-block copy) |
| `/energy/output` | grows as MapReduce and Pig write results |
| `/energy/warehouse` | grows as Hive creates tables |

`-du -h` uses binary units, so 130,339,665 bytes shows as 124.3 M (MiB).

## Screenshots to take

Save them in `screenshots/02-hdfs/`. The script prints a `===== N. ... =====` header before each section, which makes the screenshots easy to label.

1. Section 2: `hdfs dfs -ls -R /energy` showing all folders
2. Section 4: the three `-stat` lines with blocksize 134217728 and 33554432
3. Section 5: fsck of `full` (1 block) and `full_32mb` (2 blocks) side by side
4. Section 6: fsck showing "Target Replicas is 2 but found 1" and "Under-replicated blocks: 1"
5. Section 7: fsck back to 0 under-replicated blocks
6. NameNode web page (http://localhost:9870) → Utilities → Browse the file system → `/energy/long/full_32mb/energy_full.csv`. Clicking the file shows its 2 blocks with their IDs.

## Viva questions for this step

What is a block, and why is the default 128 MB?
A block is the unit HDFS stores and copies. It is large because HDFS is built for big files read from start to end. A large block keeps the NameNode's list short (the NameNode holds it all in memory) and makes the time spent finding a block small compared to the time spent reading it.

How many map tasks would a job start on each copy of energy_full.csv?
By default one map task per input split, and one split per block. The 128 MB copy gives 1 map task and the 32 MB copy gives 2.

If a file is 1 KB, does it use 128 MB of disk?
No. A block only takes as much disk space as the data in it. The 128 MB is an upper limit, not a fixed size. Many small files are still a problem, because each one costs memory in the NameNode.

What happens when you set replication to 2 on one machine?
The target becomes 2, but HDFS will not put two copies of a block on the same DataNode. The block stays at 1 copy and fsck reports it as under-replicated. The data is still readable and the status stays HEALTHY.

What does fsck check? Does it fix anything?
It asks the NameNode, for each file, how many blocks it has, how many live copies each block has, and where they are. It reports missing, corrupt, under- and over-replicated blocks. It does not repair. Re-replication is done by the NameNode on its own.

What is the difference between `-setrep 2` and `-setrep -w 2`?
Both set the target. `-w` also waits until every block actually has 2 copies. On our one-node setup that never happens, so `-w` would hang.

Can you change the block size of a file that is already in HDFS?
No. It is fixed when the file is written. To change it you copy or upload the file again with the new size, which is what we did for `full_32mb`.
