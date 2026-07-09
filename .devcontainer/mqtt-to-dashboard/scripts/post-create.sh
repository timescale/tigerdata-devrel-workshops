#!/usr/bin/env bash
# postCreateCommand for the mqtt-to-dashboard workshop devcontainer. Runs once,
# when the container is first created. Installs everything natively — no
# Docker-in-Docker, no docker-compose. Tiger Cloud (hosted TimescaleDB) is
# remote, so there's no local database to run either.
#
# Grafana itself is NOT started here — scripts/reload-grafana-env.sh (run via
# postStartCommand) launches it directly, since that's also how it picks up
# .env values for datasource provisioning. See that script for why we don't
# use `service grafana-server start`/systemd here.
set -euo pipefail

WORKSHOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/mqtt-to-dashboard"

echo "==> Installing psql"
sudo apt-get update
sudo apt-get install -y postgresql-client

echo "==> Adding Grafana's official apt repo and installing grafana"
sudo apt-get install -y apt-transport-https wget gnupg
sudo mkdir -p /etc/apt/keyrings
sudo wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

echo "==> Making Grafana's log writable (reload-grafana-env.sh runs it as a plain user,"
echo "    and the redirect into this file is set up before its 'sudo -u grafana' applies)"
sudo touch /var/log/grafana/grafana.log
sudo chmod 666 /var/log/grafana/grafana.log

echo "==> Pointing Grafana's provisioning at this repo (so edits here take effect)"
sudo rm -rf /etc/grafana/provisioning/dashboards /etc/grafana/provisioning/datasources
sudo ln -s "$WORKSHOP_DIR/grafana/provisioning/dashboards"  /etc/grafana/provisioning/dashboards
sudo ln -s "$WORKSHOP_DIR/grafana/provisioning/datasources" /etc/grafana/provisioning/datasources

echo "==> Baseline Grafana config: anonymous Viewer access, and skip Grafana's"
echo "    bundled-plugin auto-install (we only need the built-in Postgres"
echo "    datasource for Tiger Cloud, and a room full of attendees don't need"
echo "    to all download ~280MB of unused plugins on first boot)"
sudo tee -a /etc/grafana/grafana.ini >/dev/null <<'EOF'

[auth.anonymous]
enabled = true
org_role = Viewer

[plugins]
preinstall_disabled = true
EOF

echo "==> Installing consumer Python deps"
pip install --user -r "$WORKSHOP_DIR/consumer/requirements.txt"
