# Fork, Break, Fix, Delete

**Let a coding agent do real database work — on a database it's allowed to break.**

A coding agent can read your codebase, run your tests, and open a pull request. Point it
at your database and the calculus changes: a bad migration isn't something you undo with
`git checkout`, so most teams draw a line the agent isn't allowed to cross.

This workshop moves the line instead of holding it. You'll wire Tiger MCP into the coding
agent you already use, fork a Tiger Cloud service into an instant isolated copy, and turn
the agent loose on a deliberately terrible schema — wrong data types, no indexes, no
hypertable. You'll watch it read `EXPLAIN` plans, search the Tiger Data docs through the
MCP server, hit a wall that no index can get it over, and fix the thing properly. Then
you'll measure the result, prove the original never moved, and throw the fork away.

## What you'll learn

- How to connect Tiger MCP to Claude Code, Codex, GitHub Copilot CLI, or any MCP-capable
  coding agent
- How to fork a Tiger Cloud service so agent-driven changes never touch the original
- How to have an agent diagnose slow queries from `EXPLAIN` plans and built-in Tiger Data
  documentation search
- How to apply hypertables and continuous aggregates through an agent, then verify the
  improvement instead of taking its word for it
- The guardrails — fork-first, `AGENTS.md`, read-only roles, permission rules — that make
  this safe to point at something that matters

---

## Before the workshop — setup checklist

**Budget 20 minutes, and do this the day before, not five minutes before.** This session is
60 minutes and it starts at the fork. If step 9 doesn't work for you, you won't be able to
follow along.

### 1. Get a Tiger Cloud account

Sign up at [tigerdata.com](https://www.tigerdata.com/). The free tier is enough for this
entire workshop — you need two services and you get two.

### 2. Open the Codespace

[**Open in GitHub Codespaces**](https://codespaces.new/timescale/tigerdata-devrel-workshops/tree/mattstratton/fork-break-fix-delete?devcontainer_path=.devcontainer/fork-break-fix-delete/devcontainer.json)

Give it a few minutes on first boot. It installs `psql`, `jq`, the Tiger CLI, and three coding
agent CLIs, and decompresses a 125 MB dataset. When it's done you'll see a banner in the
terminal.

Then move into the workshop directory and stay there:

```bash
cd fork-break-fix-delete
```

Everything below assumes you're in that directory. Launching your agent from here is what
makes it pick up `AGENTS.md` and `.claude/settings.json`.

### 3. Log in to the Tiger CLI

```bash
tiger auth login --headless
```

`--headless` prints a short code and a URL. Open the URL in any browser on any machine,
enter the code, pick your project. This is the flow designed for exactly this situation —
your terminal is inside a container in a datacenter and it cannot open your browser.

Check it worked:

```bash
tiger service list
```

### 4. Authenticate your coding agent

You bring your own. All three are already installed. Pick one — in order of how likely it
is to just work:

<details>
<summary><b>GitHub Copilot CLI</b> — zero friction, recommended if you're unsure</summary>

```bash
copilot
```

You're already authenticated to GitHub inside a Codespace, so there is nothing to log into.
If your Claude or ChatGPT login goes sideways ten minutes before the session, this is your
escape hatch.
</details>

<details>
<summary><b>Claude Code</b> — needs a Claude Pro/Max subscription or an API key</summary>

```bash
claude
```

Follow the prompt. **If the browser sign-in completes but nothing happens in the terminal**,
copy the code shown in the browser and paste it at the `Paste code here if prompted` prompt.
Codespaces doesn't always route the localhost callback back into the container.

To survive a container rebuild, generate a long-lived token:

```bash
claude setup-token
```

and store the result as a
[user-level Codespaces secret](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces)
named `CLAUDE_CODE_OAUTH_TOKEN` (or use `ANTHROPIC_API_KEY`). Codespaces injects secrets as
environment variables automatically. Note that `~/.claude` survives stopping and starting a
codespace, but is wiped by a rebuild.
</details>

<details>
<summary><b>Codex</b> — read this one before the workshop, not during</summary>

```bash
codex login --device-auth
```

**You must enable "Device Code Authorisation" in your ChatGPT security settings first.**
It is off by default, it is an account-level toggle, and if you skip it you will discover
that fact in the middle of the session. Plain `codex login` won't work here either — it
spins up an OAuth callback on `localhost:1455` that the browser on your laptop can't reach.

`codex login --api-key` is the fallback if you have an OpenAI API key.
</details>

### 5. Install Tiger MCP into your agent

```bash
tiger mcp install claude-code    # or: codex | copilot
```

Then start your agent and ask it something like *"list my Tiger Cloud services"*. If it
comes back with a list, the MCP server is wired up. If it says it has no such tool, restart
the agent so it re-reads its config.

### 6. Create your service

```bash
tiger service create --name fbfd-original --cpu shared --memory shared
```

`--cpu shared --memory shared` is the free tier. It takes about 20 seconds. Free services
live in `us-east-1` only, and they fork in about 30 seconds, which is the entire reason
this workshop fits in an hour.

Look at the **Service ID** in the output. It's ten characters, and it is unique to you —
this is not something you can copy out of these docs. *That*, not the name, is what the
Tiger CLI addresses services by. Names are display labels.

The transcript below is illustrative, not copy-pasteable — substitute your own ID:

```console
$ tiger db connection-string fbfd-original
Error: no entries with that projectID:serviceID combination could be found

$ tiger db connection-string <your-service-id>
postgresql://tsdbadmin:...@<your-service-id>.<project>.tsdb.cloud.timescale.com:36821/tsdb?sslmode=require
```

Run these two for real — the first prints your ID, the second proves it works:

```bash
tiger service list                                   # find your Service ID
tiger db connection-string "$(scripts/sid fbfd-original)"
```

Rather than have you paste ten random characters into fifteen commands, this workshop
ships three small helpers:

```bash
scripts/sid     fbfd-original       # your service's ID
scripts/conn    fbfd-original       # the full connection string, password included
scripts/explain fbfd-original -f sql/2-baseline.sql
```

`tiger db query` is how you run SQL — it talks to the service directly and doesn't need
psql installed at all:

```bash
tiger db query "$(scripts/sid fbfd-original)" -c "SELECT count(*) FROM service_requests"
tiger db query "$(scripts/sid fbfd-original)" -f sql/1-bad-schema.sql
```

`scripts/explain` is the same thing for anything containing an `EXPLAIN`. The table
renderer trims leading whitespace from results, which is invisible for normal rows but
flattens an EXPLAIN plan so every node sits at the left margin and you can't see what's
nested in what. The helper asks for `-o json` instead and unwraps it, which keeps the
indentation.

We still use `psql` for exactly one thing — the ingest — because loading a local CSV needs
psql's `\copy`, and `tiger db query` has no way to stream a file from your machine.

> **On a paid service?** It all works. Two differences: forking takes about 2.5 minutes
> instead of 30 seconds (restore-and-replay rather than copy-on-write), and the baseline
> queries are only about half as slow, so the before/after is less dramatic. Use
> `--last-snapshot` instead of `--now` to get most of the speed back — we measured that at
> roughly a minute, with all the data present.

### 7. Create the bad schema

```bash
tiger db query "$(scripts/sid fbfd-original)" -f sql/1-bad-schema.sql
```

Ten columns, all `text`. No keys, no indexes, no hypertable. It's meant to hurt.

### 8. Have your agent load the data

This is the first thing you'll ask an agent to do. Start it (`claude`, `codex`, or
`copilot`) from the `fork-break-fix-delete` directory and give it this:

> **Prompt 1 — ingest**
>
> ```
> Load the NYC 311 dataset in data/nyc311_sample.csv into the service_requests
> table on the Tiger Cloud service named fbfd-original. The CSV has a header row
> and its columns are already in the same order as the table.
>
> Use psql's \copy so the file is read from this machine — tiger db query
> can't stream a local file. Get the connection string by running
> scripts/conn fbfd-original; don't ask me for credentials.
>
> When you're done, tell me the row count and the earliest and latest created_date.
> ```

It should come back with 1,000,000 rows spanning January to late April 2024.

### 9. Confirm you're ready

```bash
tiger db query "$(scripts/sid fbfd-original)" -c "SELECT count(*) FROM service_requests"
```

One million rows. The upload takes about 15 seconds. **If you don't see that, fix it before
the session** — post in the workshop channel, don't wait for the day.

---

## During the workshop

60 minutes. Each section is self-contained, so falling behind on one doesn't lock you out
of the next.

| Time | What happens |
|------|--------------|
| 0–10 | **Framing.** Why `git` makes agents safe on code, why databases don't get that for free, and what a fork buys you. Quick check that everyone's pre-work landed. |
| 10–20 | **Break.** Run `sql/2-baseline.sql` and read the `EXPLAIN` plan together. |
| 20–25 | **Fork.** One command, about a minute, and repoint your agent at the copy. |
| 25–45 | **Fix.** Prompts 2 and 3. Watch the agent diagnose, hit the wall, search the docs, and operate. |
| 45–55 | **Verify.** `sql/3-verify-fix.sql` on the fork, `sql/4-compare-original.sql` on the original. |
| 55–60 | **Delete.** Throw the fork away. Guardrails recap. |

### The files

| File | What it does | Run it against |
|------|--------------|----------------|
| `sql/1-bad-schema.sql` | Creates the deliberately broken table | `fbfd-original` (pre-work) |
| `sql/2-baseline.sql` | Times two dashboard queries and shows their plans | `fbfd-original` |
| `sql/3-verify-fix.sql` | The *same two queries*, plus what the agent changed | `fbfd-fork` |
| `sql/4-compare-original.sql` | Proves the original is untouched | `fbfd-original` |
| `AGENTS.md` | The guardrail your agent reads. You'll edit it in step 3. | — |
| `.claude/settings.json` | Permission rules — the fence, as opposed to the sign | — |
| `scripts/sid` | Service name → service ID | — |
| `scripts/conn` | Service name → connection string (only needed for the `\copy` ingest) | — |
| `scripts/explain` | `tiger db query` with EXPLAIN indentation intact | — |

---

### Step 1 — Break: measure how bad it is

```bash
scripts/explain fbfd-original -f sql/2-baseline.sql
```

Write all three timings down. On a free-tier service, measured on 1,000,000 rows:

| Query | What it asks | Baseline |
|-------|--------------|----------|
| Q1 — one day of complaints by type | narrow, recent window | **~2,900 ms** |
| Q2 — median time to close, same day | narrow window, more work per row | **~2,950 ms** |
| Q3 — daily counts, whole dataset | no filter, touches everything | **~3,470 ms** |

Three seconds to render one day of a dashboard. Sit with that for a second.

Two things to notice in the Q1 plan:

1. **`Seq Scan on service_requests`** with `rows=1000000`. You asked for one day out of four
   months — about 0.8% of the table — and it read all of it. There is no index, so there is
   no other option.
2. The `created_date::timestamptz` cast is in the filter, which means Postgres has to
   convert a million strings into timestamps *before* it can decide which rows you wanted.

If you're feeling clever, try to fix #1 the obvious way:

```sql
CREATE INDEX ON service_requests ((created_date::timestamptz));
```

```
ERROR:  functions in index expression must be marked IMMUTABLE
```

Text-to-timestamptz depends on the session's `TimeZone`, so it's `STABLE`, not `IMMUTABLE`,
and Postgres won't index it. **There is no index that saves you from a wrong data type.**
Hold onto that — your agent is about to run into the same wall.

### Step 2 — Fork

```bash
time tiger service fork "$(scripts/sid fbfd-original)" --now --name fbfd-fork
```

Watch the clock. **We measured 29.7 seconds** with all million rows in place. On the free
tier this is copy-on-write — it isn't copying 156 MB anywhere, so the time barely depends
on how much data you have.

The fork inherits the parent's sizing, so it comes out on the free tier too. You don't need
to pass `--cpu`/`--memory`.

You now have two independent databases with identical contents. `fbfd-fork` is expendable.

> On a paid service the same fork took **2 minutes 35 seconds**, because it's a real
> restore-and-replay rather than copy-on-write. `--last-snapshot` brought that down to
> roughly a minute and still had all million rows.

### Step 3 — Repoint the guardrail

Open `AGENTS.md` and change one line:

```diff
- TARGET SERVICE: fbfd-original
+ TARGET SERVICE: fbfd-fork
```

Small edit, and it's the whole safety model. Everything after this happens on the copy.

### Step 4 — Fix: turn the agent loose

Two prompts. Give it the first one and **let it finish before you give it the second** —
the diagnosis is the interesting part and it's easy to skip past.

> **Prompt 2 — diagnose (don't let it change anything yet)**
>
> ```
> The query in sql/2-baseline.sql marked "Q1" is too slow to put behind a
> dashboard. Figure out why.
>
> Run it against the target service, read the EXPLAIN ANALYZE output, and
> investigate the schema. Then explain to me, in plain language, what the actual
> problem is and what you'd do about it.
>
> Do not change anything yet. I want the diagnosis first.
> ```

> **Prompt 3 — operate**
>
> ```
> Go ahead and fix it. This is a fork, so you have room to be wrong.
>
> Constraints:
> - Q1, Q2 and Q3 in sql/3-verify-fix.sql must keep working with their text
>   unchanged. Make the schema fast; don't rewrite the question.
> - Preserve all 1,000,000 rows, and the answers must not change.
> - Use TimescaleDB features where they're the right tool. Check syntax with
>   search_docs rather than working from memory.
> - Report EXPLAIN ANALYZE before and after for all three.
>
> Then, separately: Q3 has to aggregate the entire table, so I don't expect the
> schema change alone to help it much. Build me a continuous aggregate that
> answers the same question, and name the view daily_complaints with a column
> called day. Tell me what I give up by having to query it explicitly instead of
> it just making Q3 faster.
> ```

Prompt 2 is deliberately vague. The point is to watch an agent reason about a database
rather than follow your recipe.

**What to watch for:**

- Does it try the expression index and hit the `IMMUTABLE` error? Most do. What it does
  *next* matters more than whether it happens.
- Does it use `search_docs`, or does it write hypertable syntax from memory? (The syntax
  changed across versions. Memory is often wrong.)
- Does it convert `created_date` to `timestamptz` before or after creating the hypertable?
  There's only one order that works, and finding out the hard way costs a table rewrite.
- Does it notice that Q3 didn't improve, or does it round "two out of three got faster"
  up to "fixed"?
- Does it actually re-run `EXPLAIN`, or does it just tell you it's faster now?

That last one is the real lesson. An agent reporting a result it didn't measure is the same
failure mode whether it's touching your database or your test suite.

### Step 5 — Verify

On the fork:

```bash
scripts/explain fbfd-fork -f sql/3-verify-fix.sql
```

Q1, Q2 and Q3 are byte-for-byte the same queries you ran in step 1. Here's what we measured
on a free-tier service, before and after:

**Run it twice.** The first query against a brand-new fork reads from cold storage — we
measured Q1 at 87 ms on the first run and 5 ms on the second. The second run is the honest
number.

| Query | Before | After | |
|-------|--------|-------|---|
| Q1 — one day of complaints | ~2,900 ms | **~5 ms** | **~550x** |
| Q2 — median time to close | ~3,000 ms | **~90 ms** | **~33x** |
| Q3 — daily counts, everything | ~3,700 ms | ~1,800 ms | **~2x** |
| Q4 — same as Q3, via the continuous aggregate | — | **~110 ms** | ~33x vs Q3 before |

**Then look at Q3 and notice it barely moved.** That is the most useful result in the whole
workshop. Correct types, a hypertable, and a well-chosen index all make queries faster by
letting them *read less*. Q3 aggregates every row in the table, so there is nothing to skip
— chunk exclusion has nothing to exclude, and an index on a column you aren't filtering on
is dead weight.

Q4 is the answer to that, and it's a different query on purpose: it hits the continuous
aggregate. Nothing rewrites Q3 for you. You buy the speed by doing the aggregation in
advance and then agreeing to ask for it by name. That trade is worth understanding before
you let an agent make it on your behalf.

Then on the original:

```bash
tiger db query "$(scripts/sid fbfd-original)" -f sql/4-compare-original.sql
```

Still all `text`. Still not a hypertable. Still no indexes. Still a million rows. Your agent
just rewrote table types and built continuous aggregates and none of it reached here.

### Step 6 — Delete

```bash
tiger service delete "$(scripts/sid fbfd-fork)" --confirm
tiger service list
```

Gone. That's the part people skip and it's half the point: the fork was never precious, so
nothing about this workflow depends on the agent being careful.

---

## The guardrails, in order of how much you should trust them

1. **The fork itself.** Structural. The agent cannot damage what it isn't connected to.
   Everything else on this list is a refinement of this one idea.
2. **A read-only connection to anything real.** `scripts/conn fbfd-original --read-only`
   hands your agent a connection string that the *server* refuses writes on. Not a role you
   have to remember to grant, not a convention — the connection itself is in read-only mode.
   Try it:

   ```console
   $ psql "$(scripts/conn fbfd-original --read-only)" -c "SELECT count(*) FROM service_requests;"
    1000000

   $ psql "$(scripts/conn fbfd-original --read-only)" -c "CREATE TABLE agent_was_here(x int);"
   ERROR:  cannot execute CREATE TABLE in a read-only transaction

   $ psql "$(scripts/conn fbfd-original --read-only)" -c "DROP TABLE service_requests;"
   ERROR:  cannot execute DROP TABLE in a read-only transaction
   ```

   Reads work. Writes and DDL don't. This is the one to reach for when an agent needs to
   understand production but has no business changing it.

   One caveat we hit while building this: a **fork of a free service currently refuses
   read-only connections outright** — `FATAL: cannot disable read-only mode`. Read-only
   works on the original, which is where you'd actually want it. It's also why the
   "what changed?" section of `sql/3-verify-fix.sql` asks in SQL rather than using
   `tiger db schema`, which always connects read-only.
3. **Permission rules.** `.claude/settings.json` in this folder denies
   `tiger service delete`, `stop`, and `update-password`. The agent doesn't get to make
   lifecycle decisions. This is a fence — it's checked before the command runs.
4. **`AGENTS.md`.** This is a sign, not a fence. It's genuinely useful — agents follow it
   most of the time — but "most of the time" is doing real work in that sentence. Never let
   a written instruction be the only thing between an agent and something you can't rebuild.

The ordering is the takeaway. Teams tend to invest in #4 and skip #1, which is backwards.

---

## Need help?

Ask in the workshop chat. If you're stuck on setup, paste the exact command and the exact
error — "it didn't work" is hard to help with and we're on a 60-minute clock.

## Troubleshooting

**`no entries with that projectID:serviceID combination could be found`**
You passed a service *name* where the CLI wanted a service *ID*. Names are display labels;
`tiger db connection-string`, `tiger service get`, `tiger service fork` and
`tiger service delete` all take the ten-character ID. Use `scripts/sid <name>` to get an
ID, `scripts/conn <name>` for a connection string, or read them off `tiger service list`.

**`tiger` commands fail with a keyring or credential error**
No system keyring exists inside a container. The setup script runs
`tiger config set password_storage pgpass` for you, but if you're on your own Linux machine
rather than the Codespace, run it yourself and log in again.

**`codex login` hangs, or the browser can't reach `localhost:1455`**
Use `codex login --device-auth`, and make sure "Device Code Authorisation" is enabled in
your ChatGPT security settings. See step 4 above.

**Claude Code's browser sign-in completes but the terminal doesn't notice**
Copy the code from the browser and paste it at the `Paste code here if prompted` prompt.
The localhost callback doesn't always route back into a Codespace.

**Your agent says it has no Tiger tools**
Re-run `tiger mcp install <client>` and restart the agent — most agents read their MCP
config only at startup.

**The database went read-only mid-ingest**
Free services have a storage cap and flip to read-only when they hit it. We did not hit it:
the loaded table is 156 MB, the database sits at 167 MB, and it peaked around 216 MB during
the type conversion — all fine. If you do hit it, check `tiger service list`, then either
load a smaller slice of the CSV or move to a paid service.

**`tiger service fork` refuses to run**
A service has to be `Running` or `Paused` to be forked, never `In progress`. Wait for
`tiger service list` to settle and try again.

**The fork is taking 15 minutes**
You're on a paid service, which uses restore-and-replay rather than copy-on-write. Use
`--last-snapshot` instead of `--now` — it's the fast path.

**`refresh_continuous_aggregate() cannot run inside a transaction block`**
`tiger db query` wraps a multi-statement call in one implicit transaction, and refreshing a
continuous aggregate can't happen inside one. The whole batch rolls back, so the view
silently doesn't exist afterwards. Split it into two calls: one to `CREATE MATERIALIZED
VIEW ... WITH NO DATA`, a second to `CALL refresh_continuous_aggregate(...)`. Worth telling
your agent up front — it's in `AGENTS.md`.

**`tiger db schema` fails on the fork with `cannot disable read-only mode`**
Known: a fork of a free service refuses read-only connections, and `tiger db schema` always
connects read-only. Use it against `fbfd-original`, and use the SQL introspection queries at
the bottom of `sql/3-verify-fix.sql` for the fork. Ordinary read-write queries against the
fork are unaffected.

**Your EXPLAIN plan is flat, with every node at the left margin**
You ran it through `tiger db query` directly. Its table renderer trims leading whitespace,
which destroys the plan's nesting. Use `scripts/explain` instead.

**Q3 didn't get faster**
Expected. See step 5 — Q3 has to touch every row, so partitioning can't help it. That's
what Q4 and the continuous aggregate are for.

**Q1 or Q2 got *slower* after the fix**
That's a real finding, not a broken workshop. Ask the agent why and make it show you the
plan. A common cause: an index that doesn't match the query's filter, so the planner picks
it and then has to go back to the heap for everything.

**The fork ran out of storage mid-fix**
Changing a column's type rewrites the whole table, so the old and new copies both exist for
the duration — roughly 350 MB at peak against a 156 MB starting table. There is no clever
way around that (`ALTER COLUMN ... TYPE` rewrites just the same as `CREATE TABLE` +
`INSERT ... SELECT`), so the lever is fewer rows. Reload with a slice:

```sql
DELETE FROM service_requests WHERE created_date::timestamptz >= '2024-03-01';
VACUUM FULL service_requests;
```

or regenerate a smaller CSV with `ROWS=250000 scripts/make-dataset.sh`.

## After the workshop

Things worth trying on your own:

- **Fork something real.** Point this workflow at a staging database with a schema you
  actually inherited. Ask an agent to explain it to you before you ask it to change anything.
- **Fork to plan a migration.** `tiger service fork --to-timestamp` gives you the database
  as it was at a specific moment, which is a very good way to rehearse a migration against
  production-shaped data.
- **Wire the read-only role in.** Give your agent a `--read-only` connection string to
  production and a read-write one to a fork, and see how much useful work it can do without
  ever holding a write handle to anything that matters.
- **Keep the `AGENTS.md`.** Copy it into a real repo and adapt it. The `TARGET SERVICE` line
  pattern generalises further than you'd think.

Don't leave services running you aren't using:

```bash
tiger service list                       # names and IDs
tiger service delete <service-id> --confirm
```

## Regenerating the dataset

`data/nyc311_sample.csv.gz` is committed, so you don't need to. If you want a different
slice, `scripts/make-dataset.sh` documents how it was built from
[NYC Open Data](https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9).
