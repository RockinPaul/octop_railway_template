# Deploy and Host Octop on Railway

[Octop](https://github.com/TencentCloud/Octop) is an open-source, self-hosted AI assistant from
Tencent Cloud: multi-user, multi-agent, with a web dashboard, an expert library, MBTI personas, a
RAG knowledge base, MCP connectors, IM channels and cron automation — all in one process, with every
conversation and credential kept on your own deployment.

This template runs it on Railway with its state on a volume and an admin password generated for your
deployment. One service, one volume, a public domain.

## About Hosting Octop

Octop is a single Python process that serves the React dashboard, the HTTP/SSE/WebSocket API, the IM
channel bridge and the scheduler from one control-plane database — SQLite by default, so there is no
second service to run. Everything it owns lives under `~/.octop`, which this template puts on the
volume: the database of users, agents and providers, the JWT signing secret, each agent's workspace,
installed plugins and logs.

Two details are handled for you. Octop's server is uvicorn on asyncio, which can bind only one
address family at a time, so the server listens on loopback and a small TCP relay in front of it
serves both — which is what Railway's edge and private network each need. And the admin account is
created on first boot from a generated password held in the service variables, rather than written
to a file inside the container that you would need a shell to read.

## Why Deploy Octop on Railway?

- **It stays awake.** Cron jobs, IM channels and long agent runs keep working with no machine of
  your own left running.
- **One service, no assembly.** No separate database, queue or broker to provision.
- **Your data stays in your deployment.** Conversations, credentials and workspaces sit on your
  volume, not in someone else's SaaS.
- **Reachable from anywhere.** A browser dashboard, plus IM channels and a programmatic API.
- **Survives redeploys.** Accounts, agents, knowledge bases and signed-in sessions are on the volume.

## Common Use Cases

- A personal assistant that keeps notes, writes summaries and remembers across conversations.
- A shared household or small-team assistant — one admin, separate users, an expert per task.
- A team bot bridged into Feishu, DingTalk, WeCom, QQ or Discord, routing tasks into group chats.
- Scheduled automation: cron jobs described in natural language that run and report on their own.
- A private knowledge base with RAG retrieval grounding answers in your own documents.

## Dependencies for Octop Hosting

- A model provider — an OpenAI-compatible API key, DashScope, or any provider you configure in the
  dashboard. Nothing is proxied through a third party.
- Optional: credentials for whichever IM channels or connectors you want to bridge.

### Deployment Dependencies

- Upstream project: <https://github.com/TencentCloud/Octop> (MIT), released package `octop` 1.0.0
  on PyPI: <https://pypi.org/project/octop/>.
- Upstream documentation: <https://github.com/TencentCloud/Octop/tree/main/docs>.
- Template source: <https://github.com/RockinPaul/octop_railway_template> (MIT).

### Implementation Details

**After deploying:** copy `OCTOP_DEFAULT_PASSWORD` from the service's Variables tab, open the public
domain, and sign in as **`admin`**. Then add a model provider in the dashboard and create an agent.

**How the admin password is handled, and why.** Octop already does the right thing on its own: when
no password is supplied, its container entrypoint generates a random one and writes it to
`~/.octop/credential.txt`. That is safe, but on Railway the only way to read a file inside the
container is to open a shell session on the service — an awkward first step for a one-click deploy.
So this template hands Octop a **password generated per deployment by Railway**
(`${{secret(24)}}`), which means it is visible in the service's Variables tab from the moment the
deploy finishes, and different for every deployment of this template. The container refuses to start
if that variable is empty or shorter than 12 characters, so there is no path to an unprotected
instance.

The variable is the **initial** password: it is applied only while there is no database yet.
Changing it afterwards does nothing, and that is deliberate — Octop lets you change your password in
the web console, and upstream's own credential file says the console password wins, so re-applying
the variable on each boot would silently revert a change you made. To reset a forgotten password,
run `octop user passwd --username admin` from a shell on the service.

**Security.** Unauthenticated API calls are refused (401), a wrong password is refused (401), and
upstream ships real login rate limiting (5 attempts, 15-minute lockout). The JWT secret is 32 random
bytes kept on the volume, so sessions survive redeploys. The container refuses to start with an
empty or short password. The honest caveat: agents run shell commands and browse on your behalf, so
the blast radius of this URL is a shell — keep the generated password and treat the URL accordingly.

**Notes.** `PORT` is set to 8080 and the relay follows it; Railway's healthcheck probes that port
and the domain targets it, so leave it as it is. Health is reported at `/api/health`. The interactive
API docs at `/api/docs` are off by default; enable them with `"enable_api_docs": true` in
`~/.octop/config.json`. Much of upstream's documentation is written in Chinese; the dashboard itself
is bilingual.

## Licences

Octop is MIT. The template's glue is MIT.
