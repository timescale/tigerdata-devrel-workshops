"""Producer configuration, read from environment variables (see .env)."""
import os

MQTT_BROKER_HOST = os.getenv("MQTT_BROKER_HOST", "mqtt-broker")
MQTT_BROKER_PORT = int(os.getenv("MQTT_BROKER_PORT", "1883"))
MQTT_TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "workshop")
INTERVAL_SECONDS = float(os.getenv("PRODUCER_INTERVAL_SECONDS", "2"))

# Auth + TLS (off by default for the all-local stack; used when publishing to a
# hardened public broker — see deploy/). MQTT_CA_CERT is only needed for a
# self-signed cert; a Let's Encrypt cert is trusted by the system store.
MQTT_USERNAME = os.getenv("MQTT_USERNAME", "")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "")
MQTT_TLS = os.getenv("MQTT_TLS", "false").lower() in ("1", "true", "yes")
MQTT_CA_CERT = os.getenv("MQTT_CA_CERT", "")
