#!/usr/bin/env bash
#
# Regenerates fork-break-fix-delete/data/nyc311_sample.csv.gz.
#
# You do NOT need to run this for the workshop — the .csv.gz is committed.
# This exists so the dataset is reproducible, and so we can resize it if the
# free-tier storage cap ever bites.
#
# Source: NYC Open Data, 311 Service Requests from 2010 to Present (erm2-nwe9)
#   https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9
#
# Two things worth knowing:
#   1. The pull takes ~2 minutes from a good connection. That is exactly why the
#      CSV is committed instead of downloaded live — 40 attendees hitting an
#      unauthenticated Socrata endpoint at the same moment is a rate-limit story.
#   2. Socrata hands back latitude/longitude with 17 significant digits, which is
#      nonsense precision and about 8 MB of pure gzip bloat. We round to 6 decimals
#      (~10 cm), which is both more honest and what keeps us under the size cap.
#
# Size budget: the committed .gz must stay under 25 MB. Every clone of this repo
# pays for it, including the other workshops' Codespaces. If you add rows and blow
# the budget, take rows back out — do not reach for Git LFS.

set -euo pipefail

ROWS="${ROWS:-1000000}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
RAW="$(mktemp -t nyc311raw.XXXXXX).csv"
TRIMMED="$(mktemp -t nyc311trim.XXXXXX).csv"
trap 'rm -f "$RAW" "$TRIMMED"' EXIT

echo "==> Downloading ${ROWS} rows of NYC 311 service requests (this takes a couple of minutes)"
curl -sS --fail -G 'https://data.cityofnewyork.us/resource/erm2-nwe9.csv' \
  --data-urlencode "\$limit=${ROWS}" \
  --data-urlencode '$order=created_date' \
  --data-urlencode "\$where=created_date between '2024-01-01T00:00:00' and '2024-12-31T23:59:59'" \
  --data-urlencode '$select=unique_key,created_date,closed_date,agency,complaint_type,descriptor,borough,incident_zip,latitude,longitude' \
  -o "$RAW"

echo "==> Rounding coordinates to 6 decimal places"
python3 - "$RAW" "$TRIMMED" <<'PY'
import csv, sys
src, dst = sys.argv[1], sys.argv[2]
reader = csv.reader(open(src, newline=""))
writer = csv.writer(open(dst, "w", newline=""), quoting=csv.QUOTE_MINIMAL)
header = next(reader)
writer.writerow(header)
lat, lon = header.index("latitude"), header.index("longitude")
count = 0
for row in reader:
    for i in (lat, lon):
        if row[i]:
            row[i] = f"{float(row[i]):.6f}"
    writer.writerow(row)
    count += 1
print(f"    {count:,} rows")
PY

echo "==> Compressing"
gzip -9 -c "$TRIMMED" > "$OUT_DIR/nyc311_sample.csv.gz"

SIZE_MB=$(( $(wc -c < "$OUT_DIR/nyc311_sample.csv.gz") / 1024 / 1024 ))
echo "==> Wrote $OUT_DIR/nyc311_sample.csv.gz (${SIZE_MB} MB)"
if [ "$SIZE_MB" -ge 25 ]; then
  echo "!!! ${SIZE_MB} MB is over the 25 MB budget. Re-run with a smaller ROWS= value." >&2
  exit 1
fi
