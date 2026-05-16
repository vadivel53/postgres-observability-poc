# PostgreSQL Observability POC

This project provides a local Docker Desktop POC for a production-style PostgreSQL observability stack:

- PostgreSQL 17 active node
- PostgreSQL 17 passive streaming replica
- pgwatch with Grafana dashboards
- pgBadger log analysis
- Nginx report publishing
- GitHub Codespaces support

The design follows the referenced production guide: monitoring components are separate from database nodes, pgwatch is used for live monitoring, and pgBadger is used for PostgreSQL log forensics.

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

### 4. Verify Active/Passive Replication

```powershell
.\scripts\check-poc.ps1
```

Expected result:

- active node shows a replication connection
- passive node returns `pg_is_in_recovery = true`
- `pg_stat_statements` is available

### 5. Open the UIs

| Tool | URL | Purpose |
|---|---|---|
| Grafana | http://localhost:3000 | pgwatch dashboards |
| pgwatch Admin UI | http://localhost:8080 | Add monitored databases |
| pgBadger Reports | http://localhost:8081 | View HTML reports through Nginx |

Grafana default login:

```text
User: admin
Password: pgwatchadmin
```

### 6. Add PostgreSQL Nodes to pgwatch

Open the pgwatch Admin UI:

```text
http://localhost:8080
```

Add two sources.

Active source:

```text
Name: postgres-active
Group: poc
Connection string: postgresql://pgwatch:pgwatch_password@postgres-active:5432/observability_demo?sslmode=disable
Preset metrics: exhaustive
Enabled: true
```

Passive source:

```text
Name: postgres-passive
Group: poc
Connection string: postgresql://pgwatch:pgwatch_password@postgres-passive:5432/observability_demo?sslmode=disable
Preset metrics: exhaustive
Enabled: true
```

Wait up to two minutes for pgwatch to collect metrics, then open Grafana.

### 7. Generate Test Load

```powershell
.\scripts\generate-load.ps1 -Rows 100000 -SlowSeconds 3
```

This inserts sample rows, runs an aggregate query, and creates one slow query for log analysis.

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

### 9. Useful Checks

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

### 10. Stop the Stack

Stop containers and keep data:

```powershell
docker compose down
```

Stop containers and remove all POC data:

```powershell
docker compose down -v
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
