# Contributing a workshop

For the DevRel team and anyone building or maintaining a Tiger Data workshop. If you're
here to *take* a workshop, the [README](./README.md) is what you want.

## Start from the template

Use **[timescale/workshop-template](https://github.com/timescale/workshop-template)** →
*Use this template* → *Create a new repository*. Name it `<topic>-workshop` under the
`timescale` org.

You get the devcontainer, README skeleton, LICENSE, editor settings and a builder-facing
`CLAUDE.md` already in place. A one-shot workflow rewrites the Codespaces badge to point
at your new repo and then deletes itself, so the badge is never silently wrong.

Then read that repo's `CLAUDE.md` — it carries the conventions and the gotchas, and is
the more detailed version of everything below.

Add your workshop to the list in this repo's README once it's ready for people to find.

This repo used to hold all of them in subfolders. That broke down for a practical reason
worth knowing: a devcontainer nested at `.devcontainer/<workshop-name>/` needs a
`?devcontainer_path=` query string in its Codespaces link, and any relative paths inside
it are computed from a repo root that isn't the workshop root. One repo per workshop makes
both problems disappear.

## What a workshop repo contains

```
README.md                        attendee-facing: the whole product
LICENSE                          MIT
.devcontainer/devcontainer.json  at the default path, not nested
.devcontainer/post-create.sh     if setup needs more than one line
sql/1-*.sql, sql/2-*.sql, …      numbered, self-contained, re-runnable
```

Optional: `slides.pdf`, an `AGENTS.md` if a coding agent is part of the workshop, committed
datasets if the workshop needs them.

## The README is the product

Assume someone lands on it cold, a week before the session, with none of your context.
The shape that's worked:

1. **Title, Codespaces badge, one-paragraph pitch.** What they'll build, not what topics
   get covered.
2. **What you'll learn** — four or five bullets.
3. **Before the workshop — setup checklist.** Numbered. Ends with one command whose output
   proves they're ready, and a blunt statement of what happens if it doesn't work.
4. **During the workshop** — a table mapping each `sql/N-*.sql` to what it does, and a
   run-of-show if the timing is tight.
5. **Troubleshooting** — every failure you actually hit while building it. This section
   earns its length.
6. **After the workshop** — what to try next, and how to delete anything still running.

Two rules that keep biting us:

- **No hardcoded dates.** "Before workshop day", never "before May 28". These get reused,
  and a stale date is the first thing an attendee notices.
- **Numbers must be measured, not estimated.** If the README says a step takes two minutes,
  someone timed it. A wrong number is worse than no number — it turns "this is slow" into
  "this is broken".

## Codespaces

Put `devcontainer.json` at `.devcontainer/devcontainer.json` and the badge needs no query
string:

```markdown
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/timescale/<repo>)
```

While a workshop is still on a branch, add `/tree/<branch>` before the query string and
drop it once merged.

Standard settings across our workshops:

```json
"customizations": {
  "vscode": {
    "settings": {
      "workbench.secondarySideBar.defaultVisibility": "hidden"
    }
  }
}
```

**Read [`docs/devcontainer-notes.md`](./docs/devcontainer-notes.md) before building one.**
It's the accumulated list of things that cost real debugging time — the Tiger CLI's
keyring behaviour in containers, running native services without Docker, and how to test a
devcontainer locally instead of rebuilding Codespaces.

## Tiger CLI over psql

Newer workshops run every statement through `tiger db query` and don't install `psql` at
all. Fewer dependencies, and it exercises the tool we're actually shipping.

Two limits to design around, both measured:

- **`tiger db query` can't stream a local file into a `COPY`.** There's no
  `tiger db copy`, and piping a CSV into `-c "COPY … FROM STDIN"` hangs rather than
  erroring ([tiger-cli#227](https://github.com/timescale/tiger-cli/issues/227)). If your
  workshop needs to load a local dataset, ship it as gzipped `INSERT` statements and pipe
  them in with `gunzip -c … | tiger db query`.
- **A multi-statement file runs in one implicit transaction.** Anything that can't run
  inside a transaction block — `CREATE MATERIALIZED VIEW … WITH DATA`,
  `refresh_continuous_aggregate()` — fails with SQLSTATE 25001 when run via `-f`, and takes
  the whole file down with it. Run those statements individually with `-c`.

Also: `tiger db query`'s table renderer trims leading whitespace, which flattens `EXPLAIN`
plans so every node sits at the left margin. If reading plans matters to your workshop,
`-o json` preserves the indentation.

## Testing before you ship

- Build the devcontainer locally rather than opening real Codespaces:
  ```bash
  npx --yes @devcontainers/cli up --workspace-folder . \
    --config .devcontainer/devcontainer.json --remove-existing-container
  ```
- Run every SQL file end to end against a real service, and record the timings you put in
  the README.
- Delete every service you created. `tiger service list` before you call it done.
