"""Consumer configuration, read from environment variables (see .env)."""
import os

# MQTT
MQTT_BROKER_HOST = os.getenv("MQTT_BROKER_HOST", "mqtt-broker")
MQTT_BROKER_PORT = int(os.getenv("MQTT_BROKER_PORT", "1883"))
MQTT_SUBSCRIBE = os.getenv("MQTT_SUBSCRIBE", "workshop/#")
MQTT_TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "workshop")

# Auth + TLS. Off for the all-local stack; set these to connect to a hardened
# shared broker (see deploy/). MQTT_CA_CERT is only needed for a self-signed
# cert — a Let's Encrypt cert is trusted by the system store, so leave it blank.
MQTT_USERNAME = os.getenv("MQTT_USERNAME", "")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "")
MQTT_TLS = os.getenv("MQTT_TLS", "false").lower() in ("1", "true", "yes")
MQTT_CA_CERT = os.getenv("MQTT_CA_CERT", "")

# Tiger Cloud connection (discrete fields — same values Grafana uses).
DB = {
    "host": os.getenv("TIGER_HOST", ""),
    "port": int(os.getenv("TIGER_PORT", "5432")),
    "dbname": os.getenv("TIGER_DATABASE", "tsdb"),
    "user": os.getenv("TIGER_USER", "tsdbadmin"),
    "password": os.getenv("TIGER_PASSWORD", ""),
    # Tiger Cloud always requires SSL; override only for a local test DB.
    "sslmode": os.getenv("TIGER_SSLMODE", "require"),
}

# How many readings to buffer before writing a batch to Tiger Cloud, and the
# max time to wait before flushing a partial batch.
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "50"))
FLUSH_SECONDS = float(os.getenv("FLUSH_SECONDS", "2"))
