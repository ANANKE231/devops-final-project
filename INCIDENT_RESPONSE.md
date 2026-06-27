# Incident Response Runbook

## Service Level Objective (SLO)
- **Availability target:** 99% uptime (measured via `/health` checks every 30s)
- **Error budget:** < 5 errors/minute sustained (matches the `HighErrorRate` Prometheus alert)
- **Latency target:** p95 request latency < 500ms (tracked via `app_request_duration_seconds`)

## Alert: AppDown (app unreachable)
1. Check Grafana → Alerting → confirm `AppDown` is firing.
2. `docker compose ps` — confirm `devops-app` container status.
3. `docker compose logs devops-app --tail=100` — look for crash traceback.
4. If the container exited: `docker compose up -d devops-app` to restart.
5. If it keeps crash-looping, roll back to the last known-good version:
   ```
   bash scripts/rollback.sh
   ```
6. Confirm recovery: `curl http://localhost:5000/health` should return `"status": "ok"`.

## Alert: HighErrorRate / ElevatedErrorRate
1. Open Grafana → Explore → Loki, filter by `{service="devops-app", level="ERROR"}`.
2. Identify the failing endpoint from the error logs.
3. Check Prometheus (`http://localhost:9090`) for `app_errors_total` by endpoint to confirm scope.
4. If caused by a bad deploy, roll back immediately:
   ```
   bash scripts/rollback.sh
   ```
5. If caused by bad input/load, no rollback needed — monitor until rate drops below threshold.

## Rollback Procedure
```
bash scripts/rollback.sh
```
This reverts to the previous Blue-Green slot / last working container image.
Verify with `bash scripts/health_check.sh` afterward.

## Post-Incident
- Write a short note in `docs/incidents/` with: what happened, detection time,
  resolution time, and root cause.
- If a new failure mode was discovered, add a Prometheus alert rule for it in
  `prometheus/rules/alerts.yml`.
