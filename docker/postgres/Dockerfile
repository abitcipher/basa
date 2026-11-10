# PostgreSQL 18 + PostGIS 3.6 + pgvector (btree_gist ships with Postgres contrib)
FROM postgis/postgis:18-3.6
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-18-pgvector \
 && rm -rf /var/lib/apt/lists/*
COPY init-extensions.sql /docker-entrypoint-initdb.d/20-extensions.sql
