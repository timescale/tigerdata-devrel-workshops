#!/usr/bin/env bash
#
# Runs once, when the codespace is first created.
#
# Installs everything the attendee needs so that the only thing left to do by hand
# is authenticate — to Tiger Cloud, and to whichever coding agent they brought.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKSHOP_DIR="$REPO_ROOT/fork-break-fix-delete"

echo "==> Installing psql and jq"
# apt directly rather than ghcr.io/devcontainers-contrib/features/postgresql-client,
# which has failed to resolve during container creation before (community feature
# registry flake, not something we control).
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client jq

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

echo "==> Decompressing the NYC 311 dataset"
# The .gz is committed; the .csv is gitignored. -k keeps the archive, -f makes this
# safe to re-run.
gunzip -kf "$WORKSHOP_DIR/data/nyc311_sample.csv.gz"

cat <<'BANNER'

  ────────────────────────────────────────────────────────────────
   fork-break-fix-delete — container ready

   Installed: psql, jq, tiger, claude, codex, copilot

   You still need to authenticate. Open
       fork-break-fix-delete/README.md
   and work through "Before the workshop". Budget about 20 minutes.

   Short version:
       tiger auth login --headless
       tiger mcp install claude-code     # or codex / copilot
       tiger service create --name fbfd-original --cpu shared --memory shared
  ────────────────────────────────────────────────────────────────

BANNER
