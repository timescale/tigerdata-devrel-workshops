# tigerdata-devrel-workshops

Hands-on workshops from the Tiger Data DevRel team. Each workshop is
self-contained in its own top-level folder (see root `README.md` for the
repo-wide conventions: one README per workshop, a row in the workshops table,
etc.).

## Devcontainer conventions

Workshops that need attendees to have specific tools installed use a
Codespaces devcontainer, one per workshop, at
`.devcontainer/<workshop-name>/devcontainer.json`. Attendees launch it via a
deep link in the workshop's README (skips the config picker):

```
https://codespaces.new/timescale/tigerdata-devrel-workshops?devcontainer_path=.devcontainer/<workshop-name>/devcontainer.json
```

**Branch scoping:** Codespaces reads `.devcontainer` from whatever branch/ref
you launch it on, not always from `main` — so a devcontainer can be built and
iterated on entirely within a feature branch before it's merged. The plain
deep link above defaults to the repo's default branch, though; to point it at
a specific branch while a workshop is still in progress, add a `/tree/`
segment before the query string:

```
https://codespaces.new/timescale/tigerdata-devrel-workshops/tree/<branch-name>?devcontainer_path=.devcontainer/<workshop-name>/devcontainer.json
```

Drop the `/tree/<branch-name>` once the workshop's devcontainer has merged to
`main`.

**Prefer apt-install over community devcontainer features for anything
critical.** `ghcr.io/devcontainers-contrib/*` features have flaked before
(see git history — the `postgresql-client` feature failed to resolve during
container creation). Installing directly via the tool's own official apt repo
in `postCreateCommand` is more reliable and is the established pattern here.

**Avoid Docker-in-Docker unless a workshop genuinely needs to run its own
containers.** It's tempting to reach for `docker-in-docker` + `docker-compose`
to run a workshop's services, but if everything can run natively in the
devcontainer instead (a Python process, a natively-installed service like
Grafana, `psql` talking to a remote hosted database), that's simpler, faster
to build, and has fewer moving parts for attendees to debug. See
`mqtt-to-dashboard` below for a worked example of moving off Docker-in-Docker.

### `postCreateCommand` vs `postStartCommand`

- `postCreateCommand` runs once, when the container is first built. Use it
  for anything that only needs to happen once: package installs, one-time
  file wiring (e.g. symlinking provisioning config into place).
- `postStartCommand` runs on every container start, including the first
  (right after `postCreateCommand`). Use it for anything that needs to run
  every time the container comes up, or that depends on files an attendee
  creates mid-session (like a `.env` file that didn't exist yet at build
  time).

### Running a native service (e.g. Grafana) without Docker

`mqtt-to-dashboard` installs Grafana OSS directly via apt
(`apt.grafana.com`) instead of running it in a container. Two non-obvious
gotchas surfaced while building this, both worth knowing before doing this
again for another workshop:

1. **The packaged `service`/init.d script doesn't reliably work inside a
   devcontainer.** It sources `/etc/default/grafana-server` but never
   `export`s what it reads, so custom `GF_*` env vars (needed for
   `${VAR}`-style substitution in Grafana provisioning YAML) never reach the
   daemon. It also has a hard-coded 1-second wait before checking the pidfile,
   which is too short and reports `failed!` even when the server is starting
   up fine (e.g. because Grafana's bundled-plugin auto-install is still
   downloading ~280MB on first boot — see `scripts/post-create.sh`'s
   `preinstall_disabled` setting, which avoids that entirely). **Fix:** don't
   use `service`/systemd at all — launch the binary directly with the env
   vars you need, and confirm it's actually up by polling its health endpoint
   instead of trusting the launcher's exit code.
2. **Devcontainer sudoers usually only grants passwordless `sudo` to become
   `root`**, not arbitrary service users (`vscode ALL=(root) NOPASSWD:ALL`).
   `sudo -u grafana ...` will hang/fail asking for a password that doesn't
   exist. Use `sudo runuser -u grafana -- ...` instead — `runuser` run as
   root doesn't need a password for the target user.

See `.devcontainer/mqtt-to-dashboard/scripts/reload-grafana-env.sh` for the
concrete pattern (also handles picking up `.env` changes an attendee makes
mid-workshop, and rotating the Grafana admin password via
`grafana cli admin reset-admin-password` — changing `GF_SECURITY_ADMIN_PASSWORD`
after the admin user already exists in Grafana's database does *not*
retroactively change it; the CLI command is the actual way to do that).

## Testing a devcontainer change without opening a real Codespace

You don't need to push and open a Codespace in the browser to iterate on a
`devcontainer.json` — the same container can be built and run locally with
the official CLI, as long as Docker Desktop is running:

```bash
npx --yes @devcontainers/cli up \
  --workspace-folder . \
  --config .devcontainer/<workshop-name>/devcontainer.json \
  --remove-existing-container   # forces postCreateCommand to re-run on repeat tries
```

This builds the actual devcontainer image, runs `postCreateCommand` and
`postStartCommand` for real, and reports a JSON result with `"outcome":
"success"` or an error. From there, inspect it exactly like any other
container:

```bash
CID=$(docker ps -a --filter "label=devcontainer.local_folder" --format '{{.ID}}' | head -1)
docker exec -u root "$CID" bash -c '...'   # poke around as root
docker exec "$CID" curl -sf http://localhost:3000/api/health   # hit a forwarded service directly
```

Note the workspace folder is bind-mounted, so anything a script writes into
it (e.g. a test `.env` file) lands on your actual host checkout too — clean
those up (`git status` after testing) rather than committing them. Tear the
test container down when done: `docker rm -f "$CID"`.

This caught three real bugs while building `mqtt-to-dashboard`'s devcontainer
(a path-resolution bug, the Grafana init.d issues above, and a log-file
permission issue) that would otherwise only have surfaced after a slow,
manual Codespace rebuild — worth doing this for any nontrivial devcontainer
change.
