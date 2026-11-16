"""Generate a small PaySim-style transaction dataset into fraud.db (SQLite).

Normal behaviour is random; three fraud patterns are injected so the SQL
analysis has something real to find:
  1. DRAIN      - TRANSFER of the whole balance, then CASH_OUT by the mule.
  2. BURST      - many rapid small transactions from one account.
  3. SPIKE      - a single huge amount far above the account's normal size.
"""
import random
import sqlite3
from pathlib import Path

random.seed(42)
DB = Path(__file__).parent / "fraud.db"
N_CUSTOMERS, N_NORMAL, HOURS = 2000, 50_000, 720  # 30 days of hourly "steps"

if DB.exists():
    DB.unlink()
con = sqlite3.connect(DB)
con.executescript(Path(__file__).parent.joinpath("sql/01_schema.sql").read_text())

balance = {f"C{i:05d}": random.uniform(500, 50_000) for i in range(N_CUSTOMERS)}
accts = list(balance)
rows = []


def add(step, typ, amount, orig, dest, fraud):
    """Record a transaction and update both balances (PaySim columns)."""
    amount = round(min(amount, balance[orig]), 2)
    if amount <= 0:
        return
    ob, od = balance[orig], balance.get(dest, 0.0)  # merchants (M...) start at 0
    balance[orig] = round(ob - amount, 2)
    if typ != "CASH_OUT":  # cash-out leaves the system
        balance[dest] = round(od + amount, 2)
    rows.append((step, typ, amount, orig, ob, balance[orig], dest, od,
                 balance.get(dest, od), fraud))


# --- normal traffic ---------------------------------------------------------
for _ in range(N_NORMAL):
    o, d = random.sample(accts, 2)
    typ = random.choices(["PAYMENT", "TRANSFER", "CASH_OUT", "DEBIT"], [50, 20, 20, 10])[0]
    add(random.randint(1, HOURS), typ, random.lognormvariate(5, 1), o, d, 0)

# --- fraud 1: drain account then mule cashes out ----------------------------
for _ in range(40):
    victim, mule = random.sample(accts, 2)
    step = random.randint(1, HOURS - 2)
    amt = balance[victim]
    add(step, "TRANSFER", amt, victim, mule, 1)
    add(step + 1, "CASH_OUT", amt, mule, f"M{random.randint(1, 50):03d}", 1)

# --- fraud 2: rapid burst of small transfers --------------------------------
for _ in range(25):
    victim = random.choice(accts)
    step = random.randint(1, HOURS - 2)
    for _ in range(random.randint(6, 10)):
        add(step + random.choice([0, 0, 1]), "TRANSFER", random.uniform(20, 90), victim,
            random.choice(accts), 1)

# --- fraud 3: one abnormally large amount -----------------------------------
for _ in range(25):
    victim = random.choice(accts)
    balance[victim] += 200_000  # make sure funds exist
    add(random.randint(1, HOURS), "TRANSFER", random.uniform(150_000, 200_000), victim,
        random.choice(accts), 1)

rows.sort(key=lambda r: (r[0], r[3]))
con.executemany(
    """INSERT INTO transactions(step,type,amount,name_orig,old_bal_orig,new_bal_orig,
                                name_dest,old_bal_dest,new_bal_dest,is_fraud)
       VALUES (?,?,?,?,?,?,?,?,?,?)""", rows)
con.commit()
n, f = con.execute("SELECT COUNT(*), SUM(is_fraud) FROM transactions").fetchone()
print(f"Created {DB.name}: {n} transactions, {f} fraudulent ({f/n:.2%})")
