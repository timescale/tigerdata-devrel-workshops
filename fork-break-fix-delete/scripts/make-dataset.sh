#!/usr/bin/env bash
#
# Regenerates data/load/*.sql.gz.
#
# You do NOT need to run this for the workshop -- the data files are committed.
# This exists so the dataset is reproducible and resizable.
#
# Source: NYC Open Data, 311 Service Requests from 2010 to Present (erm2-nwe9)
#   https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9
#
# Three things worth knowing:
#   1. The download takes ~2 minutes. That's why the data is committed rather
#      than fetched live -- forty attendees hitting an unauthenticated Socrata
#      endpoint at the same moment is a rate-limit story.
#   2. Socrata returns latitude/longitude with 17 significant digits, which is
#      nonsense precision and pure gzip bloat. We round to 6 decimals (~10 cm).
#   3. Output is INSERT statements, not CSV, because the workshop loads data with
#      `tiger db query` and nothing else. Chunked at 100k rows because a single
#      1M-row file is ~146 MB of SQL and a free service OOMs on it.
#
# Size budget: data/ must stay under 25 MB total. Every clone of this repo pays
# for it, including the other workshops' codespaces. If you add rows and blow the
# budget, take rows back out -- do not reach for Git LFS.

set -euo pipefail

ROWS="${ROWS:-1000000}"
CHUNK="${CHUNK:-100000}"
WORKSHOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="$(mktemp -t nyc311raw.XXXXXX).csv"
trap 'rm -f "$RAW"' EXIT

echo "==> Downloading ${ROWS} rows of NYC 311 service requests (a couple of minutes)"
curl -sS --fail -G 'https://data.cityofnewyork.us/resource/erm2-nwe9.csv' \
  --data-urlencode "\$limit=${ROWS}" \
  --data-urlencode '$order=created_date' \
  --data-urlencode "\$where=created_date between '2024-01-01T00:00:00' and '2024-12-31T23:59:59'" \
  --data-urlencode '$select=unique_key,created_date,closed_date,agency,complaint_type,descriptor,borough,incident_zip,latitude,longitude' \
  -o "$RAW"

echo "==> Writing data/load/*.sql.gz"
rm -f "$WORKSHOP"/data/load/*.sql.gz
mkdir -p "$WORKSHOP/data/load"

CHUNK="$CHUNK" OUT="$WORKSHOP/data/load" python3 - "$RAW" <<'PY'
import csv, gzip, os, sys

chunk_size = int(os.environ["CHUNK"])
out_dir = os.environ["OUT"]
reader = csv.reader(open(sys.argv[1], newline=""))
header = next(reader)
lat, lon = header.index("latitude"), header.index("longitude")

def sql(value):
    return "NULL" if value == "" else "'" + value.replace("'", "''") + "'"

out, batch, rows, part = None, [], 0, 0

def flush():
    if batch:
        out.write("INSERT INTO service_requests VALUES\n" + ",\n".join(batch) + ";\n")
        batch.clear()

for row in reader:
    for i in (lat, lon):
        if row[i]:
            row[i] = f"{float(row[i]):.6f}"
    if rows % chunk_size == 0:
        part += 1
        out = gzip.open(f"{out_dir}/{part:02d}.sql.gz", "wt", compresslevel=9)
    batch.append("(" + ",".join(sql(c) for c in row) + ")")
    rows += 1
    if len(batch) == 1000:
        flush()
    if rows % chunk_size == 0:
        flush(); out.close()

flush()
if out and not out.closed:
    out.close()
print(f"    {rows:,} rows in {part} chunks")
PY

TOTAL_MB=$(( $(du -sk "$WORKSHOP/data" | cut -f1) / 1024 ))
echo "==> data/ is now ${TOTAL_MB} MB"
if [ "$TOTAL_MB" -ge 25 ]; then
  echo "!!! ${TOTAL_MB} MB is over the 25 MB budget. Re-run with a smaller ROWS= value." >&2
  exit 1
fi
