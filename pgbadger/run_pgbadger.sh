#!/usr/bin/env bash
set -euo pipefail

ACTIVE_LOG_DIR="${ACTIVE_LOG_DIR:-/pgdata-active/log}"
PASSIVE_LOG_DIR="${PASSIVE_LOG_DIR:-/pgdata-passive/log}"
REPORT_DIR="${REPORT_DIR:-/reports}"

mkdir -p "$REPORT_DIR"

generate_report() {
  local node_name="$1"
  local log_dir="$2"
  local output="$REPORT_DIR/${node_name}-latest.html"

  if compgen -G "$log_dir/*.log" >/dev/null; then
    pgbadger "$log_dir"/*.log -o "$output"
  else
    cat > "$output" <<HTML
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>${node_name} pgBadger report</title></head>
  <body>
    <h1>${node_name} pgBadger report</h1>
    <p>No PostgreSQL log files were found yet. Generate database activity, then run the report command again.</p>
  </body>
</html>
HTML
  fi
}

generate_report "active" "$ACTIVE_LOG_DIR"
generate_report "passive" "$PASSIVE_LOG_DIR"

cat > "$REPORT_DIR/index.html" <<HTML
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>PostgreSQL pgBadger Reports</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 40px; color: #17202a; }
      a { display: block; margin: 12px 0; font-size: 18px; }
      .stamp { color: #566573; margin-top: 24px; }
    </style>
  </head>
  <body>
    <h1>PostgreSQL pgBadger Reports</h1>
    <a href="./active-latest.html">Active PostgreSQL report</a>
    <a href="./passive-latest.html">Passive PostgreSQL report</a>
    <p class="stamp">Generated at $(date -u +"%Y-%m-%d %H:%M:%S UTC")</p>
  </body>
</html>
HTML

echo "pgBadger reports generated in $REPORT_DIR"
