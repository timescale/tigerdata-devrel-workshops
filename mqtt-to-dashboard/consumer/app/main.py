"""
Consumer entrypoint — THIS is where the workshop happens.

Flow:  MQTT message  ->  parse into a Reading  ->  buffer  ->  batch-insert to Tiger Cloud

paho delivers messages on a single background thread, so mqtt_client buffers and
writes right in the message callback — no extra threads or locks needed. A failed
write (e.g. tables not created yet) keeps the batch and retries, so nothing is lost.
"""
from app import mqtt_client
from app.tigercloud_client import TigerCloudWriter


def main() -> None:
    writer = TigerCloudWriter()
    # Connects to the broker, subscribes, and blocks handling messages until killed.
    mqtt_client.start(writer)


if __name__ == "__main__":
    main()
