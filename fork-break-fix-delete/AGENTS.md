# Agent instructions — fork-break-fix-delete workshop

Read by Claude Code, Codex, and GitHub Copilot CLI. Launch your agent from **this
directory** (`cd fork-break-fix-delete`) so it picks up this file and the
permission rules in `.claude/settings.json`.

## Target service

```
TARGET SERVICE: fbfd-original
```

That line is the only thing standing between you and a very bad afternoon, and
you are going to edit it during the workshop. Right now it points at the service
you are ingesting data into. In step 3 you will change it to `fbfd-fork`, and
from that moment on the original is off limits.

## Rules

1. **Only connect to the service named on the `TARGET SERVICE` line above.**
   Get its connection string with:
   ```
   scripts/conn <TARGET SERVICE>
   ```
   That helper exists because the Tiger CLI addresses services by their
   ten-character service ID, not by name — it resolves the name for you and calls
   `tiger db connection-string <id> --with-password`.

   Never connect to any other service in this project. If a task seems to require
   it, stop and ask.

2. **Never run `tiger service delete`, `tiger service stop`, or
   `tiger service update-password`.** Service lifecycle is the human's job.

3. **Search the docs before you guess.** Tiger MCP exposes a `search_docs` tool
   with the real TimescaleDB documentation in it. Hypertable and continuous
   aggregate syntax has changed across versions; do not write it from memory.

4. **Measure before and after.** Any change you make to the schema must be
   bracketed by `EXPLAIN (ANALYZE, BUFFERS)` on the affected query, and you must
   report both plans and both timings. "It should be faster now" is not a result.

5. **Say what you are about to drop, before you drop it.** `DROP TABLE`,
   `DROP INDEX`, `ALTER TABLE ... DROP COLUMN` and table rewrites all get
   announced first, in plain language, including how many rows are affected.

6. **Do not touch the CSV in `data/`.** It is the source of truth for re-runs.

## About this database

`service_requests` holds one million NYC 311 service requests from 2024. It was
loaded from a CSV by someone in a hurry, which is why every column is `text`.

Queries against it are dashboard-shaped: bucket by time, group by a category
(`complaint_type`, `borough`, `agency`), filter to a date window. Optimise for
that access pattern.
