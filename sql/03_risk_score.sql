-- Combine the rules into one risk score per transaction and measure how well it works.
DROP VIEW IF EXISTS txn_flags;
CREATE VIEW txn_flags AS
WITH w AS (
    SELECT t.*,
           step - LAG(step, 2) OVER o                                         AS span_3txns,
           AVG(amount) OVER (PARTITION BY name_orig ORDER BY step, txn_id
                             ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS avg_before
    FROM transactions t
    WINDOW o AS (PARTITION BY name_orig ORDER BY step, txn_id)
)
SELECT txn_id, name_orig, type, amount, is_fraud,
       COALESCE(span_3txns <= 1 AND type = 'TRANSFER', 0)                    AS f_velocity,
       (avg_before IS NOT NULL AND amount > 10 * avg_before AND amount > 50000) AS f_spike,
       (type IN ('TRANSFER','CASH_OUT') AND old_bal_orig > 0 AND new_bal_orig = 0
        AND amount > 1000)                                                    AS f_drain
FROM w;

-- name: Flag counts and precision / recall against the ground-truth label
WITH scored AS (
    SELECT *, f_velocity + f_spike + f_drain AS risk_score FROM txn_flags
)
SELECT risk_score >= 1                          AS flagged,
       COUNT(*)                                 AS txns,
       SUM(is_fraud)                            AS fraud_caught,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 1) AS precision_pct
FROM scored GROUP BY 1 ORDER BY 1 DESC;

-- name: Recall: share of all fraud that was flagged
SELECT ROUND(100.0 * SUM(f_velocity + f_spike + f_drain >= 1) / COUNT(*), 1) AS recall_pct
FROM txn_flags WHERE is_fraud = 1;
