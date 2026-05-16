#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -v db_name="$POSTGRES_DB" \
  -v pgwatch_user="${PGWATCH_USER:-pgwatch}" \
  -v pgwatch_password="${PGWATCH_PASSWORD:-pgwatch_password}" \
  -v replication_user="${REPLICATION_USER:-replicator}" \
  -v replication_password="${REPLICATION_PASSWORD:-replicator_password}" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT format('CREATE ROLE %I WITH LOGIN PASSWORD %L', :'pgwatch_user', :'pgwatch_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'pgwatch_user') \gexec

SELECT format('CREATE ROLE %I WITH REPLICATION LOGIN PASSWORD %L', :'replication_user', :'replication_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'replication_user') \gexec

GRANT pg_monitor TO :"pgwatch_user";
GRANT pg_read_all_stats TO :"pgwatch_user";
GRANT CONNECT ON DATABASE :"db_name" TO :"pgwatch_user";

SELECT pg_create_physical_replication_slot('passive_slot')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_replication_slots WHERE slot_name = 'passive_slot'
);

CREATE TABLE IF NOT EXISTS poc_orders (
  id bigserial PRIMARY KEY,
  customer_id integer NOT NULL,
  amount numeric(12,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
SQL
