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

// TLS, and why this is more than one line.
//
// Tiger Cloud presents a private, self-signed certificate chain:
//
//   leaf   C=USA, O=Timescale Inc, CN=<service>.<project>.tsdb.cloud.timescale.com
//   root   O=Timescale Inc, CN=ca.timescale.com   (self-signed)
//
// That root is not in any public trust store and Tiger does not publish it for
// download, so verifying the chain is not merely inconvenient, it is impossible.
// We checked a free service and a paid one and both presented it, despite the
// strict-SSL docs describing Google/ZeroSSL certificates on paid plans.
//
// The connection string the CLI hands out says sslmode=require, which in libpq
// means "encrypt, don't verify" -- so psql and the Tiger CLI itself are already
// doing exactly what the fallback below does.
//
// Still: verify by default, and fall back to encrypted-but-unverified ONLY when
// the failure is specifically an unverifiable chain -- loudly, never silently.
// Any other TLS error is a real error and propagates. If Tiger ever ships
// publicly-trusted certificates, this starts verifying with no change here.
//
// (node-postgres lets the connection string's own sslmode win over the ssl
// option, so drop it and state the intent in one place.)
const url = new URL(conn.stdout.trim());
url.searchParams.delete("sslmode");

const UNVERIFIABLE_CHAIN = new Set([
  "SELF_SIGNED_CERT_IN_CHAIN",
  "DEPTH_ZERO_SELF_SIGNED_CERT",
  "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
]);

async function connect(verify) {
  const client = new pg.Client({
    connectionString: url.toString(),
    ssl: verify
      ? { rejectUnauthorized: true, servername: url.hostname }
      : { rejectUnauthorized: false },
  });
  await client.connect();
  return client;
}

let client;
try {
  client = await connect(true);
} catch (err) {
  if (!UNVERIFIABLE_CHAIN.has(err.code)) throw err;
  console.warn(
    `  note: ${url.hostname}\n` +
    `        presents a private Tiger Cloud certificate chain that cannot be\n` +
    `        verified against the public trust store (${err.code}).\n` +
    `        Expected today on every Tiger Cloud service. Continuing: the\n` +
    `        connection is encrypted, but the server is not authenticated --\n` +
    `        the same guarantee psql gives you with sslmode=require.`
  );
  client = await connect(false);
}

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
