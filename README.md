# ⬡ DevOps Final Project

A Python/Flask app with a complete DevOps pipeline: CI/CD, Blue-Green deployment,
Infrastructure as Code, full observability (metrics + logs + alerting), and
security scanning — all runnable locally with one command.

This project extends two earlier assignments (`devops-project` + `observability-lab`)
into a single, production-style stack as required by the Final assignment.

---

## Architecture

```
                          ┌─────────────────────────┐
  git push  ──────────►   │   GitHub Actions CI/CD   │
                          │  lint → test → security  │
                          │  scans → deploy           │
                          └────────────┬─────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Docker Compose Network                     │
│                                                                    │
│  ┌─────────────┐   /metrics    ┌────────────┐                     │
│  │ devops-app  │ ────────────► │ Prometheus │── evaluates ──► alerts
│  │ (Flask)     │               │  :9090     │   (alert_rules.yml) │
│  │ :5000       │               └─────┬──────┘                     │
│  │ /health     │                     │                            │
│  │ /metrics    │                     ▼                            │
│  │ JSON logs ──┼──► Promtail ──► Loki ──► Grafana :3000           │
│  └─────────────┘                              (dashboards+alerts) │
└──────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Tool |
|---|---|
| App | Python 3.11 · Flask 3.0 |
| Tests | pytest · flake8 |
| CI/CD | GitHub Actions |
| IaC | Ansible · Bash |
| Containers | Docker · Docker Compose |
| Metrics | Prometheus |
| Logs | Loki + Promtail (JSON structured logs) |
| Dashboards/Alerts | Grafana |
| Security | pip-audit, Trivy, gitleaks |
| Deploy | Blue-Green |

---

## Project Structure

```
.
├── app/app.py                      # Flask app + Prometheus metrics + JSON logging
├── Dockerfile
├── docker-compose.yml               # app + Prometheus + Grafana + Loki + Promtail
├── tests/test_app.py                # 8 unit tests
├── .github/workflows/ci-cd.yml      # lint, test, security scans, deploy
├── prometheus/
│   ├── prometheus.yml
│   └── rules/alerts.yml             # HighErrorRate, ElevatedErrorRate, AppDown
├── loki/loki-config.yml
├── promtail/promtail-config.yml
├── grafana/provisioning/...         # datasources, dashboards, alert rules
├── ansible/setup.yml                # IaC playbook
├── scripts/
│   ├── deploy.sh                    # Blue-Green deploy
│   ├── rollback.sh                  # Rollback
│   └── health_check.sh              # Health monitor
├── setup.sh                         # One-command environment setup
├── INCIDENT_RESPONSE.md             # SLOs + runbooks
└── .env.example
```

---

## Environment Setup (one command)

```bash
git clone <this-repo>
cd devops-project
bash setup.sh
```

This copies `.env.example` → `.env` and runs `docker compose up --build -d`,
bringing up the app and the entire observability stack with no manual steps.

| Service | URL | Login |
|---|---|---|
| App | http://localhost:5000 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Loki | http://localhost:3100 | — |

Tear down: `docker compose down -v`

**Run without Docker:**
```bash
pip install -r requirements.txt
python3 app/app.py
```

**Or provision with Ansible:**
```bash
pip install ansible
ansible-playbook -i ansible/inventory.ini ansible/setup.yml
```

---

## CI/CD Pipeline

```
git push
   │
   ▼
 LINT (flake8) → TEST (pytest) ─┬─► SECURITY: pip-audit (dependency scan)
                                 ├─► SECURITY: gitleaks (secrets scan)
                                 └─► SECURITY: Trivy (container image scan)
                                          │
                                          ▼
                              DEPLOY (main only, Blue-Green)
                                          │
                                          ▼
                          Health check + post-deploy smoke test
```

- `main` → full pipeline, deploys on success
- `dev` → lint + test + security scans only, no deploy
- Security scans report findings without blocking the demo pipeline (set
  `exit-code: '1'` / remove `continue-on-error` to enforce hard-fail in production)

---

## Security Implementation

| Check | Tool | Where |
|---|---|---|
| Dependency vulnerabilities | `pip-audit` | CI job `dependency-scan` |
| Container image vulnerabilities | Trivy | CI job `image-scan` |
| Secrets in code/history | gitleaks | CI job `secrets-scan` |
| Secrets management | `.env` (gitignored) + `.env.example` template | repo root |

All tools are free and run entirely in GitHub Actions — no paid services required.

---

## Monitoring, Logging & Observability

- **Metrics:** the app exposes `/metrics` (Prometheus format) — request counts,
  error counts, and request latency histograms, scraped every 10s.
- **Logs:** structured JSON logs go to stdout, are picked up by Promtail via the
  Docker socket, and shipped to Loki — queryable in Grafana with LogQL.
- **Alerting:** Prometheus + Grafana alert rules fire on:
  - `HighErrorRate` — >5 errors/min (critical)
  - `ElevatedErrorRate` — >2 errors/min (warning)
  - `AppDown` — app unreachable for 30s (critical)
- **Dashboards:** auto-provisioned in Grafana on startup.

To trigger an alert manually:
```bash
for i in {1..10}; do curl -s -X POST http://localhost:5000/api/messages; sleep 0.2; done
```

---

## Reliability Improvements

- `/health` endpoint used for liveness checks, CI smoke tests, and Prometheus's `AppDown` alert
- `scripts/health_check.sh` — standalone health monitor (supports `--watch` mode)
- `scripts/rollback.sh` — instant rollback to the previous Blue-Green slot
- Post-deploy smoke test in CI (`/health` + `/metrics` + a real `POST` request) before
  traffic is considered switched
- **[INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md)** — SLOs and step-by-step runbooks
  for `AppDown` and `HighErrorRate` alerts

---

## Deploy & Rollback

```bash
bash scripts/deploy.sh v2.0      # deploy new version
bash scripts/rollback.sh         # rollback instantly
```

---

## Screenshots

> Add screenshots here demonstrating:
> - CI/CD pipeline passing (including security scan jobs)
> - Grafana dashboard with live metrics
> - Grafana alert in "Firing" state
> - Loki log explorer showing JSON logs
> - Trivy / gitleaks scan output

---

## API

| Method | Endpoint | Description |
|---|---|---|
| GET | `/` | Web UI |
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |
| GET | `/api/messages` | List messages |
| POST | `/api/messages` | Post message |
| GET | `/api/echo/<name>` | Dynamic route |
