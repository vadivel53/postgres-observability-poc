#!/bin/bash
set -e

# Add active/passive PostgreSQL sources for pgwatch monitoring.
# This script is executed during the pgwatch container's initial database setup.
psql -v ON_ERROR_STOP=1 -U postgres -d pgwatch <<'EOSQL'
INSERT INTO pgwatch.source (name, preset_config, preset_config_standby, connstr, "group", dbtype, is_enabled)
VALUES
  ('postgres-active', 'full', 'full', 'postgresql://pgwatch:pgwatch_password@postgres-active:5432/observability_demo?sslmode=disable', 'poc', 'postgres', true),
  ('postgres-passive', 'full', 'full', 'postgresql://pgwatch:pgwatch_password@postgres-passive:5432/observability_demo?sslmode=disable', 'poc', 'postgres', true)
ON CONFLICT (name) DO UPDATE
  SET connstr = EXCLUDED.connstr,
      preset_config = EXCLUDED.preset_config,
      preset_config_standby = EXCLUDED.preset_config_standby,
      "group" = EXCLUDED."group",
      dbtype = EXCLUDED.dbtype,
      is_enabled = EXCLUDED.is_enabled;

UPDATE pgwatch.source
SET is_enabled = false
WHERE name = 'test';
EOSQL