#!/usr/bin/env bash
# ============================================================
#  rollback.sh — Instant Rollback to Previous Slot
#  Usage: bash scripts/rollback.sh
# ============================================================
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/devops-demo}"
LOG_DIR="${LOG_DIR:-/var/log/devops-demo}"
BLUE_PORT=5001
GREEN_PORT=5002

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ ! -f "$DEPLOY_DIR/active_slot" ]]; then
  log "❌  No active_slot file found. Has the app been deployed?"
  exit 1
fi

ACTIVE=$(cat "$DEPLOY_DIR/active_slot")

if [[ "$ACTIVE" == "blue" ]]; then
  PREVIOUS="green"; PREV_PORT=$GREEN_PORT; LIVE_PORT=$BLUE_PORT
else
  PREVIOUS="blue";  PREV_PORT=$BLUE_PORT;  LIVE_PORT=$GREEN_PORT
fi

PIDFILE="$DEPLOY_DIR/$PREVIOUS/app.pid"

log "⏪  Rolling back: $ACTIVE → $PREVIOUS"

# Check if previous slot is still running
if [[ -f "$PIDFILE" ]]; then
  OLD_PID=$(cat "$PIDFILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    log "   Previous slot ($PREVIOUS) already running on port $PREV_PORT"
  else
    log "   Previous slot not running — restarting..."
    VERSION=$(cat "$DEPLOY_DIR/$PREVIOUS/VERSION" 2>/dev/null || echo "unknown")
    APP_ENV=production APP_VERSION="$VERSION" PORT="$PREV_PORT" \
      python3 "$DEPLOY_DIR/$PREVIOUS/app.py" &>> "$LOG_DIR/${PREVIOUS}.log" &
    echo $! > "$PIDFILE"
    sleep 2
  fi
else
  log "   No PID file for $PREVIOUS — may not have been deployed"
  exit 1
fi

# Verify previous slot responds
if ! curl -sf "http://localhost:$PREV_PORT/health" > /dev/null; then
  log "❌  Previous slot ($PREVIOUS:$PREV_PORT) not healthy — rollback aborted"
  exit 1
fi

# Switch active slot back
echo "$PREVIOUS" > "$DEPLOY_DIR/active_slot"
log "✅  Rollback complete. $PREVIOUS is now LIVE on port $PREV_PORT"
log "   (The failed deploy on $ACTIVE:$LIVE_PORT is now idle)"

# Record rollback event
echo "{\"event\":\"rollback\",\"from\":\"$ACTIVE\",\"to\":\"$PREVIOUS\",\"time\":\"$(date -u +%FT%TZ)\"}" \
  >> "$DEPLOY_DIR/releases/history.jsonl"
