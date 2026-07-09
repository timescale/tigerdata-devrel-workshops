"""
Tiger Cloud side of the consumer.

It's just Postgres: we connect with a standard connection and use plain SQL.
Two things happen here:

  1. auto-register any new tag into `tag_meta` (from the topic hierarchy), so
     ingestion never fails on the foreign key and the namespace self-populates.
  2. batch-insert readings into the `tag_history` hypertable.

If the tables don't exist yet, we print a friendly reminder to run
sql/1-create_tables.sql and keep buffering — nothing is lost.
"""
import time

import psycopg
from psycopg import errors

from app import config
from app.mqtt_client import Reading


class TigerCloudWriter:
    def __init__(self):
        self._conn = self._connect()
        # Tags we've already ensured exist in tag_meta (avoids re-upserting).
        self._known_tags: set[str] = set()
        # So we log "tables not found" once, not on every retry.
        self._warned_no_tables = False

    def _connect(self) -> psycopg.Connection:
        while True:
            try:
                conn = psycopg.connect(**config.DB, autocommit=True)
                print(f"[consumer] connected to Tiger Cloud at {config.DB['host']}", flush=True)
                return conn
            except psycopg.OperationalError as exc:
                print(f"[consumer] cannot reach Tiger Cloud ({exc}); retrying in 3s...", flush=True)
                time.sleep(3)

    def _ensure_assets(self, readings: list[Reading]) -> None:
        """Register any tags we haven't seen before (idempotent)."""
        new = {r.tag_id: r for r in readings if r.tag_id not in self._known_tags}
        if not new:
            return
        with self._conn.cursor() as cur:
            cur.executemany(
                """
                INSERT INTO tag_meta (tag_id, uns_path, asset, metric)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (tag_id) DO NOTHING
                """,
                [(r.tag_id, r.uns_path, r.asset, r.metric) for r in new.values()],
            )
        self._known_tags.update(new.keys())

    def write(self, readings: list[Reading]) -> bool:
        """
        Insert a batch of readings. Returns True on success; False if it couldn't
        (the caller keeps the batch and retries), so nothing is lost.
        """
        if not readings:
            return True
        try:
            self._ensure_assets(readings)
            with self._conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO tag_history (ts, tag_id, value, quality) VALUES (%s, %s, %s, %s)",
                    [(r.ts, r.tag_id, r.value, r.quality) for r in readings],
                )
            print(f"[consumer] wrote {len(readings)} readings to Tiger Cloud", flush=True)
            self._warned_no_tables = False
            return True
        except errors.UndefinedTable:
            if not self._warned_no_tables:
                print(
                    "[consumer] tables not found — run sql/1-create_tables.sql, "
                    "then I'll start writing. (buffering...)",
                    flush=True,
                )
                self._warned_no_tables = True
            # Clear the known-tags cache so assets get re-registered post-create.
            self._known_tags.clear()
            return False
        except psycopg.OperationalError:
            print("[consumer] lost connection to Tiger Cloud; reconnecting...", flush=True)
            self._conn = self._connect()
            return False
