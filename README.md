# PostgreSQL Observability POC

This project provides a local Docker Desktop POC for a production-style PostgreSQL observability stack:

- PostgreSQL 17 active node
- PostgreSQL 17 passive streaming replica
- pgwatch with Grafana dashboards
- pgBadger log analysis
- Nginx report publishing
- GitHub Codespaces support

The design follows the referenced production guide: monitoring components are separate from database nodes, pgwatch is used for live monitoring, and pgBadger is used for PostgreSQL log forensics.

## Service Map

| Service | Local URL / Port | Purpose |
|---|---:|---|
| PostgreSQL active | `localhost:5432` | Primary PostgreSQL 17 database |
| PostgreSQL passive | `localhost:5433` | Streaming read replica |
| Grafana | http://localhost:3000 | pgwatch metrics dashboards |
| pgwatch Admin UI | http://localhost:8080 | pgwatch source/config administration |
| pgBadger reports via Nginx | http://localhost:8081 | Static HTML PostgreSQL log reports |

Nginx is used only for publishing pgBadger HTML reports. Grafana is served by the pgwatch demo container on port `3000`.

## Local Runbook

### 1. Prerequisites

Install:

- Docker Desktop
- Git
- PowerShell

Recommended Docker Desktop resources:

- 4 CPUs
- 8 GB memory
- 20 GB free disk

### 2. Prepare Environment

From the project folder:

```powershell
Copy-Item .env.example .env
```

The default credentials are POC-only. Change `.env` before sharing the stack outside a local lab.

### 3. Start the Stack

```powershell
docker compose up -d
```

Expected containers:

- `pgobs-postgres-active`
- `pgobs-postgres-passive`
- `pgobs-pgwatch`
- `pgobs-nginx`

### 4. Verify Deployment Health

```powershell
.\scripts\check-poc.ps1
```

Expected result:

- active node shows a replication connection
- passive node returns `pg_is_in_recovery = true`
- `pg_stat_statements` is available
- pgwatch/Grafana container is running

You can also check containers directly:

```powershell
docker compose ps
```

### 5. Open the UIs

| Tool | URL | Purpose |
|---|---|---|
| Grafana | http://localhost:3000 | pgwatch dashboards |
| pgwatch Admin UI | http://localhost:8080 | pgwatch source/config administration |
| pgBadger Reports | http://localhost:8081 | View HTML reports through Nginx |

Grafana default login:

```text
User: admin
Password: pgwatchadmin
```

### 6. pgwatch and Grafana Configuration

The stack automatically registers both PostgreSQL nodes in pgwatch during first startup:

| Source | Role | Connection |
|---|---|---|
| `postgres-active` | primary | `postgres-active:5432/observability_demo` |
| `postgres-passive` | replica | `postgres-passive:5432/observability_demo` |

The bundled pgwatch sample source is disabled automatically.

Grafana is provisioned with the `pgwatch-metrics` datasource from:

```text
grafana/datasources/pg_ds.yml
```

This file sets both the datasource database and the Grafana PostgreSQL plugin default database to `pgwatch_metrics`. This is required for Grafana 12 panels to render metrics correctly.

Wait one to two minutes after startup for pgwatch to collect the first metrics, then open:

```text
http://localhost:3000/d/db-overview/2-database-overview?var-dbname=postgres-active&var-agg_interval=5m&var-lag_interval=1d&orgId=1&from=now-3h&to=now&timezone=browser
```

### 7. Generate Test Load

```powershell
.\scripts\generate-load.ps1 -Rows 100000 -SlowSeconds 3
```

This inserts sample rows, runs an aggregate query, and creates one slow query for log analysis.

After generating load, refresh Grafana. The Database Overview dashboard should show values such as instance state, uptime, TPS, QPS, query runtime, database size change, and insert/update/delete rates.

### 8. Generate pgBadger Reports

```powershell
docker compose --profile reports run --rm pgbadger
```

Open:

```text
http://localhost:8081
```

Reports:

- `active-latest.html`
- `passive-latest.html`

### 9. Metrics Validation

Confirm that pgwatch is collecting metric streams for both databases:

```powershell
docker compose exec -T pgwatch psql -U postgres -d pgwatch_metrics -c "SELECT dbname, count(*) AS metric_streams FROM admin.all_distinct_dbname_metrics WHERE dbname IN ('postgres-active','postgres-passive') GROUP BY dbname ORDER BY dbname;"
```

Expected result:

```text
postgres-active  - metric streams present
postgres-passive - metric streams present
```

Confirm that Grafana can query the datasource:

```powershell
$pair='admin:pgwatchadmin'
$b64=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$body = @{queries=@(@{refId='A';datasource=@{uid='pgwatch-metrics';type='grafana-postgresql-datasource'};rawSql="SELECT dbname, count(*) AS rows, max(time) AS latest FROM instance_up WHERE dbname IN ('postgres-active','postgres-passive') GROUP BY dbname ORDER BY dbname";format='table';datasourceId=1;intervalMs=1000;maxDataPoints=100});from='now-3h';to='now'} | ConvertTo-Json -Depth 8
Invoke-RestMethod -Method Post -UseBasicParsing -Headers @{Authorization="Basic $b64";'Content-Type'='application/json'} -Body $body http://localhost:3000/api/ds/query
```

The response should include both `postgres-active` and `postgres-passive`.

### 10. Useful Checks

List containers:

```powershell
docker compose ps
```

Connect to active PostgreSQL:

```powershell
docker compose exec postgres-active psql -U postgres -d observability_demo
```

Connect to passive PostgreSQL:

```powershell
docker compose exec postgres-passive psql -U postgres -d observability_demo
```

Check replication from active:

```sql
SELECT application_name, state, sync_state, replay_lsn
FROM pg_stat_replication;
```

Check passive mode:

```sql
SELECT pg_is_in_recovery();
```

Check slow statements:

```sql
SELECT query, calls, mean_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### 11. Stop the Stack

Stop containers and keep data:

```powershell
docker compose down
```

Stop containers and remove all POC data:

```powershell
docker compose down -v
```

### 12. Rebuild or Reset

After changing datasource provisioning, compose files, or container configuration, recreate pgwatch/Grafana:

```powershell
docker compose up -d pgwatch
```

For a clean POC reset:

```powershell
docker compose down -v
docker compose up -d
.\scripts\generate-load.ps1 -Rows 100000 -SlowSeconds 3
```

## GitHub Codespaces Runbook

### 1. Open in Codespaces

After the repository is pushed to GitHub:

1. Open the repository in GitHub.
2. Select **Code**.
3. Select **Codespaces**.
4. Create a new Codespace.

### 2. Start the Stack

Inside the Codespace terminal:

```bash
cp -n .env.example .env
docker compose up -d
```

The same automatic pgwatch source registration and Grafana datasource provisioning are used in Codespaces.

### 3. Open Forwarded Ports

Codespaces will forward:

- `3000` for Grafana
- `8080` for pgwatch Admin UI
- `8081` for pgBadger reports
- `5432` for active PostgreSQL
- `5433` for passive PostgreSQL

Use the **Ports** tab to open each service in a browser.

### 4. Generate Load and Reports

```bash
pwsh ./scripts/generate-load.ps1 -Rows 100000 -SlowSeconds 3
docker compose --profile reports run --rm pgbadger
```

If PowerShell is not available in the Codespace, install it or run equivalent SQL manually through `psql`.

### 5. Codespaces Validation

Open the forwarded Grafana port and use the Database Overview dashboard with:

```text
var-dbname=postgres-active
```

If a dashboard opens without data, wait one to two minutes, refresh the page, and confirm that the `pgwatch-metrics` datasource has `pgwatch_metrics` set as its default database.

## Production Notes

This repository is a POC. Before production:

- replace default passwords
- restrict `pg_hba.conf` to the monitoring subnet
- use SCRAM-SHA-256 credentials from a secret store
- configure TLS where required
- use dedicated storage for metrics and PostgreSQL logs
- define metrics and log retention policies
- back up Grafana dashboards, pgwatch configuration, and pgBadger reports
- avoid exposing PostgreSQL or pgwatch admin ports publicly

## References

- pgwatch Docker documentation: https://pgwat.ch/latest/tutorial/docker_installation.html
- pgwatch GitHub project: https://github.com/cybertec-postgresql/pgwatch
- PostgreSQL Docker image: https://hub.docker.com/_/postgres
