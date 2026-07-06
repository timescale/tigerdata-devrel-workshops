#!/usr/bin/env bash
# ============================================================================
# One-time setup for the public MQTT broker + producer VM.
#
#   cp .env.server.example .env.server && edit it
#   ./setup.sh                 # Let's Encrypt cert for $DOMAIN (needs port 80 free)
#   ./setup.sh --self-signed   # self-signed cert (testing / no DNS)
#
# Re-running is safe: it recreates the password file and refreshes the cert.
# Requires Docker (with the compose plugin). No other host packages needed —
# mosquitto_passwd, certbot, and openssl all run inside containers.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

SELF_SIGNED=false
[[ "${1:-}" == "--self-signed" ]] && SELF_SIGNED=true

if [[ ! -f .env.server ]]; then
  echo "ERROR: .env.server not found. Run: cp .env.server.example .env.server && edit it" >&2
  exit 1
fi
set -a; source .env.server; set +a
: "${DOMAIN:?set DOMAIN in .env.server}"
: "${PRODUCER_PASSWORD:?set PRODUCER_PASSWORD in .env.server}"
: "${ATTENDEE_PASSWORD:?set ATTENDEE_PASSWORD in .env.server}"

MOSQ_IMG="eclipse-mosquitto:2"
CERTS_DIR="broker/certs"
mkdir -p "$CERTS_DIR"

# --- 1. Password file (producer = read/write, attendee = read-only) ---------
echo "==> Generating password file..."
docker run --rm -v "$PWD/broker:/m" "$MOSQ_IMG" \
  mosquitto_passwd -b -c /m/passwd producer "$PRODUCER_PASSWORD"
docker run --rm -v "$PWD/broker:/m" "$MOSQ_IMG" \
  mosquitto_passwd -b /m/passwd attendee "$ATTENDEE_PASSWORD"

# --- 2. TLS certificate -----------------------------------------------------
if $SELF_SIGNED; then
  echo "==> Generating a self-signed cert for $DOMAIN (testing only)..."
  docker run --rm -v "$PWD/$CERTS_DIR:/c" alpine/openssl \
    req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout /c/privkey.pem -out /c/fullchain.pem \
    -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost"
  echo "    NOTE: attendees must set MQTT_CA_CERT to this fullchain.pem to trust it."
else
  echo "==> Obtaining a Let's Encrypt cert for $DOMAIN (port 80 must be free + open)..."
  docker run --rm -p 80:80 -v "$PWD/letsencrypt:/etc/letsencrypt" \
    certbot/certbot certonly --standalone \
    -d "$DOMAIN" --non-interactive --agree-tos -m "${CERTBOT_EMAIL:?set CERTBOT_EMAIL}"
  cp "letsencrypt/live/$DOMAIN/fullchain.pem" "$CERTS_DIR/fullchain.pem"
  cp "letsencrypt/live/$DOMAIN/privkey.pem"  "$CERTS_DIR/privkey.pem"
fi

# The broker runs as the mosquitto user (uid 1883). mosquitto_passwd, certbot,
# and openssl write their output as root:root 0600, and the repo's config files
# are owned by the clone user — uid 1883 can read none of these, and recent
# Mosquitto refuses world-readable auth files. Hand them all to uid 1883.
SUDO=""; [[ $EUID -ne 0 ]] && command -v sudo >/dev/null && SUDO="sudo"
$SUDO chown 1883:1883 broker/passwd broker/aclfile broker/mosquitto.conf "$CERTS_DIR"/*.pem
$SUDO chmod 0640 broker/passwd broker/aclfile broker/mosquitto.conf "$CERTS_DIR/privkey.pem"
$SUDO chmod 0644 "$CERTS_DIR/fullchain.pem"

# --- 3. Launch --------------------------------------------------------------
echo "==> Starting broker + producer..."
docker compose -f docker-compose.server.yml up -d --build

cat <<EOF

Done. Broker is live on port 8883 (TLS).

  Open ONLY 8883/tcp to the world in your cloud firewall / security group.
  ($SELF_SIGNED && echo "Port 80 was used just now for the cert; you can close it.")

Attendees connect with:
  MQTT_BROKER_HOST=$DOMAIN
  MQTT_BROKER_PORT=8883
  MQTT_TLS=true
  MQTT_USERNAME=attendee
  MQTT_PASSWORD=<the ATTENDEE_PASSWORD you set>

Check it:  docker compose -f docker-compose.server.yml logs -f producer
EOF
