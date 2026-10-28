#!/bin/sh
# Bind the container's own IPv4 (0.2.x rejects wildcard binds), serve TLS when
# certificates are mounted, apply the host overlay, then hand off to `dsh web`.
set -eu

ip=$(node -p "Object.values(require('os').networkInterfaces()).flat().filter(a=>a.family==='IPv4'&&!a.internal).map(a=>a.address)[0]")
set -- web --host "$ip" --port "${DSH_PORT:-3080}" --no-open
[ -n "${DSH_PUBLIC_URL:-}" ] && set -- "$@" --public-url "$DSH_PUBLIC_URL"
if [ -n "${DSH_TRUSTED_HOST:-}" ]; then
  for h in $DSH_TRUSTED_HOST; do set -- "$@" --trusted-host "$h"; done
fi
if [ -f /certs/fullchain.pem ] && [ -f /certs/privkey.pem ]; then
  set -- "$@" --tls-cert /certs/fullchain.pem --tls-key /certs/privkey.pem
fi
[ -n "${DSH_OVERLAY:-}" ] && [ -f "${DSH_OVERLAY}" ] && set -- "$@" --patch "$DSH_OVERLAY"

# The volume owns state only; the profile lives in the image. Symlink it in on
# first boot so `dsh plugin add` from the UI cannot silently diverge the code.
if [ -d /data/dsh ] && [ ! -e /data/dsh/profiles ]; then
  ln -s /opt/dsh/profiles /data/dsh/profiles
fi

echo "[entrypoint] dsh $*"
exec dsh "$@"
