# Octop on Railway

[Octop](https://github.com/TencentCloud/Octop) — a self-hosted, multi-user AI assistant with a web
dashboard, an expert library, a knowledge base, IM channels and cron — running on Railway with its
state on a volume and an admin password generated for your deployment.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/octop)

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `octop` | `python:3.12-slim` + `octop` 1.0.0 | **yes** | The whole assistant: dashboard, API, agents, cron. |

One service, one volume, no gateway. Octop runs as a single process that serves the dashboard, the
HTTP/SSE/WebSocket API, the IM channels and the scheduler from one control-plane database.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `OCTOP_DEFAULT_PASSWORD` | generated, 24 chars | First-run password for the `admin` account. Read it from the service variables after deploying. |
| `OPENAI_API_KEY` | *(empty)* | Optional. Any provider can also be configured in the dashboard. |
| `PORT` | `8080` | The port Railway's healthcheck probes and the domain targets. Leave it alone. |
| `OCTOP_PORT` | `8088` | Baked. The inner loopback port the server itself listens on. |
| `HOME` | `/data` | Baked. Puts `~/.octop` — database, secrets, agent workspaces — on the volume. |
| `OCTOP_ADMIN_USERNAME` | `admin` | Optional. Add it before the first boot to use a different name. |

The deploy form asks for nothing you have to invent.

## First run

1. Copy `OCTOP_DEFAULT_PASSWORD` from the service's **Variables** tab.
2. Open the public domain and sign in as **`admin`**.
3. Add a model provider in the dashboard (or set `OPENAI_API_KEY`), then create an agent.

**Why the password is a Railway-generated secret.** Upstream already handles this well: with no
password supplied, Octop's own entrypoint generates a random one and writes it to
`~/.octop/credential.txt`. On Railway that file needs a shell session on the service to read, so
this template hands Octop a `${{secret(24)}}` instead — generated per deployment, visible in the
Variables tab as soon as the deploy finishes, and different for every deployment. The entrypoint
refuses to start on an empty or short value, so there is no path to an unprotected instance.

`OCTOP_DEFAULT_PASSWORD` is the **initial** password, applied only when there is no database yet.
Changing the variable later does nothing — deliberately, so that a password you changed in the web
console is not silently reverted by the next redeploy. To reset it, run
`octop user passwd --username admin` from a shell on the service.

## Security

Octop's own posture is better than most self-hosted assistants, and this is measured against a
running instance rather than taken from the README:

- Unauthenticated API calls are refused — `/api/agents` returns **401** — and a wrong password on
  `/api/auth/login` returns **401** while the generated one returns **200** with a JWT.
- Upstream ships **login rate limiting**: `login_max_attempts: 5` and `login_lockout_seconds: 900`
  in `config.json`.
- The JWT signing secret is 32 random bytes generated on first boot and kept on the volume, so
  sessions survive a redeploy. Verified: a token minted before the container was replaced still
  authenticated afterwards.
- The entrypoint refuses to start with an empty or short password. Octop also rejects weak and
  common passwords itself, which is why the template hands it a generated one.

The honest caveat: agents run shell commands, browse, and read the workspaces you give them, so the
blast radius of this URL is a shell. Upstream ships tool approval, shell guardrails and PII
redaction; keep the generated password, and treat the URL like an SSH session into a dev box.

## What persists

The volume at `/data` holds `~/.octop` in full: the SQLite control plane (users, agents, providers,
sessions, audit), the JWT secret, per-agent workspaces, installed plugins and logs. Running agent
sessions end on redeploy; the data does not.

## Why it is shaped this way

- **socat in front of a loopback server.** Octop is uvicorn on asyncio, which cannot bind both
  address families at once: `--host ::` answers on `[::1]` and *not* on `127.0.0.1`, and
  `--host 0.0.0.0` is invisible on Railway's IPv6-only private network. The server listens on
  `127.0.0.1:8088` and `socat TCP6-LISTEN:$PORT,ipv6only=0` forwards to it, which serves both
  families and passes the `Host` header through untouched.
- **`uv`, not `pip`.** Octop's dependency tree defeats pip's resolver outright —
  `ResolutionTooDeep: 200000` after about nine minutes. Upstream only ever installs it with uv.
- **A compiler at build time.** `evdev`, pulled in for the remote-desktop input feature, is a C
  extension with no wheel; `build-essential` is installed for the build and purged afterwards.
- **The PyPI wheel, not upstream's Dockerfile.** The published wheel already contains the built
  React dashboard, so the two-stage npm build upstream needs is unnecessary here.
- **`PORT` is a real variable.** Railway's healthcheck probes the port named by `PORT`, not the
  domain's target port, so the entrypoint takes its outer port from it.

## Upgrading

Bump `OCTOP_VERSION` in the `Dockerfile` and push. Upstream released v1.0.0 (GA) on 2026-09-14 after
roughly weekly releases, so check the changelog before jumping versions.

## Licences

Octop is [MIT](https://github.com/TencentCloud/Octop/blob/main/LICENSE). The glue in this repository
is MIT as well.
