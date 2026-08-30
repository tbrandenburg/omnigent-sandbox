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

```bash
cp .env.example .env
./bootstrap.sh   # mints secrets into .env, idempotent, unattended
docker compose up -d
```

Open the printed server URL, sign in, start a new chat, pick the registered
host, select the `opencode-native` harness.

## Full plan

See [`docs/INITIAL.md`](docs/INITIAL.md) for the complete setup plan:
version pinning, port allocation, auth mode rationale, guardrail policies,
and the full validation/E2E checklist.

## License

[MIT](LICENSE)
