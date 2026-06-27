import datetime
import json
import logging
import os
import time

from flask import Flask, request, jsonify, render_template_string, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# ── JSON structured logging ──────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.datetime.utcfromtimestamp(record.created).strftime("%Y-%m-%dT%H:%M:%S.%f"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": "devops-demo-app",
            "version": os.environ.get("APP_VERSION", "1.0.0"),
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        if hasattr(record, "extra"):
            log_entry.update(record.extra)
        return json.dumps(log_entry)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.root.setLevel(logging.INFO)
logging.root.handlers = [handler]
logger = logging.getLogger("devops-demo-app")

# ── Prometheus metrics ───────────────────────────────────────────────────────
REQUEST_COUNTER = Counter(
    "app_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status_code"],
)
ERROR_COUNTER = Counter(
    "app_errors_total",
    "Total number of application errors",
    ["endpoint", "error_type"],
)
REQUEST_LATENCY = Histogram(
    "app_request_duration_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
)

app = Flask(__name__)

messages = []


@app.before_request
def start_timer():
    request._start_time = time.time()


@app.after_request
def record_metrics(response):
    latency = time.time() - getattr(request, "_start_time", time.time())
    endpoint = request.path
    REQUEST_COUNTER.labels(
        method=request.method,
        endpoint=endpoint,
        status_code=response.status_code,
    ).inc()
    REQUEST_LATENCY.labels(endpoint=endpoint).observe(latency)

    if response.status_code >= 500:
        ERROR_COUNTER.labels(endpoint=endpoint, error_type="server_error").inc()

    logger.info(
        "request handled",
        extra={
            "extra": {
                "method": request.method,
                "path": endpoint,
                "status_code": response.status_code,
                "latency_ms": round(latency * 1000, 2),
                "remote_addr": request.remote_addr,
            }
        },
    )
    return response


HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DevOps Demo</title>
  <link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@300;400;500&family=Syne:wght@400;600;700;800&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg: #080b10; --surface: #0e1218; --surface2: #141920;
      --border: rgba(255,255,255,0.07); --border-bright: rgba(99,210,143,0.3);
      --green: #63d28f; --green-dim: #2a6645; --amber: #f0b429; --red: #f56565;
      --text: #e2e8f0; --text-dim: #64748b; --text-muted: #334155;
      --mono: 'DM Mono', monospace; --sans: 'Syne', sans-serif;
    }
    body { font-family: var(--mono); background: var(--bg); color: var(--text); min-height: 100vh; line-height: 1.6; }
    .wrapper { max-width: 860px; margin: 0 auto; padding: 48px 24px 80px; }
    h1 { font-family: var(--sans); font-size: 1.4rem; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 24px; margin-bottom: 16px; }
    .endpoint { display: flex; gap: 10px; padding: 8px 0; font-size: 0.85rem; }
    .get { color: var(--green); } .post { color: var(--amber); }
  </style>
</head>
<body>
<div class="wrapper">
  <h1>⬡ DevOps Demo App</h1>
  <p>CI/CD · Blue-Green Deploy · IaC · Observability · Security Scanning</p>
  <div class="card">
    <div class="endpoint"><span class="get">GET</span> /health — health check</div>
    <div class="endpoint"><span class="get">GET</span> /metrics — Prometheus metrics</div>
    <div class="endpoint"><span class="get">GET</span> /api/messages — list messages</div>
    <div class="endpoint"><span class="post">POST</span> /api/messages — post message</div>
    <div class="endpoint"><span class="get">GET</span> /api/echo/:name — dynamic route</div>
  </div>
</div>
</body>
</html>"""


@app.route('/')
def index():
    return render_template_string(HTML)


@app.route('/health')
def health():
    return jsonify({
        "status": "ok",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "version": os.environ.get("APP_VERSION", "1.0.0"),
        "env": os.environ.get("APP_ENV", "production"),
    })


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route('/api/messages', methods=['GET'])
def get_messages():
    return jsonify({"messages": messages})


@app.route('/api/messages', methods=['POST'])
def post_message():
    data = request.get_json()
    if not data or not data.get('body'):
        ERROR_COUNTER.labels(endpoint='/api/messages', error_type='validation_error').inc()
        logger.warning("rejected empty message body")
        return jsonify({"error": "body is required"}), 400
    msg = {
        "author": data.get("author", "Anonymous"),
        "body": data["body"],
        "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M"),
    }
    messages.append(msg)
    return jsonify({"status": "created", "message": msg}), 201


@app.route('/api/echo/<name>')
def echo(name):
    return jsonify({"echo": name, "timestamp": datetime.datetime.utcnow().isoformat()})


if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5000))
    logger.info("starting devops-demo-app", extra={"extra": {"port": port}})
    app.run(host='0.0.0.0', port=port, debug=False)
