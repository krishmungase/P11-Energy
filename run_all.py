#!/usr/bin/env python3
"""
Step 8: scale test. Runs the same jobs on different amounts of data and records the
wall-clock time and the Hadoop counters of every run.

Data sets (all in HDFS, made in Step 2 except x5):
    sample     /energy/long/sample      2019 only,             9.4 MB,  1 block
    full       /energy/long/full        2015-2020,            52.9 MB,  1 block of 128 MB
    full_32mb  /energy/long/full_32mb   same file, 32 MB blocks,          2 blocks
    full_x5    /energy/long/full_x5     the full file 5 times, 264 MB,  2 blocks (252 MiB)
The x5 copy exists because 52.9 MB is still small: most of a 20-second job is YARN
starting containers, so sample and full take almost the same time. Five copies give
the same averages (each value appears 5 times) with 5x the records, which is also a
handy correctness check.

Jobs:
    MapReduce Job A (avgload) and Job B (share)   on all four data sets
    Pig script                                    on sample and full (each run is ~5 min)
    Two Hive queries on the CSV external tables    on sample, full and full_x5

Usage (Hadoop running, Steps 2, 3 and 6 done):
    .venv/bin/python run_all.py              # everything, about 20 minutes
    .venv/bin/python run_all.py --skip-pig   # without the two Pig runs
Writes:
    results/scale/scale_results.md   the table for the report
    results/scale/scale_results.csv  the same numbers as CSV
    results/scale/logs/*.txt         the full log of every run
"""
import argparse
import csv
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "results" / "scale"
LOGS = OUT / "logs"
JAR = ROOT / "mapreduce" / "target" / "p11-energy-mr.jar"

DATASETS = {
    "sample": "/energy/long/sample",
    "full": "/energy/long/full",
    "full_32mb": "/energy/long/full_32mb",
    "full_x5": "/energy/long/full_x5",
}
HIVE_TABLES = {"sample": "energy_raw_ext_sample", "full": "energy_raw_ext", "full_x5": "energy_raw_ext_x5"}

# Two Hive queries: a plain GROUP BY, and the join used for question 1
HIVE_QUERIES = {
    "hive_avg_load": """SELECT country, substr(ts, 1, 4) AS yr, AVG(value)
                        FROM {t} WHERE metric = 'load' GROUP BY country, substr(ts, 1, 4)""",
    "hive_share_join": """SELECT g.country, g.yr, (g.s + g.w) / l.ld AS share FROM
          (SELECT country, substr(ts, 1, 4) AS yr,
                  AVG(CASE WHEN metric = 'solar' THEN value END) AS s,
                  AVG(CASE WHEN metric = 'wind' THEN value END) AS w
           FROM {t} WHERE metric IN ('solar', 'wind') GROUP BY country, substr(ts, 1, 4)) g
          JOIN (SELECT country, substr(ts, 1, 4) AS yr, AVG(value) AS ld
                FROM {t} WHERE metric = 'load' GROUP BY country, substr(ts, 1, 4)) l
          ON g.country = l.country AND g.yr = l.yr""",
}

MR_COUNTERS = ["Launched map tasks", "Launched reduce tasks", "Map input records",
               "Map output records", "Combine input records", "Combine output records",
               "Reduce input records", "Reduce shuffle bytes", "HDFS: Number of bytes read"]


def env():
    """Same environment as `source env.sh`."""
    out = subprocess.run(["bash", "-c", f"source '{ROOT}/env.sh' && env"],
                         capture_output=True, text=True, check=True).stdout
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


ENV = env()


def sh(cmd, log=None):
    """Run a shell command, return (seconds, output)."""
    start = time.time()
    p = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=ENV, cwd=ROOT)
    secs = time.time() - start
    text = p.stdout + p.stderr
    if log:
        log.write_text(text + f"\nWall clock seconds: {secs:.1f}\nExit code: {p.returncode}\n")
    if p.returncode != 0:
        print(f"   !! exit code {p.returncode}, see {log}")
    return secs, text


def counter(text, name):
    m = re.search(rf"^\s*{re.escape(name)}=(\d+)", text, re.M)
    return int(m.group(1)) if m else None


def ensure_x5():
    _, out = sh("hdfs dfs -test -e /energy/long/full_x5/energy_full_x5.csv && echo yes || echo no")
    if "yes" in out:
        return
    print(">> Making /energy/long/full_x5 (the full file 5 times, ~264 MB)")
    f = ROOT / "data" / "energy_full.csv"
    sh(f"hdfs dfs -mkdir -p /energy/long/full_x5 && "
       f"cat '{f}' '{f}' '{f}' '{f}' '{f}' | hdfs dfs -put -f - /energy/long/full_x5/energy_full_x5.csv")


def ensure_hive_x5_table():
    sql = ("CREATE DATABASE IF NOT EXISTS energy; USE energy; "
           "CREATE EXTERNAL TABLE IF NOT EXISTS energy_raw_ext_x5 "
           "(ts STRING, country STRING, metric STRING, value DOUBLE) "
           "ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE "
           "LOCATION '/energy/long/full_x5';")
    sh(f'beeline -u jdbc:hive2:// --silent=true -e "{sql}"')


def size_and_blocks(path):
    _, out = sh(f"hdfs dfs -du -s {path}; hdfs fsck {path} -files -blocks 2>/dev/null | grep 'Total blocks'")
    size = int(out.split()[0]) if out.strip() and out.split()[0].isdigit() else None
    m = re.search(r"Total blocks \(validated\):\s+(\d+)", out)
    return size, int(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-pig", action="store_true")
    args = ap.parse_args()
    LOGS.mkdir(parents=True, exist_ok=True)

    print(">> Building the MapReduce jar")
    sh("cd mapreduce && mvn -q package")
    ensure_x5()
    ensure_hive_x5_table()

    info = {d: size_and_blocks(p) for d, p in DATASETS.items()}
    rows = []

    # ---- MapReduce ----
    for d, path in DATASETS.items():
        for job in ("avgload", "share"):
            name = f"mr_{job}_{d}"
            print(f">> {name}")
            out_dir = f"/energy/output/scale/{name}"
            secs, text = sh(f"hdfs dfs -rm -r -f -skipTrash {out_dir} >/dev/null 2>&1; "
                            f"hadoop jar {JAR} {job} -D p11.reducers=3 {path} {out_dir}",
                            LOGS / f"{name}.txt")
            row = {"tool": "MapReduce", "job": job, "data": d, "seconds": round(secs, 1)}
            row.update({c: counter(text, c) for c in MR_COUNTERS})
            rows.append(row)
            print(f"   {secs:.0f} s, {row['Launched map tasks']} map tasks, "
                  f"{row['Map input records']} input records")

    # ---- Pig ----
    if not args.skip_pig:
        for d in ("sample", "full"):
            name = f"pig_{d}"
            print(f">> {name} (about 5 minutes)")
            secs, text = sh(f"pig -x mapreduce -param INPUT={DATASETS[d]} "
                            f"-param OUTPUT=/energy/output/scale/{name} pig/peak_and_daily.pig",
                            LOGS / f"{name}.txt")
            m = re.search(r"Successfully read (\d+) records \((\d+) bytes\)", text)
            rows.append({"tool": "Pig", "job": "peak_and_daily.pig", "data": d,
                         "seconds": round(secs, 1),
                         "Map input records": int(m.group(1)) if m else None,
                         "HDFS: Number of bytes read": int(m.group(2)) if m else None,
                         # count only the rows of Pig's "Job Stats" table; job ids also
                         # appear in other parts of the log
                         "MR jobs": len(re.findall(r"^job_\d+_\d+\t",
                                                   text.split("Job Stats")[-1].split("Input(s)")[0],
                                                   re.M))})
            print(f"   {secs:.0f} s, {rows[-1]['MR jobs']} MapReduce jobs")

    # ---- Hive ----
    for d, table in HIVE_TABLES.items():
        for qname, q in HIVE_QUERIES.items():
            name = f"{qname}_{d}"
            print(f">> {name}")
            sql = "USE energy; " + " ".join(q.format(t=table).split()) + ";"
            secs, text = sh(f'beeline -u jdbc:hive2:// --silent=true -i hive/init.sql -e "{sql}"',
                            LOGS / f"{name}.txt")
            stages = re.findall(r"Stage-Stage-\d+: Map: (\d+)\s+Reduce: (\d+)\s+HDFS Read: (\d+)", text)
            rows.append({"tool": "Hive", "job": qname, "data": d, "seconds": round(secs, 1),
                         "MR jobs": len(stages),
                         "Launched map tasks": sum(int(s[0]) for s in stages),
                         "Launched reduce tasks": sum(int(s[1]) for s in stages),
                         "HDFS: Number of bytes read": sum(int(s[2]) for s in stages)})
            print(f"   {secs:.0f} s, {len(stages)} MapReduce jobs")

    # ---- write results ----
    cols = ["tool", "job", "data", "seconds", "MR jobs"] + MR_COUNTERS
    with open(OUT / "scale_results.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c) for c in cols})

    def fmt(v):
        return "" if v is None else (f"{v:,}" if isinstance(v, int) else str(v))

    lines = ["# Scale test results", "", "## Data sets", "",
             "| data | HDFS path | size (bytes) | blocks |", "|---|---|---|---|"]
    for d, p in DATASETS.items():
        s, b = info[d]
        lines.append(f"| {d} | {p} | {fmt(s)} | {fmt(b)} |")
    lines += ["", "## Runs", "",
              "| tool | job | data | seconds | MR jobs | map tasks | reduce tasks | map input records "
              "| map output records | combine in | combine out | reduce input records | shuffle bytes "
              "| HDFS bytes read |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| " + " | ".join(fmt(r.get(c)) for c in
                     ["tool", "job", "data", "seconds", "MR jobs", "Launched map tasks",
                      "Launched reduce tasks", "Map input records", "Map output records",
                      "Combine input records", "Combine output records", "Reduce input records",
                      "Reduce shuffle bytes", "HDFS: Number of bytes read"]) + " |")
    (OUT / "scale_results.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
