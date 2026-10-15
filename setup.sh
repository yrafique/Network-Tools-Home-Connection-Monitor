#!/usr/bin/env bash
# setup.sh — fresh-install bootstrap for a dedicated monitoring host (e.g. a new Pi).
#
# Run ON the host itself, from the cloned repo:
#   git clone https://github.com/yrafique/home-network-monitor.git
#   cd home-network-monitor && ./setup.sh
#
# Installs Docker Engine + Compose plugin if missing, creates .env from
# .env.example on first run, then builds and starts the stack. Containers use
# `restart: always`, so the stack comes back on its own after every reboot.
# Safe to re-run: it rebuilds and restarts with the current code.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "setup.sh is for the Linux host. On a Mac, see 'Run locally' in README.md."

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

# ── 1. Docker Engine + Compose plugin ────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine (get.docker.com)..."
  $SUDO apt-get update -q
  $SUDO apt-get install -y -q ca-certificates curl git
  curl -fsSL https://get.docker.com | $SUDO sh
else
  log "Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1 && ! $SUDO docker compose version >/dev/null 2>&1; then
  log "Installing Docker Compose plugin..."
  $SUDO apt-get install -y -q docker-compose-plugin
fi

$SUDO systemctl enable --now docker >/dev/null

# Let the login user run docker without sudo (takes effect on next login).
if [ -n "$SUDO" ] && ! id -nG "$USER" | grep -qw docker; then
  $SUDO usermod -aG docker "$USER"
  log "Added $USER to the docker group (applies after you log out and back in)."
fi

# Use sudo for this run if the group change hasn't applied yet.
DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="$SUDO docker"

# ── 2. Config ────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  log "Created .env from .env.example — edit it to set targets, Grafana password and alerts."
else
  log "Keeping existing .env"
fi
mkdir -p data

# ── 3. Build + start ─────────────────────────────────────────────────────────
# Only docker-compose.yml: docker-compose.override.yml is for the Mac
# (it disables the speedtest) and must not apply on the always-on host.
log "Building and starting the stack (first build takes a few minutes on a Pi)..."
$DOCKER compose -f docker-compose.yml up -d --build --remove-orphans

log "Waiting for containers to report healthy..."
for _ in $(seq 1 60); do
  unhealthy=$($DOCKER compose -f docker-compose.yml ps --format '{{.Name}} {{.Status}}' | grep -vc '(healthy)' || true)
  [ "$unhealthy" -eq 0 ] && break
  sleep 5
done
$DOCKER compose -f docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}'

HOST="$(hostname).local"
echo
log "Done. The stack restarts automatically on boot."
log "Grafana:    http://${HOST}:3000"
log "Settings:   http://${HOST}:8080"
log "Prometheus: http://${HOST}:9090"
log "Metrics:    http://${HOST}:8000/metrics"
