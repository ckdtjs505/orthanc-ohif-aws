#!/usr/bin/env bash
# Run the Orthanc + OHIF stack on your own machine (needs only Docker).
#
#   ./scripts/run-local.sh          start the stack on http://localhost:8080
#   ./scripts/run-local.sh sample   generate a synthetic CT study and upload it
#   ./scripts/run-local.sh down     stop the stack (data is kept)
#   ./scripts/run-local.sh reset    stop the stack and delete all stored DICOM
#
# Env: HTTP_PORT (default 8080), PACS_USER (default admin), PACS_PASSWORD (default: generated)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOCKER_DIR="$ROOT/docker"
PW_FILE="$DOCKER_DIR/.local-password"
export HTTP_PORT=${HTTP_PORT:-8080}
PACS_USER=${PACS_USER:-admin}
URL="http://localhost:$HTTP_PORT"
ORTHANC_IMAGE=orthancteam/orthanc:24.10.3

compose() { docker compose -f "$DOCKER_DIR/docker-compose.yml" "$@"; }

# Print an htpasswd line for user/password (read from stdin).
htpasswd_line() {
  local user=$1 pw
  pw=$(cat)
  if command -v openssl >/dev/null 2>&1; then
    printf '%s:%s\n' "$user" "$(printf '%s' "$pw" | openssl passwd -apr1 -stdin)"
  else
    # No openssl on the host (e.g. Windows): salted SHA-1 via Python in the Orthanc image.
    printf '%s' "$pw" | docker run --rm -i --entrypoint python3 "$ORTHANC_IMAGE" -c '
import base64, hashlib, os, sys
pw = sys.stdin.read().encode(); salt = os.urandom(8)
print(sys.argv[1] + ":{SSHA}" + base64.b64encode(hashlib.sha1(pw + salt).digest() + salt).decode())' "$user"
  fi
}

ensure_credentials() {
  [ -f "$DOCKER_DIR/nginx/.htpasswd" ] && [ -f "$PW_FILE" ] && return
  local pw=${PACS_PASSWORD:-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}
  printf '%s' "$pw" | htpasswd_line "$PACS_USER" > "$DOCKER_DIR/nginx/.htpasswd"
  printf '%s\n%s\n' "$PACS_USER" "$pw" > "$PW_FILE"
  chmod 600 "$PW_FILE"
}

read_credentials() { PACS_USER=$(sed -n 1p "$PW_FILE"); PACS_PASSWORD=$(sed -n 2p "$PW_FILE"); }

up() {
  docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker Desktop first." >&2; exit 1; }
  ensure_credentials
  compose up -d
  printf 'waiting for the stack'
  for _ in $(seq 1 90); do
    curl -sf "$URL/healthz" >/dev/null 2>&1 && break
    printf '.'; sleep 2
  done
  echo
  curl -sf "$URL/healthz" >/dev/null || { echo "stack did not come up; see: docker compose -f docker/docker-compose.yml logs" >&2; exit 1; }
  read_credentials
  cat <<EOF

  OHIF viewer         $URL/
  Orthanc Explorer 2  $URL/orthanc/ui/app/
  login               $PACS_USER / $PACS_PASSWORD   (saved in docker/.local-password)

  Next: ./scripts/run-local.sh sample   (uploads a synthetic CT study)
EOF
}

sample() {
  [ -f "$PW_FILE" ] || { echo "run ./scripts/run-local.sh first" >&2; exit 1; }
  read_credentials
  local out="$ROOT/sample-data"
  if python3 -c 'import pydicom, numpy' >/dev/null 2>&1; then
    python3 "$ROOT/scripts/make_sample_dicom.py" "$out"
  else
    echo "pydicom not found locally; generating inside a python container"
    docker run --rm -v "$ROOT/scripts:/scripts:ro" -v "$out:/out" python:3.12-slim \
      sh -c 'pip install -q --disable-pip-version-check pydicom numpy && python /scripts/make_sample_dicom.py /out'
  fi
  PACS_URL=$URL PACS_USER=$PACS_USER PACS_PASSWORD=$PACS_PASSWORD "$ROOT/scripts/upload.sh" "$out"
  echo "open $URL/ and click the PHANTOM, SPHERE study"
}

case "${1:-up}" in
  up) up ;;
  sample) sample ;;
  down) compose down ;;
  reset) compose down -v; rm -f "$DOCKER_DIR/nginx/.htpasswd" "$PW_FILE" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
