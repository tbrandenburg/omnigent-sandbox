#!/bin/bash
# Non-interactive entrypoint for the omnigent-host worker container.
#
# 1. `omnigent login <server>` in accounts mode prompts (via stdin) for a
#    username (defaults to "admin") and a password — no browser flow. We
#    pipe both values so this works headless under `docker compose up -d`.
#    Login stores a session JWT under ~/.omnigent/auth_tokens.json (in this
#    container's home dir), which `omnigent host` then picks up.
# 2. `omnigent host <server>` runs the tunnel client in the foreground
#    (long-lived, keeps the container alive), which `restart: unless-stopped`
#    re-dials automatically after crashes/restarts.
set -euo pipefail

: "${OMNIGENT_SERVER_URL:?OMNIGENT_SERVER_URL must be set}"
: "${OMNIGENT_ADMIN_USERNAME:=admin}"
: "${OMNIGENT_ADMIN_PASSWORD:?OMNIGENT_ADMIN_PASSWORD must be set (the server first-admin password)}"

echo "host-entrypoint: logging in to ${OMNIGENT_SERVER_URL} as ${OMNIGENT_ADMIN_USERNAME}"
printf '%s\n%s\n' "${OMNIGENT_ADMIN_USERNAME}" "${OMNIGENT_ADMIN_PASSWORD}" \
  | omnigent login "${OMNIGENT_SERVER_URL}"

echo "host-entrypoint: starting omnigent host tunnel to ${OMNIGENT_SERVER_URL}"
exec omnigent host "${OMNIGENT_SERVER_URL}"
