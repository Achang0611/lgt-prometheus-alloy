# LGT + Prometheus + Alloy (o11y center)

Single-node observability stack for Coolify (or any reverse-proxy fronted Docker host):

| Service    | Role                         | Internal port |
|-----------|------------------------------|---------------|
| Alloy     | OTLP gateway (apps send here)| 4317, 4318, 12345 |
| Prometheus| Metrics                      | 9090          |
| Loki      | Logs                         | 3100          |
| Tempo     | Traces                       | 3200 (+ OTLP internal) |
| Grafana   | UI                           | 3000          |

All ports use Compose `expose` only — publish nothing on the host. Route traffic via Coolify / Traefik / Caddy.

```
Apps --OTLP--> Alloy:4317/4318
                 ├─ metrics → Prometheus (remote_write)
                 ├─ logs    → Loki
                 └─ traces  → Tempo
Grafana ← query ← Prometheus / Loki / Tempo
```

## Quick start

```bash
cp .env.example .env
# edit GRAFANA_* for your domain
docker compose up -d
```

## Coolify / reverse proxy

Point proxy routes at the **container network** services (or Coolify service names):

| Public path / host              | Upstream              | Notes |
|---------------------------------|-----------------------|--------|
| `https://grafana.example.com`   | `grafana:3000`        | Set `GRAFANA_ROOT_URL` to this URL |
| `https://otlp.example.com:4317` | `alloy:4317` (gRPC)   | OTLP gRPC from apps |
| `https://otlp.example.com` HTTP | `alloy:4318`          | OTLP HTTP path `/v1/traces`, `/v1/metrics`, `/v1/logs` |
| (optional) Alloy UI             | `alloy:12345`         | Prefer internal-only |

Prometheus, Loki, and Tempo should stay **internal** (no public proxy).

## App instrumentation

Send OpenTelemetry to Alloy (not Tempo directly):

- gRPC: `http://otlp.example.com:4317` (or your proxy target)
- HTTP: `https://otlp.example.com` with OTLP paths

Example env (OTel SDK / collector):

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.example.com:4318
# or gRPC:
# OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.example.com:4317
```

## Environment

See `.env.example`:

- `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
- `GRAFANA_ROOT_URL` — must match the public Grafana URL

## Verify

From a host that can reach the Docker network (or via proxy):

```bash
docker compose ps
docker compose exec grafana wget -qO- http://localhost:3000/api/health
docker compose exec alloy wget -qO- http://localhost:12345/-/ready
docker compose exec prometheus wget -qO- http://localhost:9090/-/ready
docker compose exec loki wget -qO- http://localhost:3100/ready
docker compose exec tempo wget -qO- http://localhost:3200/ready
```

In Grafana Explore: Prometheus, Loki, and Tempo datasources are auto-provisioned.

## Files

- `docker-compose.yaml` — services, volumes, healthchecks
- `config.alloy` — OTLP receive → batch → backends
- `prometheus.yaml` — scrape self + stack
- `loki.yaml` / `tempo.yaml` — storage and retention
- `grafana/provisioning/` — datasources (Prometheus default, Loki, Tempo + linking)
