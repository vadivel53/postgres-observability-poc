docker compose ps

Write-Host ""
Write-Host "Replication status from active node:"
docker compose exec -T postgres-active psql -U postgres -d observability_demo -c "SELECT application_name, state, sync_state, replay_lsn FROM pg_stat_replication;"

Write-Host ""
Write-Host "Passive recovery status:"
docker compose exec -T postgres-passive psql -U postgres -d observability_demo -c "SELECT pg_is_in_recovery();"

Write-Host ""
Write-Host "pg_stat_statements sample:"
docker compose exec -T postgres-active psql -U postgres -d observability_demo -c "SELECT query, calls FROM pg_stat_statements ORDER BY calls DESC LIMIT 5;"
