FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbadger ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY run_pgbadger.sh /usr/local/bin/run_pgbadger.sh
RUN chmod +x /usr/local/bin/run_pgbadger.sh

ENTRYPOINT ["/usr/local/bin/run_pgbadger.sh"]
