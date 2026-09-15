# Octop — self-hosted multi-user AI assistant (https://github.com/TencentCloud/Octop)
#
# Upstream publishes no container image, but its PyPI wheel already contains the
# built React dashboard, so this installs the released package rather than
# repeating upstream's two-stage npm build.
FROM python:3.12-slim

ARG OCTOP_VERSION=1.0.0

# uv, not pip: Octop's dependency tree defeats pip's resolver outright
# ("ResolutionTooDeep: 200000" after ~9 minutes). Upstream only ever installs it
# with uv and a frozen lockfile, and uv resolves the released wheel in seconds.
COPY --from=ghcr.io/astral-sh/uv:0.7.22 /uv /uvx /bin/

ENV UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# build-essential and linux-libc-dev are build-time only: `evdev`, pulled in for
# the remote-desktop input feature, is a C extension with no wheel and fails the
# install without them. socat fronts the server (see below); git is used by the
# agent workspaces; curl is the healthcheck and the bootstrap probe.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git socat tini build-essential libffi-dev linux-libc-dev; \
    uv venv /opt/venv; \
    uv pip install --no-cache "octop==${OCTOP_VERSION}"; \
    apt-get purge -y --auto-remove build-essential libffi-dev linux-libc-dev; \
    rm -rf /var/lib/apt/lists/*; \
    octop --version

# PORT is what Railway's healthcheck probes, so it is the outward port and the
# entrypoint keeps the two in agreement. OCTOP_PORT is the inner one: the server
# itself listens on loopback only.
#
# Octop is uvicorn on asyncio, which cannot bind dual-stack — `--host ::` serves
# IPv6 alone (measured: [::1] answers, 127.0.0.1 does not) and `--host 0.0.0.0`
# serves IPv4 alone, which is invisible on Railway's IPv6-only private network.
# The entrypoint therefore runs the server on 127.0.0.1 and puts socat in front.
#
# HOME=/data puts ~/.octop on the volume. The app is not run as a different
# user, so HOME survives — no passwd indirection needed here.
ENV PORT=8080 \
    OCTOP_PORT=8088 \
    HOME=/data \
    OCTOP_LOG_LEVEL=info \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint

WORKDIR /data
EXPOSE 8080

# tini reaps socat and the uvicorn worker tree.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/railway-entrypoint"]
