"""
MQTT side of the consumer: subscribe to the workshop topics and turn each raw
message into a structured reading.

A topic like

    workshop/plant1/line-a/mixer/temperature

encodes the tag's place in the plant hierarchy (its Unified Namespace path).
We strip the base prefix to get the UNS path, and take the last two segments as
the asset ("mixer") and metric ("temperature"). This is how the metadata table
gets populated straight from the topic tree — no manual registration needed.
"""
import time
from dataclasses import dataclass

import paho.mqtt.client as mqtt

from app import config


@dataclass
class Reading:
    ts: str          # ISO-8601 timestamp from the payload
    tag_id: str
    value: float
    quality: int
    uns_path: str    # derived from the topic, e.g. plant1/line-a/mixer/temperature
    asset: str       # e.g. mixer
    metric: str      # e.g. temperature


def parse(topic: str, payload: str) -> Reading | None:
    """Turn one MQTT message into a Reading, or None if it's malformed."""
    try:
        tag_id, ts, value, quality = payload.split(",")
    except ValueError:
        print(f"[consumer] skipping malformed payload: {payload!r}", flush=True)
        return None

    # Derive the UNS path by stripping the "workshop/" prefix from the topic.
    prefix = config.MQTT_TOPIC_BASE + "/"
    uns_path = topic[len(prefix):] if topic.startswith(prefix) else topic
    segments = uns_path.split("/")
    asset = segments[-2] if len(segments) >= 2 else "unknown"
    metric = segments[-1]

    return Reading(
        ts=ts,
        tag_id=tag_id,
        value=float(value),
        quality=int(quality),
        uns_path=uns_path,
        asset=asset,
        metric=metric,
    )


def start(on_reading) -> mqtt.Client:
    """Connect, subscribe, and call on_reading(Reading) for every message."""

    def _on_connect(client, userdata, flags, reason_code, properties):
        print(f"[consumer] connected to broker, subscribing to {config.MQTT_SUBSCRIBE}", flush=True)
        client.subscribe(config.MQTT_SUBSCRIBE)

    def _on_message(client, userdata, msg):
        reading = parse(msg.topic, msg.payload.decode())
        if reading is not None:
            on_reading(reading)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = _on_connect
    client.on_message = _on_message
    if config.MQTT_USERNAME:
        client.username_pw_set(config.MQTT_USERNAME, config.MQTT_PASSWORD)
    if config.MQTT_TLS:
        # ca_certs=None uses the system trust store (works for Let's Encrypt).
        client.tls_set(ca_certs=config.MQTT_CA_CERT or None)

    while True:
        try:
            client.connect(config.MQTT_BROKER_HOST, config.MQTT_BROKER_PORT, keepalive=60)
            break
        except OSError as exc:
            print(f"[consumer] broker not ready ({exc}); retrying in 2s...", flush=True)
            time.sleep(2)

    client.loop_start()
    return client
