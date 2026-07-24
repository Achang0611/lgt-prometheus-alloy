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
Apps --OTLP+BasicAuth--> Alloy:4317/4318
                            ├─ metrics → Prometheus (remote_write)
                            ├─ logs    → Loki
                            └─ traces  → Tempo
Grafana ← query ← Prometheus / Loki / Tempo
```

## Quick start

```bash
cp .env.example .env
# edit GRAFANA_* and OTLP_TENANTS
docker compose up -d
```

## Coolify / reverse proxy

Point proxy routes at the **container network** services (or Coolify service names):

| Public path / host              | Upstream              | Notes |
|---------------------------------|-----------------------|--------|
| `https://grafana.example.com`   | `grafana:3000`        | Set `GRAFANA_ROOT_URL` to this URL |
| `https://otlp.example.com` HTTP | `alloy:4318`          | OTLP HTTP (`/v1/traces`, `/v1/metrics`, `/v1/logs`) + Basic Auth |
| (optional) Alloy UI             | `alloy:12345`         | Prefer internal-only |

Prefer **OTLP HTTP 4318** behind HTTPS. gRPC 4317 needs HTTP/2/h2c and is harder on many reverse proxies.

Prometheus, Loki, and Tempo should stay **internal** (no public proxy).

## OTLP authentication (multi-tenant labels)

Unauthorized writes are rejected at Alloy (HTTP 401). Tenants are configured with **Basic Auth**:

| Env | Format | Meaning |
|-----|--------|---------|
| `OTLP_TENANTS` | `tenant:password,tenant2:password2` | Username = tenant id; password = secret |

On each accepted request Alloy **upserts** resource attribute `tenant` from the Basic Auth username (client-supplied `tenant` is overwritten).

This is **soft isolation** (label filter in Grafana). Anyone with direct access to Prometheus/Loki/Tempo or Grafana admin can still see all data. Hard isolation later needs Mimir + multi-tenant Loki/Tempo (`X-Scope-OrgID`).

### App instrumentation

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.example.com
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
# Basic Auth: base64("tenant:password") — example for acme:secret1
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic YWNtZTpzZWNyZXQx
```

Generate the header value:

```bash
echo -n 'acme:secret1' | base64
# → put as Authorization=Basic <that>
```

Do **not** append `/v1/traces` to the endpoint; the SDK adds OTLP paths.

### Query by tenant

In Grafana Explore:

- Prometheus: `{tenant="acme"}`
- Loki: `{tenant="acme"}` (resource/label depending on exporter mapping)
- Tempo: search / TraceQL by resource `tenant=acme`

## Environment

See `.env.example`:

- `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` (password required)
- `GRAFANA_ROOT_URL` — must match the public Grafana URL
- `OTLP_TENANTS` — required; comma-separated `tenant:password` pairs

## Verify

```bash
docker compose ps
# Grafana / Prometheus have health probes; Loki/Tempo/Alloy follow grafana/alloy example (no in-container probe).
docker compose exec grafana curl -f http://localhost:3000/healthz
docker compose exec prometheus wget -qO- http://localhost:9090/-/ready
```

Unauthorized OTLP (expect 401):

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  -X POST "https://otlp.example.com/v1/traces" \
  -H "Content-Type: application/json" -d '{}'
```

Authorized smoke (replace host/creds):

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  -u 'acme:secret1' \
  -X POST "https://otlp.example.com/v1/metrics" \
  -H "Content-Type: application/json" \
  -d '{"resourceMetrics":[]}'
```

In Grafana Explore: Prometheus, Loki, and Tempo datasources are auto-provisioned.

## Files

- `docker-compose.yaml` — services, volumes, healthchecks
- `config.alloy` — OTLP receive + Basic Auth + tenant label → backends
- `scripts/alloy-entrypoint.sh` — builds htpasswd from `OTLP_TENANTS`
- `prometheus.yaml` — scrape self + stack
- `loki.yaml` / `tempo.yaml` — storage and retention
- `grafana/provisioning/` — datasources (Prometheus default, Loki, Tempo + linking)

(End of file - total lines above)
