param(
    [int]$Rows = 100000,
    [int]$SlowSeconds = 3
)

$sql = @"
INSERT INTO poc_orders (customer_id, amount)
SELECT
  (random() * 10000)::integer,
  (random() * 1000)::numeric(12,2)
FROM generate_series(1, $Rows);

SELECT customer_id, count(*), sum(amount)
FROM poc_orders
GROUP BY customer_id
ORDER BY sum(amount) DESC
LIMIT 20;

SELECT pg_sleep($SlowSeconds);
"@

$sql | docker compose exec -T postgres-active psql -U postgres -d observability_demo -f -
