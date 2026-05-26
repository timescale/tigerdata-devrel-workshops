# From Sensor to Insight: Real-Time IoT Analytics with TimescaleDB

A 60-minute hands-on workshop where you'll build a real IoT analytics pipeline on Tiger Cloud from scratch. You write the SQL, you run the queries, and you walk away with a working service you built yourself.

## What you'll learn

- **Hypertables** — turn a regular Postgres table into a time-series-optimized one
- **Columnar compression** — typically 5–10× storage reduction *and* faster queries
- **Continuous aggregates** — self-updating materialized views for real-time dashboards
- **Time-series queries** — `time_bucket()` and hyperfunctions like `last()`
- **Retention policies** — drop old data automatically

## Before the workshop — setup checklist

You need three things before we start. Do these **before May 28** — workshop day is a bad time to debug DNS.

### 1. Sign up for Tiger Cloud

Sign up at [console.cloud.timescale.com/signup](https://console.cloud.timescale.com/signup). You'll get **$1000 in trial credit**, which is way more than enough for this workshop and a bunch of follow-up experimentation.

### 2. Spin up a service

After signup, create a new service:

- **Type:** PostgreSQL with time-series and analytics
- **Region:** us-east-1
- **Compute:** the smallest paid SKU (0.5 CPU / 2 GB) — your trial credits cover this comfortably
- **Name:** anything you like (e.g. `iot-workshop`)

Once it's up, copy the connection string from the service overview. It looks like:

```
postgres://tsdbadmin:xxxxxxxx@xxxxxxxxxx.tsdb.cloud.timescale.com:39966/tsdb?sslmode=require
```

### 3. Install psql (recommended)

We'll use psql during the workshop. If you can't install it, the **Data** tab in the Tiger Cloud console works too — just slower.

```bash
# macOS
brew install libpq && brew link --force libpq

# Ubuntu / Debian
sudo apt install postgresql-client
```

Windows: see [How to install psql](https://www.tigerdata.com/blog/how-to-install-psql-on-mac-ubuntu-debian-windows).

### 4. Test your connection

A few days before the workshop, run:

```bash
psql "postgres://tsdbadmin:...your-connection-string..." -c "SELECT version();"
```

If you see a Postgres version string, you're set. If not, fix it before May 28.

---

### Power user path: `tiger-cli` (optional)

If you'd rather do setup from a terminal, [`tiger-cli`](https://github.com/timescale/tiger-cli) does everything the console UI does — and it bundles the MCP server we'll demo at the end of the workshop. Skip this if console + psql works fine for you.

**Install:**

```bash
# macOS / Linux / WSL
curl -fsSL https://cli.tigerdata.com | sh

# Or via Homebrew
brew install --cask timescale/tap/tiger-cli

# Windows (PowerShell)
irm https://cli.tigerdata.com/install.ps1 | iex
```

**Log in** (opens a browser, no API key juggling):

```bash
tiger auth login
```

**Create your workshop service + grab a connection string:**

```bash
tiger service create --name iot-workshop
tiger service list                  # confirm it's up
tiger db connection-string          # save this for later
```

**Connect:**

```bash
tiger db connect
```

`tiger db connect` shells out to local `psql` — you still need psql installed.

**Heads-up for Linux users:** if you don't have a desktop keyring daemon, `tiger auth login` may fail to save credentials silently. Fix with:

```bash
tiger config set password_storage pgpass
```

If `tiger-cli` is installed and logged in by workshop day, you'll be ready for the bonus MCP demo at the end.

---

## During the workshop

We'll work through the files in the [`sql`](./sql) directory, step by step. Either:

- **Recommended:** open each `*.sql` file locally and copy/paste each section into `psql` as we go
- **Alternative:** paste the whole file into the **Data** tab in the Tiger Cloud console

If you fall behind on a step, the next one will still work — each section is self-contained.

## Need help?

- **Workshop day:** ask in the Zoom chat — Doug will be monitoring
- **Anytime:** [docs.tigerdata.com](https://docs.tigerdata.com) or [tigerdata.com/contact](https://www.tigerdata.com/contact)

## After the workshop

Your service stays up — keep playing. Some ideas:

- **Try the Tiger MCP with your AI assistant of choice.** Once `tiger-cli` is installed, `tiger mcp install` wires it into Claude Code, Cursor, Windsurf, Codex, Gemini CLI, or VS Code automatically. (Claude Desktop is a manual JSON edit — see the [Tiger MCP docs](https://www.tigerdata.com/docs/get-started/quickstart/mcp-cli).) Then ask your assistant to query the hypertable you just built.
- Plug Grafana into your service and build a dashboard.
- Try [tiered storage to S3](https://docs.tigerdata.com/use-timescale/latest/data-tiering/) (we skipped it for time).
- Bring your own data and convert an existing Postgres table into a hypertable.

When your trial credits run out, the smallest paid service is a few bucks a month.
