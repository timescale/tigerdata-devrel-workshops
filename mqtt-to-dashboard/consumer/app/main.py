"""
Consumer entrypoint — THIS is where the workshop happens.

Flow:
  MQTT message  ->  parse into a Reading  ->  buffer  ->  batch-insert to Tiger Cloud

The buffer smooths out writes: we flush when it reaches BATCH_SIZE, or every
FLUSH_SECONDS, whichever comes first. If a write fails (e.g. tables not created
yet), the batch is kept and retried on the next flush, so no readings are lost.
"""
import threading
import time

from app import config
from app import mqtt_client
from app.tigercloud_client import TigerCloudWriter


def main() -> None:
    buffer: list = []
    lock = threading.Lock()

    def on_reading(reading) -> None:
        with lock:
            buffer.append(reading)

    writer = TigerCloudWriter()
    mqtt_client.start(on_reading)

    last_flush = time.monotonic()
    while True:
        time.sleep(0.2)
        now = time.monotonic()
        with lock:
            due = len(buffer) >= config.BATCH_SIZE or (
                buffer and now - last_flush >= config.FLUSH_SECONDS
            )
            batch = list(buffer) if due else None

        if batch:
            try:
                writer.write(batch)
                with lock:
                    del buffer[: len(batch)]   # drop only what we successfully wrote
            except Exception:
                # write() already logged the reason; keep the batch and retry.
                pass
            last_flush = now


if __name__ == "__main__":
    main()
