# From MQTT to Dashboard: Real-Time IIoT Pipelines with Tiger Cloud

A 60-minute hands-on workshop where you build a working industrial IoT pipeline end to end: **MQTT → Tiger Cloud → Grafana**. A broker streams live sensor readings, you ingest them into a TimescaleDB hypertable on Tiger Cloud, model them alongside equipment metadata, write fast time-series queries, and watch it all light up a live Grafana dashboard.

You run the consumer + Grafana locally in Docker. The MQTT feed comes from a separate project ([`../data-producer`](../data-producer)) — either a shared broker your instructor hosts, or one you run yourself. You bring one thing: a free Tiger Cloud service.

## What you'll learn

- **Ingest MQTT into Tiger Cloud** — subscribe to a broker and land topic data in a hypertable
- **Model readings + metadata** — a hypertable for facts, a metadata table for equipment context, joined
- **Fast time-series queries** — `time_bucket()`, the `last()` hyperfunction, and continuous aggregates for real-time trending
- **A live operational dashboard** — connect Grafana to Tiger Cloud and watch it update as data flows

## Architecture

```text
  ../data-producer                    this project (Docker, your laptop)
  ┌──────────────────┐               ┌──────────────────────┐        ┌─────────────────────┐
  │ producer ─▶ MQTT │──── MQTT ────▶│ consumer      Grafana │──SQL──▶│  Tiger Cloud        │
  │            broker│               │    │            │      │        │  (hosted TimescaleDB)│
  └──────────────────┘               └────┼────────────┼──────┘        │  hypertable + caggs  │
                                          └────SQL──────┴──────────────▶                      │
                                                                        └─────────────────────┘
```

You work in the **consumer**, the **`sql/`** files, and **Grafana**. The MQTT feed (producer + broker) lives in [`../data-producer`](../data-producer) — read it to see how the sample telemetry is generated.

### Where does the MQTT feed come from?

- **Shared broker (instructor-hosted):** the instructor runs the broker + producer on a public VM; everyone subscribes to the same live feed over TLS. Use the `MQTT_*` values they give you. *(This is the default for a live workshop.)*
- **Local broker (self-paced):** run the feed yourself from [`../data-producer`](../data-producer) (`docker compose up`), and point this project's consumer at `host.docker.internal:1883`.

Either way, you only run the consumer + Grafana here.

---

## Before the workshop — setup checklist

Four steps. Do them **before workshop day** — it's a bad time to debug DNS or a Docker install.

### 1. Sign up for Tiger Cloud

Sign up at [tigerdata.com](https://www.tigerdata.com/) and you'll get trial credit — far more than this workshop needs.

### 2. Spin up a service

Create a new service:

- **Type:** PostgreSQL with time-series and analytics
- **Region:** whichever is closest
- **Compute:** the smallest paid SKU is plenty; trial credits cover it
- **Name:** anything (e.g. `mqtt-workshop`)

From the service's **Connection info** panel, note the **host, port, database, user, and password**. They're also all in the connection string:

```
postgres://tsdbadmin:PASSWORD@HOST:PORT/tsdb?sslmode=require
```

### 3. Install Docker Desktop

This workshop runs a local stack, so you need Docker. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and confirm it works:

```bash
docker compose version
```

### 4. Test your Tiger Cloud connection

A few days ahead, confirm you can reach your service. Either use the **Data** tab in the Tiger Cloud console, or [`psql`](https://www.tigerdata.com/blog/how-to-install-psql-on-mac-ubuntu-debian-windows):

```bash
psql "postgres://tsdbadmin:...your-connection-string..." -c "SELECT version();"
```

If you see a Postgres version string, you're set.

---

## Running the stack

**1. Configure.** Copy the example env file and fill it in:

```bash
cd mqtt-to-dashboard
cp .env.example .env
```

Edit `.env` and set:
- your **Tiger Cloud** connection (`TIGER_HOST`, `TIGER_PORT`, `TIGER_DATABASE`, `TIGER_USER`, `TIGER_PASSWORD`), and
- the **MQTT broker** — either the shared-broker values your instructor gives you, or the local defaults (`host.docker.internal:1883`) if you're running [`../data-producer`](../data-producer) yourself.

**2. (Local feed only) Start the data producer** in a separate terminal:

```bash
cd ../data-producer && cp .env.example .env && docker compose up --build
```

Skip this if you're using a shared broker.

**3. Start the consumer + Grafana:**

```bash
docker compose up --build
```

The consumer connects to the broker and will print a reminder that the tables don't exist yet — that's expected; you create them next.

---

## During the workshop

We work through the [`sql`](./sql) files in order. Run them in the Tiger Cloud console **Data** tab, or with `psql`. Each file is self-contained, so if you fall behind, the next one still works.

| File | What it does |
|------|--------------|
| [`sql/1-create_tables.sql`](./sql/1-create_tables.sql) | Create the `tag_meta` table and the `tag_history` hypertable, and seed equipment metadata. **Run this first** — the consumer starts writing the moment the tables exist. |
| [`sql/2-explore_ingested_data.sql`](./sql/2-explore_ingested_data.sql) | Confirm rows are landing and join readings to their metadata. |
| [`sql/3-time_series_queries.sql`](./sql/3-time_series_queries.sql) | `last()`, `time_bucket()`, and quality-filtered aggregates. |
| [`sql/4-continuous_aggregates.sql`](./sql/4-continuous_aggregates.sql) | Build a self-updating 1-minute rollup with a refresh policy. |
| [`sql/5-bonus_compression.sql`](./sql/5-bonus_compression.sql) | *(Optional)* columnar compression + retention. |

Once file 1 runs, watch the consumer catch up:

```bash
docker compose logs -f consumer   # "wrote 50 readings to Tiger Cloud"
```

Then open Grafana at **http://localhost:3000** (login `admin` / the password in your `.env`). The **IIoT Overview** dashboard is pre-loaded and refreshes every 5 seconds — you'll see temperature, pressure, flow, and live current values fill in as data flows.

## How the pieces fit together

- The producer (in [`../data-producer`](../data-producer)) publishes CSV payloads (`tag_id,timestamp,value,quality`) to topics that encode the plant hierarchy: `workshop/<area>/<line>/<asset>/<metric>`.
- The consumer subscribes to `workshop/#`, derives the Unified Namespace path from each topic, auto-registers new tags into `tag_meta`, and batch-inserts readings into the hypertable.
- Grafana queries Tiger Cloud directly — it's just Postgres.

## Need help?

- **Workshop day:** ask in the chat
- **Anytime:** [docs.tigerdata.com](https://docs.tigerdata.com) or [Community Slack](https://slack.timescale.com)

### Troubleshooting

- **Consumer logs "tables not found"** — run `sql/1-create_tables.sql`; it'll start writing within a few seconds.
- **Consumer can't reach Tiger Cloud** — double-check the `TIGER_*` values in `.env`; the host must be reachable and `sslmode=require` is expected.
- **Consumer can't reach the broker** — for the shared broker, re-check `MQTT_BROKER_HOST/PORT/TLS/USERNAME/PASSWORD`; for a local feed, make sure `../data-producer` is up and `MQTT_BROKER_HOST=host.docker.internal`.
- **Grafana panels are empty** — confirm the consumer is writing (`docker compose logs consumer`) and that your dashboard time range covers "now".

## After the workshop

Your service stays up — keep going:

- Point the Grafana temperature/pressure panels at the `tag_history_1m` continuous aggregate instead of the raw table and compare query speed.
- Add your own tags: publish to a new `workshop/...` topic (see [`../data-producer`](../data-producer)) and watch the consumer auto-register it.
- Bring your own MQTT data — point the consumer at your real broker and keep the rest.
- Try the [Tiger MCP](https://www.tigerdata.com/docs/get-started/quickstart/mcp-cli) and ask your AI assistant to query the hypertable you just built.
