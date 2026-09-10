#!/usr/bin/env bash
#
# Runs once, when the codespace is first created.
#
# Installs everything the attendee needs so that the only thing left to do by hand
# is authenticate — to Tiger Cloud, and to whichever coding agent they brought.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKSHOP_DIR="$REPO_ROOT/fork-break-fix-delete"

echo "==> Installing jq"
# No postgresql-client, and no database driver either. Every statement in this
# workshop, including the data load, goes through `tiger db query`.
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq

echo "==> Installing Tiger CLI"
# INSTALL_DIR is honoured by the install script. /usr/local/bin is on PATH for every
# shell in this image, which matters because attendees open fresh terminals a lot.
curl -fsSL https://cli.tigerdata.com | sudo INSTALL_DIR=/usr/local/bin sh

echo "==> Configuring Tiger CLI credential storage"
# There is no system keyring in a container. Without this, `tiger auth login` stores
# credentials successfully and then every later command cannot read them back.
# This is the single most common way this setup fails on Linux.
tiger config set password_storage pgpass

echo "==> Installing coding agents (claude, codex, copilot)"
npm install -g --silent @anthropic-ai/claude-code @openai/codex @github/copilot

# Nothing else to install. The dataset ships as gzipped SQL in data/load/ and
# loads through `tiger db query` -- no database driver, no client library, and
# nothing unpacked to disk.

cat <<'BANNER'

  ────────────────────────────────────────────────────────────────
   fork-break-fix-delete — container ready

   Installed: jq, tiger, claude, codex, copilot

   You still need to authenticate. Open
       fork-break-fix-delete/README.md
   and work through "Before the workshop". Budget about 20 minutes.

   Short version:
       tiger auth login --headless
       tiger mcp install claude-code     # or codex / copilot
       tiger service create --name fbfd-original --cpu shared --memory shared
  ────────────────────────────────────────────────────────────────

BANNER
