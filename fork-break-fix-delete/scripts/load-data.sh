#!/usr/bin/env bash
#
# Load the NYC 311 dataset into a Tiger Cloud service.
#
#   scripts/load-data.sh fbfd-original
#
# Needs nothing but the Tiger CLI and gunzip. No psql, no Node, no drivers.
#
# The data ships as ten gzipped files of INSERT statements in data/load/. Two
# reasons it's chunked rather than one file:
#
#   * `tiger db query` sends a file as a single query string. All 1,000,000 rows
#     at once is ~146 MB of SQL and a free service answers with
#     "ERROR: out of memory (SQLSTATE 53200)". 100,000 rows at a time is ~15 MB
#     and lands fine.
#   * gunzip streams straight into the CLI's stdin, so nothing is ever unpacked
#     to disk.
#
# INSERTs are slower than a COPY would be -- about 78 seconds for the full
# million against a free service. COPY isn't available to us: it needs the
# client to stream data in a mode `tiger db query` doesn't implement.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

name="${1:-}"
if [ -z "$name" ]; then
    echo "usage: scripts/load-data.sh <service-name>" >&2
    exit 64
fi

sid="$("$here/sid" "$name")"
shopt -s nullglob
parts=("$here"/../data/load/*.sql.gz)

if [ ${#parts[@]} -eq 0 ]; then
    echo "No data files in data/load/. Did the clone finish?" >&2
    exit 1
fi

echo "Loading ${#parts[@]} chunks into '$name' ($sid). Takes about 80 seconds."
started=$SECONDS

for part in "${parts[@]}"; do
    printf '  %s ... ' "$(basename "$part")"
    if gunzip -c "$part" | tiger db query "$sid" >/dev/null; then
        echo "ok"
    else
        echo "FAILED"
        echo "Load stopped. Re-run sql/1-bad-schema.sql to reset, then try again." >&2
        exit 1
    fi
done

echo "Done in $((SECONDS - started))s."
tiger db query "$sid" -c "SELECT count(*) AS rows, min(created_date) AS earliest, max(created_date) AS latest FROM service_requests"
