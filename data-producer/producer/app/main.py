"""
Producer entrypoint (REFERENCE CODE).

Publishes one CSV reading per tag to MQTT every PRODUCER_INTERVAL_SECONDS.
Attendees read this to understand where the data comes from; the workshop
activity happens in the consumer, the SQL, and Grafana.
"""
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

from app import config
from app.generator import Generator


def connect() -> mqtt.Client:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    if config.MQTT_USERNAME:
        client.username_pw_set(config.MQTT_USERNAME, config.MQTT_PASSWORD)
    if config.MQTT_TLS:
        # ca_certs=None uses the system trust store (works for Let's Encrypt).
        client.tls_set(ca_certs=config.MQTT_CA_CERT or None)
    # Retry until the broker is up (it may still be starting).
    while True:
        try:
            client.connect(config.MQTT_BROKER_HOST, config.MQTT_BROKER_PORT, keepalive=60)
            break
        except OSError as exc:
            print(f"[producer] broker not ready ({exc}); retrying in 2s...", flush=True)
            time.sleep(2)
    client.loop_start()
    return client


def main() -> None:
    print(
        f"[producer] publishing to {config.MQTT_BROKER_HOST}:{config.MQTT_BROKER_PORT} "
        f"under '{config.MQTT_TOPIC_BASE}/' every {config.INTERVAL_SECONDS}s",
        flush=True,
    )
    client = connect()
    gen = Generator()

    while True:
        published = 0
        for tag_id, topic_suffix, value, quality in gen.readings():
            topic = f"{config.MQTT_TOPIC_BASE}/{topic_suffix}"
            ts = datetime.now(timezone.utc).isoformat()
            payload = f"{tag_id},{ts},{value},{quality}"
            client.publish(topic, payload)
            published += 1
        print(f"[producer] published {published} readings", flush=True)
        time.sleep(config.INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
