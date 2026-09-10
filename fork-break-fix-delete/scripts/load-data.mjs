// Stream the gzipped NYC 311 CSV into a Tiger Cloud service.
//
//   node scripts/load-data.mjs fbfd-original
//
// Why this exists: loading a local file into Postgres means a COPY ... FROM STDIN,
// and the client has to push the rows over the wire. `tiger db query` has no way
// to do that -- it sends a query, not a data stream -- and this workshop does not
// assume psql is installed. So we do the COPY directly against the wire protocol.
//
// Reads the .gz without unpacking it first, so nothing writes 126 MB to disk.

import { spawnSync } from "node:child_process";
import { createReadStream } from "node:fs";
import { createGunzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import pg from "pg";
import { from as copyFrom } from "pg-copy-streams";

const here = dirname(fileURLToPath(import.meta.url));
const service = process.argv[2];
const csv = process.argv[3] ?? join(here, "..", "data", "nyc311_sample.csv.gz");
const table = process.argv[4] ?? "service_requests";

if (!service) {
  console.error("usage: node scripts/load-data.mjs <service-name> [csv.gz] [table]");
  process.exit(64);
}

// Reuse the same name -> connection string lookup the rest of the workshop uses.
const conn = spawnSync(join(here, "conn"), [service], { encoding: "utf8" });
if (conn.status !== 0) {
  process.stderr.write(conn.stderr || `could not resolve service '${service}'\n`);
  process.exit(1);
}

// The connection string says sslmode=require. In libpq that means "encrypt, but
// don't verify the chain" -- which is what psql does here, because Tiger Cloud's
// certificate chain doesn't validate against Node's default CA store. Recent
// node-postgres reads sslmode=require as verify-full instead, so we say what we
// mean explicitly rather than depending on which interpretation ships.
// node-postgres lets the connection string's own sslmode win over the ssl option,
// so drop it and state the intent once, in one place.
const url = new URL(conn.stdout.trim());
url.searchParams.delete("sslmode");

const client = new pg.Client({
  connectionString: url.toString(),
  ssl: { rejectUnauthorized: false },
});
await client.connect();

const started = Date.now();
let bytes = 0;

try {
  const sink = client.query(
    copyFrom(`COPY ${table} FROM STDIN WITH (FORMAT csv, HEADER true)`)
  );
  const source = createReadStream(csv);

  // Progress only when someone is watching. Redirected to a file or a log, the
  // carriage returns turn into thousands of useless lines.
  if (process.stderr.isTTY) {
    source.on("data", (chunk) => {
      bytes += chunk.length;
      process.stderr.write(`\r  ${(bytes / 1048576).toFixed(0)} MB uploaded`);
    });
  }

  await pipeline(source, createGunzip(), sink);
  if (process.stderr.isTTY) process.stderr.write("\r".padEnd(40) + "\r");

  const { rows } = await client.query(`SELECT count(*)::bigint AS n FROM ${table}`);
  const secs = ((Date.now() - started) / 1000).toFixed(1);
  console.log(`Loaded ${Number(rows[0].n).toLocaleString()} rows into ${table} in ${secs}s`);
} finally {
  await client.end();
}
