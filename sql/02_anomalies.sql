-- Anomaly detection with window functions. Each query is separated by a
-- "-- name:" header so run.py can execute and print them one by one.

-- name: 1. Running balance of spending per account (SUM OVER) - top 5 biggest spenders
SELECT name_orig, step, type, amount,
       ROUND(SUM(amount) OVER (PARTITION BY name_orig ORDER BY step, txn_id), 2) AS running_total
FROM transactions
WHERE name_orig IN (SELECT name_orig FROM transactions GROUP BY name_orig
                    ORDER BY SUM(amount) DESC LIMIT 1)
ORDER BY step, txn_id
LIMIT 5;

-- name: 2. Velocity (LAG): 3+ transactions by same account within 1 hour-step of each other
WITH gaps AS (
    SELECT txn_id, name_orig, step, amount,
           step - LAG(step, 2) OVER (PARTITION BY name_orig ORDER BY step, txn_id) AS span_3txns
    FROM transactions
)
SELECT name_orig, COUNT(*) AS flagged_txns, ROUND(SUM(amount), 2) AS total_amount
FROM gaps WHERE span_3txns <= 1
GROUP BY name_orig ORDER BY flagged_txns DESC LIMIT 5;

-- name: 3. Amount spike vs the account's own history (rolling AVG, previous rows only)
WITH hist AS (
    SELECT txn_id, name_orig, step, amount,
           AVG(amount) OVER (PARTITION BY name_orig ORDER BY step, txn_id
                             ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS avg_before
    FROM transactions
)
SELECT txn_id, name_orig, amount, ROUND(avg_before, 2) AS avg_before,
       ROUND(amount / avg_before, 1) AS x_normal
FROM hist WHERE avg_before IS NOT NULL AND amount > 10 * avg_before AND amount > 50000
ORDER BY x_normal DESC LIMIT 5;

-- name: 4. Mule pattern (LEAD): TRANSFER in, same amount CASH_OUT by the receiver next hour
WITH events AS (            -- one row per account per money movement (in or out)
    SELECT name_dest AS account, step, txn_id, 'IN_' || type AS kind, amount FROM transactions
    UNION ALL
    SELECT name_orig,            step, txn_id, 'OUT_' || type,        amount FROM transactions
),
seq AS (
    SELECT account, step, kind, amount,
           LEAD(kind)   OVER w AS next_kind,
           LEAD(amount) OVER w AS next_amount,
           LEAD(step)   OVER w AS next_step
    FROM events
    WINDOW w AS (PARTITION BY account ORDER BY step, txn_id, kind)
)
SELECT account AS mule, step, amount, next_step - step AS hours_to_cashout
FROM seq
WHERE kind = 'IN_TRANSFER' AND next_kind = 'OUT_CASH_OUT'
  AND next_amount = amount AND next_step - step <= 2
ORDER BY amount DESC LIMIT 5;

-- name: 5. Account drained to zero in one transaction (balance check)
SELECT type, COUNT(*) AS n, ROUND(AVG(amount), 2) AS avg_amount
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT') AND old_bal_orig > 0 AND new_bal_orig = 0
GROUP BY type;
