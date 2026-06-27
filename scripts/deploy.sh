#!/usr/bin/env bash
# ============================================================
#  deploy.sh — Blue-Green Deployment Script
#  Usage: bash scripts/deploy.sh [version]
# ============================================================
set -euo pipefail

VERSION="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/devops-demo}"
LOG_DIR="${LOG_DIR:-/var/log/devops-demo}"
BLUE_PORT=5001
GREEN_PORT=5002
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)/app"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Determine slots ────────────────────────────────────────
if [[ -f "$DEPLOY_DIR/active_slot" ]]; then
  ACTIVE=$(cat "$DEPLOY_DIR/active_slot")
else
  ACTIVE="blue"
fi

if [[ "$ACTIVE" == "blue" ]]; then
  IDLE="green"; IDLE_PORT=$GREEN_PORT; LIVE_PORT=$BLUE_PORT
else
  IDLE="blue";  IDLE_PORT=$BLUE_PORT;  LIVE_PORT=$GREEN_PORT
fi

log "🚀 Deploying version $VERSION"
log "   Active slot: $ACTIVE  (port $LIVE_PORT)"
log "   Target slot: $IDLE   (port $IDLE_PORT)"

# ── Stop existing idle process (if any) ───────────────────
PIDFILE="$DEPLOY_DIR/$IDLE/app.pid"
if [[ -f "$PIDFILE" ]]; then
  OLD_PID=$(cat "$PIDFILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    log "Stopping idle slot (PID $OLD_PID)..."
    kill "$OLD_PID" && sleep 1
  fi
fi

# ── Copy new code to idle slot ────────────────────────────
mkdir -p "$DEPLOY_DIR/$IDLE"
cp -r "$APP_DIR/." "$DEPLOY_DIR/$IDLE/"

# ── Write version file ────────────────────────────────────
echo "$VERSION" > "$DEPLOY_DIR/$IDLE/VERSION"

# ── Start new version in idle slot ───────────────────────
log "Starting $IDLE slot on port $IDLE_PORT..."
APP_ENV=production APP_VERSION="$VERSION" PORT="$IDLE_PORT" \
  python3 "$DEPLOY_DIR/$IDLE/app.py" &> "$LOG_DIR/${IDLE}.log" &
NEW_PID=$!
echo "$NEW_PID" > "$PIDFILE"
log "   PID $NEW_PID — waiting for startup..."
sleep 2

# ── Health-check the new slot ─────────────────────────────
MAX_TRIES=5; n=0
until curl -sf "http://localhost:$IDLE_PORT/health" > /dev/null; do
  n=$((n+1))
  if [[ $n -ge $MAX_TRIES ]]; then
    log "❌  Health check failed — aborting deploy, keeping $ACTIVE live"
    kill "$NEW_PID" 2>/dev/null || true
    exit 1
  fi
  log "   Retrying health check ($n/$MAX_TRIES)..."
  sleep 2
done

log "✅  $IDLE slot healthy"

# ── Switch traffic ────────────────────────────────────────
echo "$IDLE" > "$DEPLOY_DIR/active_slot"
log "🔀  Traffic switched: $IDLE is now LIVE on port $IDLE_PORT"

# ── Save release record ───────────────────────────────────
mkdir -p "$DEPLOY_DIR/releases"
echo "{\"version\":\"$VERSION\",\"slot\":\"$IDLE\",\"port\":$IDLE_PORT,\"time\":\"$(date -u +%FT%TZ)\"}" \
  >> "$DEPLOY_DIR/releases/history.jsonl"

log "🎉  Deploy complete. Previous slot ($ACTIVE:$LIVE_PORT) standing by for rollback."
log "   Rollback: bash scripts/rollback.sh"
