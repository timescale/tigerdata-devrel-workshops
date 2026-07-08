#!/usr/bin/env bash
# Runs automatically on every devcontainer start (postStartCommand). Also
# re-run manually any time you edit mqtt-to-dashboard/.env, to apply changes:
#   bash .devcontainer/mqtt-to-dashboard/scripts/reload-grafana-env.sh
#
# We deliberately don't use `service grafana-server start`/systemd:
#   1. GF_*-style env vars (e.g. for ${TIGER_HOST} substitution in
#      grafana/provisioning/datasources/tigercloud.yml) only reach Grafana if
#      they're in ITS process environment. The packaged init.d script sources
#      /etc/default/grafana-server but never `export`s what it reads, so those
#      vars never make it to the exec'd process — confirmed by testing.
#   2. The init.d script also has a hard-coded 1-second wait before checking
#      Grafana wrote its pidfile, which is too short and reports "failed!"
#      even when Grafana is starting up fine.
# So we launch grafana-server ourselves, with the right env vars, and confirm
# it's actually up via its health endpoint instead of trusting an exit code.
set -euo pipefail

WORKSHOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/mqtt-to-dashboard"
ENV_FILE="$WORKSHOP_DIR/.env"

echo "==> Stopping any Grafana instance already running"
sudo pkill -f '/usr/share/grafana/bin/grafana server' 2>/dev/null || true
sleep 1

# Pull the Tiger Cloud / Grafana admin values out of .env, if it exists yet,
# as a set of NAME=value pairs we can hand straight to `env`.
ENV_ARGS=()
GRAFANA_ADMIN_PASSWORD=""
if [ -f "$ENV_FILE" ]; then
  echo "==> Found $ENV_FILE — loading TIGER_* into Grafana's environment"
  while IFS='=' read -r key value; do
    ENV_ARGS+=("$key=$value")
  done < <(grep -E '^(TIGER_HOST|TIGER_PORT|TIGER_DATABASE|TIGER_USER|TIGER_PASSWORD)=' "$ENV_FILE")
  GRAFANA_ADMIN_PASSWORD="$(grep '^GRAFANA_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"
else
  echo "==> No $ENV_FILE yet — starting Grafana with defaults (admin/admin, no Tiger Cloud connection)."
  echo "    Re-run this script after 'cp .env.example .env' and filling it in."
fi

echo "==> Starting Grafana"
sudo runuser -u grafana -- env "${ENV_ARGS[@]}" nohup /usr/share/grafana/bin/grafana server \
  --homepath=/usr/share/grafana \
  --config=/etc/grafana/grafana.ini \
  --packaging=deb \
  cfg:default.paths.provisioning=/etc/grafana/provisioning \
  cfg:default.paths.data=/var/lib/grafana \
  cfg:default.paths.logs=/var/log/grafana \
  cfg:default.paths.plugins=/var/lib/grafana/plugins \
  >>/var/log/grafana/grafana.log 2>&1 &
disown

echo "==> Waiting for Grafana to report healthy..."
healthy=false
for _ in $(seq 1 30); do
  if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep 1
done

if [ "$healthy" != true ]; then
  echo "==> Grafana did not become healthy within 30s — check /var/log/grafana/grafana.log" >&2
  exit 1
fi
echo "==> Grafana is up on http://localhost:3000"

if [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo "==> Applying GRAFANA_ADMIN_PASSWORD from .env"
  sudo runuser -u grafana -- /usr/share/grafana/bin/grafana cli \
    --homepath /usr/share/grafana \
    --config /etc/grafana/grafana.ini \
    --configOverrides "cfg:default.paths.data=/var/lib/grafana" \
    admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" >/dev/null
fi
