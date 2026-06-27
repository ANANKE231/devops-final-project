#!/usr/bin/env bash
# ============================================================
#  setup.sh — One-command environment preparation
#  Brings up the app + full observability stack (Prometheus,
#  Grafana, Loki, Promtail) using Docker Compose.
# ============================================================
set -e

echo "📦 Checking for Docker..."
if ! command -v docker &> /dev/null; then
  echo "❌ Docker is not installed. Please install Docker Desktop first."
  exit 1
fi

if [ ! -f .env ]; then
  echo "🔧 No .env found — copying .env.example"
  cp .env.example .env
fi

echo "🚀 Building and starting all services..."
docker compose up --build -d

echo ""
echo "✅ Stack is up. Give it ~10s to finish initializing, then visit:"
echo "   App         → http://localhost:5000"
echo "   Prometheus  → http://localhost:9090"
echo "   Grafana     → http://localhost:3000  (admin / admin)"
echo "   Loki        → http://localhost:3100"
echo ""
echo "Run 'docker compose logs -f' to follow logs."
echo "Run 'docker compose down -v' to tear everything down."
