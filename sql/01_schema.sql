-- PaySim-style schema. `step` = 1 hour of simulated time.
CREATE TABLE transactions (
    txn_id        INTEGER PRIMARY KEY,
    step          INTEGER NOT NULL,
    type          TEXT    NOT NULL,   -- PAYMENT, TRANSFER, CASH_OUT, DEBIT
    amount        REAL    NOT NULL,
    name_orig     TEXT    NOT NULL,
    old_bal_orig  REAL,
    new_bal_orig  REAL,
    name_dest     TEXT    NOT NULL,
    old_bal_dest  REAL,
    new_bal_dest  REAL,
    is_fraud      INTEGER NOT NULL DEFAULT 0   -- ground-truth label (for evaluation only)
);
