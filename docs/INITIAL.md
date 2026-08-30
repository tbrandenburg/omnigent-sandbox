# Omnigent Sandbox — Initial Setup Plan

**Goal:** A simple, robust, best-practice Docker setup where the Omnigent
server and a dedicated worker/host (running the workspace + OpenCode) are
containerized, and any client only needs a browser to chat with an agent —
zero LLM API keys required, using OpenCode's built-in free model.

## What you get when this plan is done

- A running, validated Docker stack (server + Postgres + a self-hosted
  OpenCode worker) on this one machine, reachable from a browser with zero
  LLM keys, zero registry, zero git-remote credentials.
- **As of step 7:** a working deployment only — no `LICENSE`, no root
  `README.md`, no `.gitignore`, no first commit. Not yet publishable.
- **As of step 8 (added below):** a GitHub-publishable repo root — MIT
  `LICENSE`, `README.md`, `.gitignore`, committed `.env.example`, pinned
  version references, and a verified-clean first commit with no secrets.
  This is the point at which "state-of-the-art repo root before GitHub
  publishment" is actually satisfied.

## Architecture

```
┌────────────┐        HTTPS/WSS        ┌───────────────────┐        WS tunnel        ┌──────────────────────┐
│  Client     │ ──────────────────────▶│  omnigent-server    │◀───────────────────────│  omnigent-host        │
│ (browser)   │   web UI / API          │  (FastAPI, no keys, │   /v1/runner/tunnel     │  (OpenCode CLI,       │
└────────────┘                          │   no agent code)     │                         │   workspace volume)   │
                                         └───────┬─────────────┘                         └──────────────────────┘
                                                 │
                                          Postgres (state)
```

- **Server**: stateless w.r.t. agent execution. Owns sessions, auth, web UI, persistence.
- **Host (worker)**: the only container that runs OpenCode and touches the workspace.
- **Client**: browser only. No local install, no credentials.

This is the "server + explicit self-hosted host" mode — not direct mode
(single-machine, no split) and not managed sandboxes (ephemeral,
provider-provisioned containers), because we have one fixed, persistent
workspace we want to keep reusing.

## No LLM keys needed

OpenCode ships a built-in free model, `opencode/big-pickle`, which works
**out of the box with no `opencode auth login` and no credentials at all** —
no `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` or any external gateway credential
is required. (Other `opencode/*-free` / `openrouter/*:free` models may still
require `opencode auth login` against OpenCode's hosted provider — not
needed here since we standardize on `big-pickle`.) The host container only
needs the OpenCode CLI itself; no secret-bearing env vars or auth step for
model access.

## Non-negotiables (KISS + robust)

1. Single `docker-compose.yaml`, two services (`server`, `host`) + Postgres. No extra moving parts.
2. Secrets only in `.env` (git-ignored) — and with the free model, there should be none beyond the server's own auth/cookie secret.
3. Auth is on (`OMNIGENT_AUTH_ENABLED=1`) from day one — never expose an unauthenticated server, even on a private network.
4. Host image is reproducible: pinned base tag, explicit OpenCode CLI version pin within Omnigent's supported range.

## OpenCode harness selection

Use `harness: opencode-native` (the bare `opencode` id is just a legacy alias
that canonicalizes to the same `opencode-native` code path — confirmed in
`omnigent/harness_plugins.py`'s `harness_modules`/alias registry; there is no
separate SDK-only `opencode` executor in this codebase). `opencode-native`
drives a real, runner-owned `opencode serve` process over HTTP/SSE
(`omnigent/inner/opencode_native_harness.py` → `OpenCodeNativeExecutor`,
`opencode_native_bridge.py`), which is exactly the "resident process the
user can attach to and take over in the web UI" model this plan needs. Agent
YAML:

```yaml
executor:
  type: omnigent
  config:
    harness: opencode-native
```

## OpenCode version compatibility

Omnigent's `opencode-native` harness enforces a version gate
(`omnigent/opencode_native_client.py`):

```
OPENCODE_MIN_VERSION           = "1.17.7"
OPENCODE_MAX_VERSION_EXCLUSIVE = "1.19.0"
```

- Verified locally: `opencode --version` → `1.18.25` — **inside** the
  supported range. No action needed today, but the host image must pin
  `opencode` to a version in `[1.17.7, 1.19.0)` and this range must be
  re-checked whenever Omnigent is upgraded.
- Do **not** rely on `OMNIGENT_OPENCODE_SKIP_VERSION_CHECK` to bypass a
  mismatch — treat a failing gate as a signal to pin an in-range version,
  not to suppress the check.
- **Pin Omnigent itself too**: latest stable is `0.11.0` (PyPI + GitHub
  Releases + CHANGELOG.md agree, released 2026-08-24/25). Pin both the
  server and host images to this exact release, not `main`, so the two
  stay in lockstep with each other and with the OpenCode version range
  as both projects evolve.

## Auth mode: `accounts` is sufficient

The deploy docs' warning that *managed sandboxes* need `header`/`oidc` auth
does **not** apply to this plan's manually-registered, persistent host.
Confirmed by reading the tunnel auth code
(`omnigent/server/routes/runner_tunnel.py:83-118`, `264-340`;
`omnigent/runner/_entry.py:464-560`): a manual `omnigent login` +
`omnigent host` presents the **user's own real accounts/OIDC bearer token**
on the tunnel WebSocket, which `_resolve_tunnel_owner()` resolves normally.
The 403 dial-back problem is specific to *server-provisioned* managed
sandboxes, where the runner never ran `omnigent login` and only holds a
server-minted binding token. **Keep the plan's original choice: built-in
`accounts` auth (`OMNIGENT_AUTH_ENABLED=1`, no OIDC vars) works fine for
this self-hosted host.** No change needed.

## Bootstrap script is already unattended

`deploy/docker/bootstrap.sh` is fully non-interactive as-is: it copies
`.env.example` → `.env` if missing, requires `openssl` (hard-fails with a
clear error if absent, no prompt), and idempotently fills in
`POSTGRES_PASSWORD`, `OMNIGENT_OIDC_COOKIE_SECRET`, and
`OMNIGENT_ACCOUNTS_COOKIE_SECRET` only if unset — no `read` calls, no
confirmation gates. Safe to call directly in first-boot automation. The
*only* interactive step in the whole flow is the separate, later first-admin
creation through the web UI (an app-level step, not part of this script) —
capture that explicitly as a one-time manual action after first
`docker compose up -d`, or script it via
`OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD` if fully hands-off setup is needed
(see `deploy/README.md`'s auth table).

## Deployment target: single machine, no registry, no git push

Both containers run on this one machine only — no remote hosts, no
container registry, no GitHub token, and no plan to push workspace changes
to a remote. This simplifies several earlier open items:

- **No registry push.** Build the host image locally (`docker build ... -t
  omnigent-host:local`) and reference that local tag directly in
  `docker-compose.yaml`. No `docker push`, no registry credentials anywhere.
- **No git credentials in the host container.** The workspace volume can be
  a plain directory; it does not need to be a git remote, and no
  `GIT_TOKEN`/PAT is configured. If git history is wanted later, `git init`
  locally without a remote — still no token required.
- **No public TLS domain needed.** Client and both containers are on the
  same machine/LAN, so the reverse-proxy/HTTP-2 step (below) becomes
  optional hardening rather than a hard requirement — keep it if more than
  one browser tab/session will be open concurrently (avoids the HTTP/1.1
  6-connection stall), otherwise `http://localhost:6767` direct is fine for
  single-session local use.

## Workspace directory contract

No git-repo or config-file (`opencode.json`, `AGENTS.md`) precondition was
found anywhere in Omnigent's `opencode_native_*` code (exhaustive grep,
zero hits). `OpenCodeServer.start()` in `opencode_native_app_server.py`
launches `opencode serve` with `cwd` set directly to the mounted workspace
path, and the TUI attach path passes the same directory via `--dir`. So: the
mounted workspace volume can be handed to OpenCode as-is, empty or
otherwise — no bootstrapping step is required before first use.

**Unknown, accepted as-is:** whether the `opencode` binary itself (as
opposed to Omnigent's wrapper code) has any undocumented internal
preference for a pre-existing git repo. Not verified either way, and since
no git remote/push is planned for this deployment there is nothing to
configure regardless of the answer — if OpenCode wants a local `.git` for
some internal feature (e.g. diffing), `git init` with no remote satisfies
that at zero credential cost. Confirm empirically during step 7's
validation pass; not a blocker for building.

## Port allocation

Checked currently-listening ports on this machine (`ss -ltnp`): `22, 53,
631, 3000, 3001, 3010, 5173, 7080, 7233, 8010, 8088, 8181, 8200, 8300, 8888,
9090` are taken.

The upstream compose stack only exposes one host port: the server, mapped
`"${OMNIGENT_PORT:-8000}:8000"` (`deploy/docker/docker-compose.yaml:154-155`).
Postgres has **no host port mapping** — it's reachable only over the
internal Docker network (`postgres:5432`), so it can never collide with
anything else on this host regardless of what else runs here.

- **`8000` (server, default) is currently free** — no override needed today.
- Don't hardcode it though: set `OMNIGENT_PORT` in `.env` so the mapping is
  a one-line change if this machine's port usage shifts later, and re-run
  `ss -ltnp | grep <port>` (or `ss -ltn 'sport = :<port>'`) before every
  fresh deploy/redeploy to confirm the chosen port is still free — treat
  this as a pre-flight check, not a one-time fact.
- If a reverse proxy is added later (optional TLS/HTTP-2 step), its
  host-exposed port (typically `80`/`443`) needs the same free-port check;
  `80`/`443` are currently free on this machine too.
- The `host` (worker) container needs **no host port mapping at all** — it
  only makes an *outbound* WebSocket connection to the server
  (`/v1/runner/tunnel`); nothing needs to bind or be exposed on the host for
  it.

## Plan

### 1. Bootstrap the server

- [ ] Copy `deploy/docker/` compose stack (server + Postgres) from upstream Omnigent, pinned to release `v0.11.0` (not `main`), as the base.
- [ ] Confirm the target host port is free (`ss -ltn 'sport = :8000'` or `sport = :${OMNIGENT_PORT}`) — `8000` is free on this machine as of this writing; set `OMNIGENT_PORT` in `.env` to override if that changes.
- [ ] Run `./bootstrap.sh` (already unattended — see above) to mint `.env` secrets — the only secrets in this setup.
- [ ] Set `OMNIGENT_ACCOUNTS_BASE_URL` to the server's real reachable URL.
- [ ] Start with `docker compose up -d` and verify `GET /health`.
- [ ] Create the first admin account via the web UI on first boot (or set `OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD` for a fully unattended first boot); capture/rotate the password.

### 2. Build a custom host image with OpenCode

- [ ] Build from `docker/Dockerfile --target host` pinned to the same `v0.11.0` Omnigent release as the base (or a minimal Node image if the other coding-harness CLIs aren't needed beyond OpenCode).
- [ ] Install a pinned, in-range OpenCode version, e.g. `npm install -g opencode-ai@1.18.25` (verify exact package name/install command against OpenCode's own install docs).
- [ ] No auth/login step needed — `opencode/big-pickle` works with zero configuration.
- [ ] Run the container process as a dedicated non-root user with write access scoped only to the mounted workspace volume.
- [ ] Build and tag locally (e.g. `docker build -f docker/Dockerfile --target host -t omnigent-host:local .`) — no registry push, single machine only.

### 3. Wire the host container into compose

- [ ] Add a `host` service to the compose stack using the custom image from step 2.
- [ ] Mount the workspace directory as a named volume (or a bind mount, since server/host/client are all this one machine — reproducibility across other hosts isn't a concern here) — no pre-existing git repo, remote, or config file is required; OpenCode launches with `cwd` set to this path directly.
- [ ] On container start, run `omnigent login <server-url>` then `omnigent host <server-url>` (entrypoint script), so the host self-registers and reconnects automatically on restart — this authenticates with the operator's real account token, so built-in `accounts` auth on the server is sufficient (no `header`/`oidc` needed for this self-hosted, non-managed host).
- [ ] Set `restart: unless-stopped` on the host service so it survives reboots/crashes and re-dials the tunnel.
- [ ] No LLM credential env vars needed on this service. No `GIT_TOKEN` needed either — no push planned.

### 4. (Optional) Front the server with TLS + HTTP/2

Not required for this single-machine, local/LAN deployment. Add only if
multiple concurrent client tabs/sessions are expected against the same
origin (avoids the HTTP/1.1 6-connection stall):

- [ ] Put a reverse proxy in front of the server (bundled Caddy overlay from `deploy/docker/docker-compose.https.yaml`, or an existing proxy).
- [ ] Confirm its host-exposed port(s) (typically `80`/`443`) are free (`ss -ltn 'sport = :80'`, etc.) — both are free on this machine as of this writing.
- [ ] Confirm the login/callback URLs match the TLS domain, if used.

### 5. Client access

- [ ] Distribute the server URL to clients; each client signs in via the web UI (or `omnigent login <server-url>` for CLI use) — no OpenCode, no workspace, no credentials on the client.
- [ ] New chat → pick the registered host → select `opencode-native` as the harness → default to `opencode/big-pickle`.

### 6. Guardrails (policies)

- [ ] Add a server-level policy capping tool calls per session (`omnigent.policies.builtins.safety.max_tool_calls_per_session`) — the free model has no spend to cap, so bound runaway loops instead of cost.
- [ ] Add an approval-gate policy for shell/file-write tools if the workspace contains anything sensitive (`omnigent.policies.builtins.safety.ask_on_os_tools`).

### 7. Validation (evidence, not assumption)

- [ ] `docker compose ps` — server, host, Postgres all healthy.
- [ ] `docker compose up -d` does not fail with a port-bind error — confirms the pre-flight port check in step 1 was accurate.
- [ ] `opencode --version` inside the host container prints a value in `[1.17.7, 1.19.0)`.
- [ ] Host shows as connected/registered in server logs and in the web UI's host picker.
- [ ] End-to-end: start a session from a fresh browser session (private window, no prior state) targeting the host, run a trivial OpenCode task (e.g. list workspace files) on `opencode/big-pickle`, confirm output streams back live with no auth/credential prompts.
- [ ] Restart the host container and confirm it re-registers without manual intervention.
- [ ] Restart the server container and confirm sessions/history survive (Postgres persistence).

### 8. Repo publishing readiness (MIT, GitHub-ready root)

Steps 1–7 produce a working deployment only (compose file, `.env`, a custom
image, a validated running stack) — not a publishable repository. This
section closes that gap so the repo root is ready for a public GitHub push:

- [ ] `LICENSE` — MIT license at repo root, correct copyright holder/year.
- [ ] `README.md` at repo root — what this is, architecture summary (link to
      `docs/INITIAL.md` for the full plan), quick start (`docker compose up
      -d`), and the "no LLM keys / no registry / free model" properties
      called out up front since they're the differentiators of this setup.
- [ ] `.gitignore` — at minimum `.env`, any local workspace/volume data,
      `*.db`, `__pycache__/`, editor cruft. Verify `.env` is never
      accidentally committed (`git status` after `bootstrap.sh` runs).
- [ ] `.env.example` committed at repo root (placeholders only, mirroring
      `deploy/docker/.env.example`) so a fresh clone can `cp .env.example
      .env && ./bootstrap.sh` — the actual `.env` stays untracked.
- [ ] `docker-compose.yaml` (and the custom host `Dockerfile`) live at a
      clear, documented path in the repo (root or `deploy/`), referenced
      consistently from the README.
- [ ] Pin the exact Omnigent (`v0.11.0`) and OpenCode (`1.18.25`, or
      whatever in-range version is chosen) versions in the README/compose
      comments, not just in this planning doc, so they survive doc rot.
- [ ] First commit: verify `git status` shows no secrets, no `.env`, no
      local workspace data before `git add`/`git commit`/any `git push`.
- [ ] Confirm no credentials of any kind are needed to clone-and-run this
      repo from scratch (true by construction here: no LLM keys, no
      registry, no `GIT_TOKEN`) — call this out explicitly in the README as
      a selling point.

### 9. Final manual E2E test — real agent chat via Playwright MCP

Step 7 validates the stack is up and wired correctly; this step proves the
actual product experience works, driven through a real browser, not curl.

- [ ] Use the Playwright MCP browser tools (`browser_navigate`,
      `browser_snapshot`, `browser_type`, `browser_click`,
      `browser_wait_for`) against the server URL from a fresh
      (non-authenticated) browser context — no manual clicking, no shortcuts.
- [ ] Sign in as the admin (or a freshly-invited user) through the actual
      login form, not a pre-seeded session/cookie.
- [ ] Start a **new chat**, select the registered host, select
      `opencode-native` as the harness, confirm the model shown is
      `opencode/big-pickle` with no credential/auth prompt anywhere in the
      flow.
- [ ] Send a real prompt that requires the agent to touch the mounted
      workspace (e.g. "list the files in this workspace and create a file
      named `e2e-check.txt` with today's date").
- [ ] Use `browser_wait_for` on the expected response text, then
      `browser_snapshot` to capture the rendered chat turn as evidence — not
      just a network-request check.
- [ ] Verify the side effect independently, outside the browser:
      `docker exec <host-container> test -f <workspace>/e2e-check.txt` (or
      equivalent) — the file must actually exist in the container's mounted
      workspace, proving the tool call really executed and wasn't just
      echoed in chat.
- [ ] Take a final screenshot (`browser_take_screenshot`) of the completed
      chat turn and save it under a repo-relative path (e.g.
      `.playwright-mcp/e2e-agent-chat.png`) as durable evidence attached to
      this plan.
- [ ] Close the browser session (`browser_close`) and confirm the session
      persists server-side (reopen the same session URL/id and confirm
      history is intact) — proves persistence isn't dependent on the
      browser tab staying open.

This step is the actual "done" signal for the whole plan — steps 1–8 can
all report green while the product is still broken for a real user; this
one can't be faked with curl or unit-level checks.

## Explicitly out of scope for this initial setup

- Pi or any other harness — OpenCode only.
- Paid/external model providers and their API keys — free `opencode/*` models only.
- Container registry / image push — everything builds and runs locally on this one machine.
- Git remote / push credentials — the workspace has no remote configured; no `GIT_TOKEN` anywhere.
- Managed/ephemeral sandbox providers (Modal, Daytona, E2B, Kubernetes) — revisit only if the workspace needs to be disposable/scaled per session, or needs to run on a different machine than this one.
- OIDC/SSO — start with built-in `accounts` auth; add OIDC later if team size/identity requirements justify it.
- Multi-host load balancing — one host container is sufficient until concurrent session load requires more.

## Open questions to confirm before building

- Whether the `opencode` binary itself (not Omnigent's wrapper code) has any undocumented internal preference for a pre-existing `.git` — unverified, but treated as a non-blocker since no remote/credential is involved either way (see "Workspace directory contract" above). Confirm empirically during step 7 validation.
