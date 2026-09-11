# Tiger Data DevRel Workshops

Hands-on workshops from the Tiger Data Developer Relations team. Each one lives in its own
repo with everything attendees need — this repo is just the index.

## Workshops

| Workshop | Description | Format | Length |
|----------|-------------|--------|--------|
| [Sensor to Insight](https://github.com/timescale/sensor-to-insight-workshop) | Build a real-time IoT analytics pipeline on Tiger Cloud — hypertables, columnar compression, continuous aggregates, and retention policies. | Live virtual workshop | 60 min |
| [MQTT to Dashboard](https://github.com/timescale/mqtt-grafana-workshop) | Stream manufacturing sensor data from an MQTT broker into Tiger Cloud and visualise it in Grafana. | Live virtual workshop | 60 min |
| [Fork, Break, Fix, Delete](https://github.com/timescale/fork-break-fix-delete-workshop) | Point a coding agent at a database it's allowed to break — Tiger MCP, instant service forks, agent-driven schema surgery, and the guardrails that make it safe. | Live virtual workshop | 60 min |

Every workshop opens in GitHub Codespaces from a badge in its own README, so attendees
need nothing installed locally.

## Starting a new workshop

One workshop, one repo, named `<topic>-workshop` under the `timescale` org. Add a row to
the table above when it's ready for people to find.

What the existing repos have in common, and what's worth copying:

- **`README.md` is the whole product.** Attendee-facing: what they'll learn, a setup
  checklist to do *before* the session, a table of what runs during it, and
  troubleshooting. Assume someone lands on it cold, a week early.
- **A Codespaces badge at the top**, pointing at the repo with no query string:
  ```markdown
  [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/timescale/<repo>)
  ```
  That bare form works because `.devcontainer/devcontainer.json` sits at the default path.
- **Numbered, re-runnable SQL** (`sql/1-*.sql`, `sql/2-*.sql`…), each file self-contained
  and safe to run twice, so someone who falls behind can skip ahead.
- **No hardcoded dates.** "Before workshop day", not "before May 28" — these get reused.
- **Pre-work that fails loudly.** End the setup section with one command whose output
  proves the attendee is ready.

See [`docs/devcontainer-notes.md`](./docs/devcontainer-notes.md) before building a
devcontainer — it's a pile of things that cost us real debugging time.

## License

MIT — see [LICENSE](./LICENSE).
