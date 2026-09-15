#!/bin/sh
set -eu

OCTOP_HOME_DIR="${HOME}/.octop"
DB_FILE="${OCTOP_HOME_DIR}/octop.db"
ADMIN_USERNAME="${OCTOP_ADMIN_USERNAME:-admin}"
ADMIN_DISPLAY_NAME="${OCTOP_ADMIN_DISPLAY_NAME:-Admin}"
INNER_PORT="${OCTOP_PORT:-8088}"
OUTER_PORT="${PORT:-8080}"

# ---------------------------------------------------------------------------
# Fail closed on a missing admin password
# ---------------------------------------------------------------------------
# Upstream's own container entrypoint generates a random password when this is
# empty and writes it to ~/.octop/credential.txt. That is safe, but on Railway
# the only way to read that file is a shell session, so this template supplies
# the password as a service variable instead and refuses to start without one.
if [ -z "${OCTOP_DEFAULT_PASSWORD:-}" ]; then
    echo "FATAL: OCTOP_DEFAULT_PASSWORD is empty." >&2
    echo "  It is the first-run password for the '${ADMIN_USERNAME}' account on a" >&2
    echo "  public URL. Set it to a long random string — the template generates" >&2
    echo "  one for you." >&2
    exit 1
fi
if [ "$(printf '%s' "${OCTOP_DEFAULT_PASSWORD}" | wc -c)" -lt 12 ]; then
    echo "FATAL: OCTOP_DEFAULT_PASSWORD is shorter than 12 characters." >&2
    echo "  Octop's own policy allows 8, which is too short for a public domain." >&2
    echo "  Use the generated value." >&2
    exit 1
fi

# Railway mounts the volume root-owned with a lost+found directory; Octop
# creates ~/.octop beside it on first boot and is happy to share the directory.
mkdir -p "${HOME}"

# ---------------------------------------------------------------------------
# First-run bootstrap
# ---------------------------------------------------------------------------
# Only when there is no database: OCTOP_DEFAULT_PASSWORD is the *initial*
# password, not a reset. Changing it later does nothing, which is deliberate —
# a password changed in the web console must not be silently reverted on the
# next redeploy. (`octop user passwd` from a shell is the documented reset.)
if [ ! -f "${DB_FILE}" ]; then
    echo "octop: first boot — bootstrapping the control plane"
    if ! octop init --yes \
            --admin-username "${ADMIN_USERNAME}" \
            --admin-password "${OCTOP_DEFAULT_PASSWORD}" \
            --admin-display-name "${ADMIN_DISPLAY_NAME}"; then
        echo "FATAL: octop init failed." >&2
        echo "  Octop rejects weak or commonly-used passwords; if you replaced the" >&2
        echo "  generated OCTOP_DEFAULT_PASSWORD with your own, try a stronger one." >&2
        exit 1
    fi
    echo "octop: admin account '${ADMIN_USERNAME}' created from OCTOP_DEFAULT_PASSWORD"
else
    echo "octop: existing control plane on the volume; leaving the admin account alone"
fi

# ---------------------------------------------------------------------------
# Serve
# ---------------------------------------------------------------------------
# Octop is uvicorn on asyncio, which forces IPV6_V6ONLY and so cannot bind both
# families at once: `--host ::` answers on [::1] and not on 127.0.0.1, and
# `--host 0.0.0.0` is invisible on Railway's IPv6-only private network. socat
# listens dual-stack and forwards to the loopback server; being a TCP relay it
# passes the Host header through untouched, which the dashboard needs.
socat "TCP6-LISTEN:${OUTER_PORT},ipv6only=0,fork,reuseaddr" \
      "TCP4:127.0.0.1:${INNER_PORT}" &

echo "octop: serving on :${OUTER_PORT} (server on 127.0.0.1:${INNER_PORT})"

# exec so the server is the process Railway watches: if it dies the container
# dies with it, rather than leaving socat holding an empty port open.
exec octop run --host 127.0.0.1 --port "${INNER_PORT}" "$@"
