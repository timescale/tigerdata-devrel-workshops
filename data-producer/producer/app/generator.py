"""
Defines the workshop's fleet of industrial "tags" and generates believable
readings for them.

Each tag maps to an MQTT topic that encodes its place in the plant hierarchy
(a Unified Namespace, or UNS):

    workshop / <area> / <line> / <asset> / <metric>

The consumer parses that hierarchy back out of the topic. The payload itself is
a compact CSV line — the same shape an OPC-UA gateway or historian might emit:

    tag_id,timestamp,value,quality

`quality` is an OPC-UA-style code: 192 = Good, 0 = Bad.
"""
import math
import random

# Canonical tag list. Keep this in sync with sql/1-create_tables.sql, which
# seeds the same tags with human-friendly units and descriptions.
#
#   tag_id, topic (below MQTT_TOPIC_BASE), baseline, amplitude, noise, kind
TAGS = [
    # Line A — mixer
    ("T-101", "plant1/line-a/mixer/temperature",  70.0, 4.0, 0.4, "wave"),
    ("P-101", "plant1/line-a/mixer/pressure",       2.5, 0.3, 0.05, "wave"),
    ("M-101", "plant1/line-a/mixer/motor_state",    1.0, 0.0, 0.0,  "state"),
    # Line B — reactor + filler
    ("T-201", "plant1/line-b/reactor/temperature", 85.0, 6.0, 0.6, "wave"),
    ("P-201", "plant1/line-b/reactor/pressure",     3.2, 0.4, 0.06, "wave"),
    ("F-201", "plant1/line-b/filler/flow_rate",    40.0, 8.0, 1.0,  "wave"),
]


class Generator:
    """Produces one reading per tag per tick, with gentle drift + noise."""

    def __init__(self):
        # Give each tag its own phase so the waves aren't all synchronized.
        self._phase = {tag_id: random.uniform(0, 2 * math.pi) for tag_id, *_ in TAGS}
        self._step = 0

    def readings(self):
        """Yield (tag_id, topic_suffix, value, quality) for every tag."""
        self._step += 1
        t = self._step / 20.0
        for tag_id, topic, baseline, amp, noise, kind in TAGS:
            if kind == "state":
                # Motor is mostly ON (1); occasionally flips to a short stop.
                value = 0.0 if random.random() < 0.02 else 1.0
            else:
                phase = self._phase[tag_id]
                value = baseline + amp * math.sin(t + phase) + random.gauss(0, noise)
                value = round(value, 3)
            # 99% of readings are Good quality; the rest are Bad (0).
            quality = 0 if random.random() < 0.01 else 192
            yield tag_id, topic, value, quality
