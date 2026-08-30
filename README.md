# omnigent-sandbox

A simple, robust, single-machine Docker setup for running
[Omnigent](https://github.com/omnigent-ai/omnigent) with the **OpenCode**
harness — server + a self-hosted worker in Docker — reachable from any
browser as a plain agent chat.

## Why this setup

- **No LLM API keys.** Uses OpenCode's built-in free model,
  `opencode/big-pickle` — zero credentials, zero external provider auth.
- **No container registry.** Everything builds and runs locally on one
  machine.
- **No git remote / push credentials.** The workspace has no remote
  configured.
- **Client is just a browser.** No local install, no OpenCode, no
  workspace, no credentials on the client device.

## Architecture

```
Client (browser) ──HTTPS/WSS──▶ omnigent-server ◀──WS tunnel── omnigent-host
                                 (FastAPI, no keys)   (OpenCode CLI,
                                       │               workspace volume)
                                  Postgres (state)
```

The server is stateless with respect to agent execution; the host container
is the only place OpenCode runs and the workspace lives.

## Quick start

The full compose stack lives in [`deploy/docker/`](deploy/docker/):

```bash
cd deploy/docker
cp .env.example .env   # or just run ./bootstrap.sh, which does this for you
./bootstrap.sh         # mints secrets into .env, idempotent, unattended
docker compose up -d
curl http://localhost:8000/health
```

Open `http://localhost:8000` (or `${OMNIGENT_PORT}` if overridden), sign in,
start a new chat, pick the registered host, select the `opencode-native`
harness and the `opencode/big-pickle` model.

**No credentials of any kind are needed to clone-and-run this repo from
scratch** — no LLM API key, no container registry login, no `GIT_TOKEN`.
`bootstrap.sh` mints only the app's own internal secrets (Postgres password,
cookie secrets) locally into a git-ignored `.env`.

## Pinned versions

- [Omnigent](https://github.com/omnigent-ai/omnigent) `v0.11.0`
- [OpenCode](https://github.com/anomalyco/opencode) `1.18.25`
  (must stay within Omnigent's supported range `[1.17.7, 1.19.0)`)

See [`deploy/docker/Dockerfile.host`](deploy/docker/Dockerfile.host) for
where these are pinned as build args.

## Full plan

See [`docs/INITIAL.md`](docs/INITIAL.md) for the complete setup plan:
version pinning, port allocation, auth mode rationale, guardrail policies,
and the full validation/E2E checklist.

## License

[MIT](LICENSE)
