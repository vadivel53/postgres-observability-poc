# PostgreSQL Grafana OSS Alert Rule SQL Examples

Use these queries with Grafana-managed alert rules against the `pgwatch-metrics`
PostgreSQL datasource. Adjust table/JSON fields if your pgwatch version stores a
metric under a different name.

Recommended labels for every rule:

```text
team=dba
env=prod
source=pgwatch
severity=warning or critical
instance=<pgwatch source name>
database=<database name>
```

## PostgreSQL Metrics Stale

Purpose: alert when pgwatch has not stored recent `instance_up` samples.

```sql
SELECT
  EXTRACT(EPOCH FROM (now() - max(time)))::int AS seconds_since_last_sample
FROM instance_up
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb';
```

Condition:

```text
WHEN last() OF A IS ABOVE 300 FOR 5m
```

## PostgreSQL Instance Down

Purpose: alert when the latest `instance_up` value is not healthy.

```sql
SELECT
  COALESCE((data->>'epoch_ns')::bigint, 0) AS instance_up_value
FROM instance_up
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb'
ORDER BY time DESC
LIMIT 1;
```

Condition:

```text
WHEN last() OF A IS BELOW 1 FOR 2m
```

If your pgwatch version stores `instance_up` differently, use the stale metrics
alert as the primary availability signal.

## Too Many PostgreSQL Sessions

Purpose: alert when session count is approaching `max_connections`.

```sql
SELECT
  COALESCE((data->>'total')::int, 0) AS total_sessions
FROM backends
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb'
ORDER BY time DESC
LIMIT 1;
```

Condition:

```text
WHEN last() OF A IS ABOVE 150 FOR 5m
```

Set the threshold according to each instance's `max_connections`.

## Waiting Sessions / Lock Pressure

Purpose: alert when lock or wait pressure persists.

```sql
SELECT
  COALESCE((data->>'waiting')::int, 0) AS waiting_sessions
FROM backends
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb'
ORDER BY time DESC
LIMIT 1;
```

Condition:

```text
WHEN last() OF A IS ABOVE 0 FOR 5m
```

## Replication Lag

Purpose: alert when standby lag is too high.

```sql
SELECT
  COALESCE((data->>'lag_b')::bigint, 0) AS lag_bytes
FROM replication
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb'
ORDER BY time DESC
LIMIT 1;
```

Condition:

```text
WHEN last() OF A IS ABOVE 1073741824 FOR 10m
```

This example uses 1 GiB. Tune it per RPO/RTO.

## Long Running Queries

Purpose: alert when active query runtime is too high.

```sql
SELECT
  COALESCE(max((data->>'state_age_s')::int), 0) AS max_query_age_seconds
FROM stat_activity
WHERE dbname = 'prod-erp-pg-prod-primary-01-p5432-primary-erpdb'
  AND data->>'state' = 'active'
  AND time > now() - interval '5 minutes';
```

Condition:

```text
WHEN last() OF A IS ABOVE 1800 FOR 5m
```

This example alerts for active queries older than 30 minutes.
