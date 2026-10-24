#!/usr/bin/env bash
# Runs the IMAP integration tests against a real Dovecot.
#
# Starts docker.io/dovecot/dovecot in a rootless podman container bound to
# 127.0.0.1 on free high ports, with a throwaway TLS certificate, seeds a
# mailbox over IMAP (APPEND), runs `dart test -t integration`, and always
# removes the container and temporary files, whatever happens.
#
# Usage: tool/integration.sh [extra dart test arguments]
# Env:   CONTAINER_ENGINE (default podman), PLUME_DOVECOT_IMAGE.
set -euo pipefail

cd "$(dirname "$0")/.."
engine=${CONTAINER_ENGINE:-podman}
image=${PLUME_DOVECOT_IMAGE:-docker.io/dovecot/dovecot:latest}
name="plume-dovecot-$$"
work=$(mktemp -d "${TMPDIR:-/tmp}/plume-dovecot.XXXXXX")

cleanup() {
  "$engine" rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# A self-signed certificate for 127.0.0.1 that only these tests trust. The
# key is world-readable because the container runs as another user; it is
# deleted on exit.
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -subj /CN=localhost \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -addext "basicConstraints=critical,CA:TRUE" \
  -keyout "$work/tls.key" -out "$work/tls.crt" 2>/dev/null
chmod 644 "$work/tls.key" "$work/tls.crt"

imap_port=$(free_port)
imaps_port=$(free_port)
password=$(openssl rand -hex 12)

echo "Starting $image as $name (IMAP 127.0.0.1:$imap_port, IMAPS 127.0.0.1:$imaps_port)"
"$engine" run -d --name "$name" \
  -e USER_PASSWORD="$password" \
  -v "$work/tls.crt:/etc/dovecot/ssl/tls.crt:ro,Z" \
  -v "$work/tls.key:/etc/dovecot/ssl/tls.key:ro,Z" \
  -p "127.0.0.1:$imap_port:31143" \
  -p "127.0.0.1:$imaps_port:31993" \
  "$image" >/dev/null

# The port forwarder accepts connections before Dovecot is up; wait for the
# IMAP greeting itself.
ready=0
for _ in $(seq 1 60); do
  if greeting=$(timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$imap_port && head -c 4 <&3" 2>/dev/null) &&
    [[ "$greeting" == "* OK" ]]; then
    ready=1
    break
  fi
  sleep 0.5
done
if [[ $ready -ne 1 ]]; then
  echo "Dovecot did not come up; its log:" >&2
  "$engine" logs "$name" >&2 || true
  exit 1
fi

seed_user=plume@example.org
dart run tool/seed_dovecot.dart "$imaps_port" "$work/tls.crt" "$seed_user" "$password"

PLUME_DOVECOT_PORT=$imap_port \
PLUME_DOVECOT_TLS_PORT=$imaps_port \
PLUME_DOVECOT_CA=$work/tls.crt \
PLUME_DOVECOT_PASSWORD=$password \
PLUME_DOVECOT_SEED_USER=$seed_user \
  dart test --run-skipped -t integration "$@"
