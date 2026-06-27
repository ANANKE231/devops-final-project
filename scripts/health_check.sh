#!/usr/bin/env bash
# ============================================================
#  health_check.sh — Periodic Health Monitor
#  Usage: bash scripts/health_check.sh [--watch]
#  Cron:  * * * * * /path/to/health_check.sh >> /var/log/devops-demo/health.log 2>&1
# ============================================================

DEPLOY_DIR="${DEPLOY_DIR:-/opt/devops-demo}"
LOG_FILE="${LOG_FILE:-/var/log/devops-demo/health.log}"
BLUE_PORT=5001
GREEN_PORT=5002
WATCH_MODE=false
INTERVAL=30   # seconds between checks in watch mode

if [[ "${1:-}" == "--watch" ]]; then WATCH_MODE=true; fi

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG_FILE"; }

check_slot() {
  local slot="$1" port="$2"
  local url="http://localhost:$port/health"
  local start end duration status version env

  start=$(date +%s%N)
  response=$(curl -sf --max-time 5 "$url" 2>/dev/null) && CURL_OK=true || CURL_OK=false
  end=$(date +%s%N)
  duration=$(( (end - start) / 1000000 ))  # ms

  if $CURL_OK; then
    status=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "parse-error")
    version=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")
    env=$(echo "$response"     | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('env','?'))" 2>/dev/null || echo "?")
    echo "  SLOT=$slot  PORT=$port  STATUS=$status  VERSION=$version  ENV=$env  LATENCY=${duration}ms  RESULT=UP"
  else
    echo "  SLOT=$slot  PORT=$port  RESULT=DOWN  LATENCY=${duration}ms"
  fi
}

run_check() {
  local active="unknown"
  [[ -f "$DEPLOY_DIR/active_slot" ]] && active=$(cat "$DEPLOY_DIR/active_slot")

  log "── Health Check ────────────────────────────── active=$active"
  log "$(check_slot blue  $BLUE_PORT)"
  log "$(check_slot green $GREEN_PORT)"

  # Summary line
  local live_port
  if [[ "$active" == "blue" ]]; then live_port=$BLUE_PORT; else live_port=$GREEN_PORT; fi
  if curl -sf --max-time 5 "http://localhost:$live_port/health" > /dev/null 2>&1; then
    log "  OVERALL=HEALTHY  active=$active"
  else
    log "  OVERALL=DEGRADED  active=$active  *** ALERT: live slot not responding ***"
  fi
}

if $WATCH_MODE; then
  log "Starting continuous health monitor (interval=${INTERVAL}s)"
  while true; do
    run_check
    sleep "$INTERVAL"
  done
else
  run_check
fi
