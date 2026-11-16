"""Run the whole project:  python run.py"""
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
DB = HERE / "fraud.db"

if not DB.exists():
    subprocess.run([sys.executable, str(HERE / "generate_data.py")], check=True)
con = sqlite3.connect(DB)
con.execute("DROP INDEX IF EXISTS idx_orig_step")  # start from an un-indexed baseline
con.execute("DROP INDEX IF EXISTS idx_dest_step")
con.execute("DROP INDEX IF EXISTS idx_fraud")


def run_file(name):
    """Split a .sql file on '-- name:' headers; print each query's result."""
    text = (HERE / "sql" / name).read_text()
    head, *parts = re.split(r"^-- name: (.*)$", text, flags=re.M)
    if head.strip():
        con.executescript(head)  # setup statements (e.g. CREATE VIEW)
    for title, sql in zip(parts[::2], parts[1::2]):
        cur = con.execute(sql.strip().rstrip(";"))
        cols = [d[0] for d in cur.description]
        print(f"\n## {title}")
        print(" | ".join(cols))
        for row in cur.fetchall():
            print(" | ".join(str(v) for v in row))


def timed(label, sql):
    t = time.perf_counter()
    con.execute(sql).fetchall()
    ms = (time.perf_counter() - t) * 1000
    plan = " ; ".join(r[3] for r in con.execute("EXPLAIN QUERY PLAN " + sql))
    print(f"{label:<10} {ms:8.1f} ms   plan: {plan}")


run_file("02_anomalies.sql")
run_file("03_risk_score.sql")

print("\n## Index benchmark (velocity query, whole table)")
BENCH = ("SELECT COUNT(*) FROM (SELECT step - LAG(step,2) OVER "
         "(PARTITION BY name_orig ORDER BY step, txn_id) g FROM transactions) WHERE g <= 1")
LOOKUP = "SELECT * FROM transactions WHERE name_orig = 'C00042' ORDER BY step"
timed("before", BENCH)
timed("before", LOOKUP)
con.executescript((HERE / "sql" / "04_indexes.sql").read_text())
timed("after", BENCH)
timed("after", LOOKUP)
con.close()
