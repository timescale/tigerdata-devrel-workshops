# Devcontainer notes

Things that cost real debugging time while building workshop devcontainers. Read this
before building a new one.

Rescued from a `CLAUDE.md` that only ever existed on an unmerged branch of this repo, and
rewritten for the current layout: each workshop is its own repo with a single
`.devcontainer/devcontainer.json` at the default path, so the Codespaces badge needs no
`devcontainer_path` query string and no `/tree/<branch>` segment.

## Test locally — don't iterate through real Codespaces

You don't need to push and open a Codespace to try a `devcontainer.json` change. With
Docker running:

```bash
npx --yes @devcontainers/cli up \
  --workspace-folder . \
  --config .devcontainer/devcontainer.json \
  --remove-existing-container   # forces postCreateCommand to re-run
```

This builds the real image and runs `postCreateCommand`/`postStartCommand` for real,
reporting `"outcome": "success"` or an error. Then poke at it like any container:

```bash
CID=$(docker ps -a --filter "label=devcontainer.local_folder" --format '{{.ID}}' | head -1)
docker exec -u vscode "$CID" bash -lc 'command -v psql tiger jq'
docker rm -f "$CID"
```

The workspace folder is bind-mounted, so anything a script writes lands in your actual
checkout — `git status` after testing rather than committing stray files.

This caught four real bugs across two workshops that would otherwise only have shown up
after a slow manual Codespace rebuild. One of them was a path bug that survived code
review twice.

## Prefer apt or an official install script over community features

`ghcr.io/devcontainers-contrib/*` features have flaked during container creation — the
`postgresql-client` one failed to resolve, which is not something we control. Installing
from the tool's own apt repo or official installer inside `postCreateCommand` is more
reliable.

Where a feature *is* first-party and does real work (`ghcr.io/devcontainers/features/node`,
`ghcr.io/anthropics/devcontainer-features/claude-code`), it's fine — but if you're already
running a `postCreateCommand`, one mechanism usually beats two.

Commit the `devcontainer-lock.json` the CLI generates. It pins features by digest, which
is worth having when forty people build the same container on the same morning.

## Avoid Docker-in-Docker unless the workshop genuinely needs it

It's tempting for running a workshop's services, but if everything can run natively — a
Python process, an apt-installed service, a CLI talking to a remote hosted database —
that's simpler, faster to build, and has fewer moving parts for attendees to debug. Both
current workshops that reached for it later dropped it.

## `postCreateCommand` vs `postStartCommand`

- `postCreateCommand` runs once, at first build. Package installs, one-time file wiring.
- `postStartCommand` runs on every start, including the first. Use it for anything that
  depends on files an attendee creates mid-session — a `.env` that didn't exist at build
  time, say.

## Paths inside `.devcontainer/scripts/`

A script at `.devcontainer/scripts/foo.sh` reaches the repo root with `../..`, not
`../../..`. That extra level is a leftover from when this repo nested devcontainers per
workshop, and it has broken a build at least once since. If you copy a script from another
workshop repo, re-check its path arithmetic and then actually run it.

## Running a native service (e.g. Grafana) without Docker

Two non-obvious gotchas, both from `mqtt-grafana-workshop`:

1. **The packaged `service`/init.d script doesn't reliably work in a devcontainer.** It
   sources `/etc/default/grafana-server` but never `export`s what it reads, so custom
   `GF_*` env vars never reach the daemon. It also hard-codes a 1-second wait before
   checking the pidfile and reports `failed!` while the server is still starting.
   **Fix:** launch the binary directly with the env you need, and confirm it's up by
   polling its health endpoint rather than trusting the launcher's exit code.
2. **Devcontainer sudoers usually only grants passwordless `sudo` to become `root`**
   (`vscode ALL=(root) NOPASSWD:ALL`), so `sudo -u grafana …` hangs asking for a password
   that doesn't exist. Use `sudo runuser -u grafana -- …` instead.

Also: changing `GF_SECURITY_ADMIN_PASSWORD` after the admin user already exists in
Grafana's database does *not* retroactively change it. `grafana cli admin
reset-admin-password` is the actual way.

## Tiger CLI in a container

- **There is no system keyring.** Without `tiger config set password_storage pgpass`,
  `tiger auth login` appears to succeed and then every later command can't read the
  credentials back. This is the most common way the setup fails on Linux.
- **The install script honours `INSTALL_DIR`**, so
  `curl -fsSL https://cli.tigerdata.com | sudo INSTALL_DIR=/usr/local/bin sh` puts `tiger`
  on `PATH` for every shell. No symlinking afterwards.
- **`tiger auth login --headless`** prints a code and a URL to open anywhere. That's the
  flow designed for a terminal that can't open a browser, which is exactly a Codespace.
