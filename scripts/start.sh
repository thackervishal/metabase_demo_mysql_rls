#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$DEMO_ROOT"

if [[ ! -f .env ]]; then
  echo "No .env file found. Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

set -a; source .env; set +a

if ! docker info >/dev/null 2>&1; then
  echo "Docker not running — starting Docker Desktop..."
  "/c/Program Files/Docker/Docker/Docker Desktop.exe" &>/dev/null &
  until docker info >/dev/null 2>&1; do sleep 3; done && echo "Docker Desktop ready."
fi

echo "Starting databases..."
docker compose up -d mysql app-db

echo "Waiting for MySQL to be ready..."
attempt=0
until [[ $(docker inspect --format='{{.State.Health.Status}}' "$(docker compose ps -q mysql)") == "healthy" ]]; do
  attempt=$((attempt + 1))
  echo "MySQL not ready — retrying in 10 seconds (attempt $attempt/30)..."
  [[ $attempt -ge 30 ]] && { echo "MySQL did not become healthy in time." >&2; exit 1; }
  sleep 10
done

if [[ ! -f "$DEMO_ROOT/.mysql-seeded" ]]; then
  echo "Applying MySQL RLS setup..."
  docker compose exec -T mysql mysql -h 127.0.0.1 -u root -pmetasample123 sample \
    <"$DEMO_ROOT/seed/mysql-rls.sql"
  touch "$DEMO_ROOT/.mysql-seeded"
else
  echo "MySQL RLS already applied — skipping (delete .mysql-seeded to force re-run)."
fi

echo "Starting Metabase..."
docker compose up -d metabase

echo "Waiting for Metabase to be ready..."
attempt=0
until curl -fs "http://127.0.0.1:${METABASE_PORT:-3300}/api/health" 2>/dev/null | grep -q '"status":"ok"'; do
  attempt=$((attempt + 1))
  echo "Metabase not ready — retrying in 10 seconds (attempt $attempt/30)..."
  [[ $attempt -ge 30 ]] && { echo "Metabase did not become ready in time." >&2; exit 1; }
  sleep 10
done

echo "Seeding Metabase..."
bash "$DEMO_ROOT/seed/seed-metabase.sh"

echo ""
echo "------------------------------------------------------------"
echo "  Demo ready"
echo "------------------------------------------------------------"
echo "  Metabase        http://localhost:${METABASE_PORT:-3300}"
echo "  MySQL           localhost:3366  db=sample"
echo "                  metabase  /  metasample123"
echo ""
echo "  admin@example.com   metabot1  (superuser, no impersonation)"
echo "  bruce@example.com   metabot1  → h_role_bruce → f_role_analytics_team  (all 50 states)"
echo "  thor@example.com    metabot1  → h_role_thor  → f_role_sales_east_coast (25 states)"
echo "  frodo@example.com   metabot1  → h_role_frodo → f_role_sales_west_coast (25 states)"
echo "------------------------------------------------------------"
