# PostgreSQL Observability Stack - Ubuntu Production Runbook

This runbook is for a production-style Ubuntu deployment where PostgreSQL runs on bare-metal servers and the observability tools run on one separate Ubuntu server.

It is not the Docker Desktop POC runbook. In production:

- PostgreSQL servers stay on bare metal.
- pgwatch, Grafana, pgBadger, and Nginx run on a dedicated observability server.
- pgwatch pulls metrics from PostgreSQL over SQL connections.
- Grafana reads metrics from the pgwatch metrics database.
- pgBadger reads PostgreSQL log files and generates HTML reports.
- Nginx publishes pgBadger reports.
- Grafana OSS Alerting sends alerts to Microsoft Teams.

## 1. Target Architecture

| Component | Location | Purpose |
|---|---|---|
| PostgreSQL primary | Bare-metal Ubuntu DB server | Production database |
| PostgreSQL standby | Bare-metal Ubuntu DB server | Streaming replica |
| Additional PostgreSQL instances | Bare-metal Ubuntu DB servers | Other databases or instances |
| pgwatch | Ubuntu observability server | Pull PostgreSQL metrics |
| pgwatch metrics DB | Ubuntu observability server | Store collected metrics |
| Grafana OSS | Ubuntu observability server | Dashboards and alerting |
| pgBadger | Ubuntu observability server | PostgreSQL log analysis |
| Nginx | Ubuntu observability server | Publish pgBadger HTML reports |

Flow:

```text
PostgreSQL servers -> pgwatch collector -> pgwatch metrics DB -> Grafana dashboards/alerts -> Microsoft Teams
PostgreSQL servers -> log collection -> pgBadger reports -> Nginx report site
```

Important distinction:

- pgwatch uses SQL connections to collect near-real-time metrics.
- pgBadger does not collect live metrics. It parses PostgreSQL logs and produces reports.

## 2. Contact Points and Ports

| Source | Destination | Port | Purpose |
|---|---|---:|---|
| Observability server | PostgreSQL servers | 5432 or custom PostgreSQL port | pgwatch metric collection |
| Observability server | PostgreSQL servers | 22 | log copy using rsync/scp/journalctl |
| Users/Admins | Grafana | 443 preferred, 3000 internal | dashboards and alerts |
| DBA/Admins | pgwatch UI | 8080 internal | source administration |
| Users/Admins | Nginx pgBadger site | 443 preferred, 8081 internal | pgBadger reports |

Restrict all admin surfaces to VPN, private subnet, SSO, or approved DBA/SRE networks.

## 3. Naming Multiple PostgreSQL Servers and Instances

Every monitored PostgreSQL endpoint must have a unique name. The endpoint is the combination of:

```text
hostname + port + database + role
```

For two servers, like the POC:

```text
pg-prod-primary-01:5432
pg-prod-standby-01:5432
```

For one Ubuntu server running multiple PostgreSQL instances:

```text
pg-db-01:5432
pg-db-01:5433
pg-db-01:5434
```

Recommended pgwatch source naming:

```text
<env>-<app>-<hostname>-p<port>-<role>-<database>
```

Examples:

```text
prod-erp-pg-prod-primary-01-p5432-primary-erpdb
prod-erp-pg-prod-standby-01-p5432-standby-erpdb
prod-crm-pg-db-01-p5432-primary-crmdb
prod-audit-pg-db-01-p5433-primary-auditdb
```

For multiple PostgreSQL instances on one server, keep these unique per instance:

| Item | Example instance A | Example instance B |
|---|---|---|
| Host | `pg-db-01` | `pg-db-01` |
| Port | `5432` | `5433` |
| Data directory | `/var/lib/postgresql/17/main` | `/pgdata/17-audit` |
| Log directory | `/var/lib/postgresql/17/main/log` | `/pgdata/17-audit/log` |
| pgwatch source | `prod-crm-pg-db-01-p5432-primary-crmdb` | `prod-audit-pg-db-01-p5433-primary-auditdb` |
| pgBadger report URL | `/pg-db-01-p5432/` | `/pg-db-01-p5433/` |

## 4. Prepare Each Bare-Metal PostgreSQL Server

Run these steps on each PostgreSQL server or instance.

### 4.1 Create a Monitoring Role

```sql
CREATE ROLE pgwatch_monitor
  LOGIN
  PASSWORD '<use-secret-store-generated-password>'
  CONNECTION LIMIT 10;

GRANT pg_monitor TO pgwatch_monitor;

GRANT CONNECT ON DATABASE <database_name> TO pgwatch_monitor;
```

Repeat `GRANT CONNECT` for every database that pgwatch should monitor.

### 4.2 Enable pg_stat_statements

In `postgresql.conf`:

```conf
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
track_io_timing = on
track_activity_query_size = 4096
```

Restart PostgreSQL during a maintenance window:

```bash
sudo systemctl restart postgresql
```

Create the extension in each monitored database:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 4.3 Restrict pg_hba.conf

Prefer TLS:

```conf
hostssl all pgwatch_monitor <OBSERVABILITY_SERVER_IP>/32 scram-sha-256
```

If TLS is not available yet and the network is private:

```conf
host all pgwatch_monitor <OBSERVABILITY_SERVER_IP>/32 scram-sha-256
```

Reload PostgreSQL:

```bash
sudo systemctl reload postgresql
```

### 4.4 Configure PostgreSQL Logging for pgBadger

In `postgresql.conf`:

```conf
logging_collector = on
log_destination = 'stderr'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '1GB'
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
deadlock_timeout = '1s'
log_temp_files = 0
log_autovacuum_min_duration = '10s'
```

Restart PostgreSQL if `logging_collector` changed:

```bash
sudo systemctl restart postgresql
```

## 5. Prepare the Ubuntu Observability Server

### 5.1 Install Base Packages

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release ufw chrony jq rsync nginx pgbadger
sudo systemctl enable --now chrony
sudo systemctl enable --now nginx
```

### 5.2 Install Docker Engine and Compose Plugin

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

### 5.3 Directory Layout

```bash
sudo mkdir -p /opt/postgres-observability/grafana/datasources
sudo mkdir -p /opt/postgres-observability/grafana/alerting
sudo mkdir -p /opt/postgres-observability/pgwatch
sudo mkdir -p /opt/postgres-observability/pgbadger
sudo mkdir -p /var/lib/pgbadger/incoming
sudo mkdir -p /var/www/pgbadger
sudo chown -R root:root /opt/postgres-observability
sudo chmod 0750 /opt/postgres-observability
sudo chown -R root:www-data /var/www/pgbadger
sudo chmod -R 0750 /var/www/pgbadger
```

## 6. Deploy pgwatch and Grafana

Use the upstream pgwatch production image or production compose pattern for long-running environments. Keep persistent storage for:

- pgwatch metrics database
- pgwatch configuration
- Grafana data
- Grafana datasource and alerting provisioning files

Do not reuse the local Docker Desktop POC compose as-is for production because it creates PostgreSQL containers. Production PostgreSQL servers are external bare-metal endpoints.

### 6.1 Grafana Datasource Provisioning

Create:

```bash
sudo vi /opt/postgres-observability/grafana/datasources/pg_ds.yml
```

Example:

```yaml
apiVersion: 1

datasources:
  - name: pgwatch metrics (postgres)
    uid: pgwatch-metrics
    type: postgres
    url: pgwatch-postgres:5432
    access: proxy
    user: pgwatch
    secureJsonData:
      password: '<pgwatch-metrics-password>'
    jsonData:
      database: pgwatch_metrics
      sslmode: disable
      postgresVersion: 1700
    isDefault: true
    editable: false
    version: 1
```

Important: `jsonData.database: pgwatch_metrics` is required for Grafana PostgreSQL datasource behavior in recent Grafana versions.

## 7. Register PostgreSQL Sources in pgwatch

Add one pgwatch source per PostgreSQL endpoint.

Examples:

| Source name | Host | Port | DB | Role |
|---|---|---:|---|---|
| `prod-erp-pg-prod-primary-01-p5432-primary-erpdb` | `pg-prod-primary-01.example.internal` | 5432 | `erpdb` | primary |
| `prod-erp-pg-prod-standby-01-p5432-standby-erpdb` | `pg-prod-standby-01.example.internal` | 5432 | `erpdb` | standby |
| `prod-crm-pg-db-01-p5432-primary-crmdb` | `pg-db-01.example.internal` | 5432 | `crmdb` | primary |
| `prod-audit-pg-db-01-p5433-primary-auditdb` | `pg-db-01.example.internal` | 5433 | `auditdb` | second instance on same host |

Connection string pattern:

```text
postgresql://pgwatch_monitor:<secret>@<host>:<port>/<database>?sslmode=require
```

Recommended source metadata:

```text
group = production
preset_config = full or tuned production preset
preset_config_standby = standby-compatible preset
enabled = true
```

## 8. Configure pgBadger Log Collection

Create host-specific incoming directories:

```bash
sudo mkdir -p /var/lib/pgbadger/incoming/pg-prod-primary-01
sudo mkdir -p /var/lib/pgbadger/incoming/pg-prod-standby-01
sudo mkdir -p /var/lib/pgbadger/incoming/pg-db-01-p5432
sudo mkdir -p /var/lib/pgbadger/incoming/pg-db-01-p5433
```

Example log copy:

```bash
rsync -az postgres@pg-prod-primary-01:/var/lib/postgresql/17/main/log/*.log \
  /var/lib/pgbadger/incoming/pg-prod-primary-01/
```

For one host with multiple PostgreSQL instances:

```bash
rsync -az postgres@pg-db-01:/var/lib/postgresql/17/main/log/*.log \
  /var/lib/pgbadger/incoming/pg-db-01-p5432/

rsync -az postgres@pg-db-01:/pgdata/17-audit/log/*.log \
  /var/lib/pgbadger/incoming/pg-db-01-p5433/
```

Create pgBadger script:

```bash
sudo vi /opt/postgres-observability/pgbadger/run-pgbadger.sh
```

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

HOSTS=(
  "pg-prod-primary-01"
  "pg-prod-standby-01"
  "pg-db-01-p5432"
  "pg-db-01-p5433"
)

for host in "${HOSTS[@]}"; do
  mkdir -p "/var/www/pgbadger/${host}"
  pgbadger \
    --quiet \
    --jobs 2 \
    --prefix '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ' \
    --outfile "/var/www/pgbadger/${host}/index.html" \
    /var/lib/pgbadger/incoming/${host}/*.log
done
```

Enable:

```bash
sudo chmod 0750 /opt/postgres-observability/pgbadger/run-pgbadger.sh
```

Schedule every 15 minutes:

```bash
sudo crontab -e
```

Add:

```cron
*/15 * * * * /opt/postgres-observability/pgbadger/run-pgbadger.sh >/var/log/pgbadger-refresh.log 2>&1
```

## 9. Configure Nginx for pgBadger Reports

Create:

```bash
sudo vi /etc/nginx/sites-available/pgbadger
```

Example:

```nginx
server {
    listen 80;
    server_name pgbadger.example.internal;

    root /var/www/pgbadger;
    index index.html;

    autoindex on;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Enable:

```bash
sudo ln -s /etc/nginx/sites-available/pgbadger /etc/nginx/sites-enabled/pgbadger
sudo nginx -t
sudo systemctl reload nginx
```

Production recommendation: put Nginx behind TLS, VPN, SSO, mTLS, or IP allow-listing. pgBadger reports may include SQL text and user/client details.

## 10. Phase 1 Alerting: Grafana OSS to Microsoft Teams

Grafana OSS Alerting is the recommended first alerting layer for this stack.

Alert flow:

```text
PostgreSQL servers -> pgwatch -> pgwatch_metrics DB -> Grafana alert rules -> Microsoft Teams
```

### 10.1 Create Microsoft Teams Workflow Webhook

1. Open Microsoft Teams.
2. Select the DBA/SRE alert channel.
3. Create a Workflow using **Post to a channel when a webhook request is received**.
4. Select the target Team and Channel.
5. Copy the generated webhook URL.
6. Store the URL in a secret store.

Do not commit the webhook URL into Git.

### 10.2 Configure Grafana Contact Point in UI

1. Open Grafana.
2. Go to **Alerting -> Contact points**.
3. Create contact point `ms-teams-dba-critical`.
4. Select integration type **Microsoft Teams**.
5. Paste the Teams Workflow webhook URL.
6. Click **Test**.
7. Confirm the Teams channel receives a test alert.
8. Save the contact point.

### 10.3 Provision Grafana Contact Point

Example files are included in this repository:

```text
grafana/alerting/teams-contact-point.example.yml
grafana/alerting/notification-policy.example.yml
grafana/alerting/postgres-alert-rule-sql-examples.md
```

Copy to Grafana provisioning path:

```bash
sudo cp grafana/alerting/teams-contact-point.example.yml /etc/grafana/provisioning/alerting/teams-contact-point.yml
sudo cp grafana/alerting/notification-policy.example.yml /etc/grafana/provisioning/alerting/notification-policy.yml
```

Set the Teams webhook URL as an environment variable for Grafana:

```bash
sudo systemctl edit grafana-server
```

Add:

```ini
[Service]
Environment="MS_TEAMS_WEBHOOK_URL=https://prod-teams-workflow-url"
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl restart grafana-server
```

Warning: provisioning notification policies replaces the Grafana notification policy tree for the organization. Export existing policies before applying in production.

### 10.4 Recommended First Alerts

| Alert | Starter condition | Severity |
|---|---|---|
| pgwatch metrics stale | no fresh `instance_up` sample for more than 5 minutes | critical |
| PostgreSQL instance down | latest availability signal unhealthy for 2 minutes | critical |
| too many sessions | sessions above 80 percent of `max_connections` for 5 minutes | warning/critical |
| waiting sessions / lock pressure | waiting sessions greater than 0 for 5 minutes | warning |
| replication lag high | lag above RPO threshold for 10 minutes | critical |
| long running query | active query age above 30 minutes | warning |
| abnormal DB growth | growth above baseline | warning |

Recommended alert labels:

```text
team=dba
env=prod
source=pgwatch
severity=critical
instance=prod-erp-pg-prod-primary-01-p5432-primary-erpdb
database=erpdb
```

### 10.5 Example Alert: Metrics Stale

Grafana datasource:

```text
pgwatch-metrics
```

SQL:

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

Labels:

```text
team=dba
env=prod
severity=critical
instance=prod-erp-pg-prod-primary-01-p5432-primary-erpdb
database=erpdb
```

### 10.6 Example Alert: Waiting Sessions

SQL:

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

## 11. How to Read pgwatch Metrics

| Area | Meaning | Action |
|---|---|---|
| Instance state / uptime | Primary/standby state and restart age | Check logs if uptime resets unexpectedly |
| TPS / QPS | Transaction and query throughput | Correlate drops/spikes with app events |
| Sessions by state | Active, idle, idle in transaction, waiting | Investigate idle in transaction and waiting sessions |
| Locks | Lock pressure and blockers | Identify blocking session/query |
| DB size | Database growth | Check bloat, ingest, retention, temp usage |
| WAL / replication | WAL generation and standby lag | Check network, storage, replication slots |
| pg_stat_statements | Top queries by runtime/calls | Tune high-impact queries |
| Cache / IO | Buffer hit and IO timing | Check scans, indexes, memory, storage |

## 12. How to Read pgBadger Reports

| Section | Meaning |
|---|---|
| Overview | Report period, log volume, session/query count |
| Slowest queries | Highest individual query duration |
| Most time consuming queries | Highest total accumulated time |
| Most frequent queries | Chatty application behavior |
| Temp files | Sort/hash spill or work_mem/index issues |
| Checkpoints | WAL/checkpoint/storage pressure |
| Locks/deadlocks | Blocking and concurrency problems |
| Connections | Pooling or application restart patterns |
| Errors | Application, permission, migration, or SQL issues |

Use pgwatch for live/near-real-time alerting. Use pgBadger for forensic evidence and SQL/log detail.

## 13. Validation Checklist

- Observability server can connect to every PostgreSQL endpoint using `pgwatch_monitor`.
- `pg_hba.conf` allows only the observability server for the monitoring user.
- `pg_stat_statements` is enabled on monitored databases.
- pgwatch source names are unique and include host, port, role, and database.
- Grafana datasource test succeeds.
- Grafana dashboard shows active and standby metrics.
- Teams contact point test succeeds.
- At least one test alert reaches Microsoft Teams.
- pgBadger job generates reports per server/instance.
- Nginx serves pgBadger reports only to approved users/networks.
- Backups exist for Grafana dashboards, pgwatch config, and pgwatch metrics.

## 14. Security Notes

- Store all passwords and Teams webhook URLs outside Git.
- Use TLS for PostgreSQL monitoring connections where possible.
- Restrict Grafana, pgwatch UI, and pgBadger reports to approved networks.
- Treat pgBadger reports as sensitive because they can include SQL text, users, clients, and errors.
- Use least-privilege roles.
- Keep OS, Docker, Grafana, pgwatch, and pgBadger patched.

## 15. Rollback

- Disable a pgwatch source if collection causes unexpected load.
- Raise `log_min_duration_statement` if logs become too noisy.
- Restore previous Grafana datasource/alerting provisioning if alert changes misbehave.
- Remove `pg_stat_statements` only during a maintenance window because it requires PostgreSQL restart.

## 16. References

- pgwatch: https://github.com/cybertec-postgresql/pgwatch
- Grafana Alerting: https://grafana.com/docs/grafana/latest/alerting/
- Grafana alert provisioning: https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/
- Grafana PostgreSQL datasource: https://grafana.com/docs/grafana/latest/datasources/postgres/
- pgBadger: https://github.com/darold/pgbadger
