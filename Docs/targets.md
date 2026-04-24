# Qué deben tener los targets externos

Este repo **no** despliega ni configura las apps que vamos a monitorear. Se asume que ya existen en algún lado (otra VPC, otro repo, máquinas del instructor, etc.).

Para que el stack de observabilidad funcione end-to-end, los targets externos deben exponer lo siguiente:

---

## Métricas (para Prometheus)

Cada target debe correr **al menos** un exporter en HTTP. Los puertos convencionales:

| Exporter                     | Puerto | Qué expone                              |
|------------------------------|--------|------------------------------------------|
| `node_exporter`              | 9100   | CPU, memoria, disco, red (host-level)    |
| `nginx-prometheus-exporter`  | 9113   | requests, conexiones, upstream latencies |
| Flask + `prometheus_client`  | 5000 (o el que elijas) | métricas custom en `/metrics` |
| `redis_exporter`             | 9121   | stats de Redis                           |
| `postgres_exporter`          | 9187   | stats de PostgreSQL                      |

El Security Group del target debe permitir inbound desde el **CIDR del nodo monitoring** en cada uno de esos puertos.

Una vez corriendo, las IPs:puertos se pegan en `ansible/roles/prometheus/files/targets_infra.yaml` (para node_exporter) y `targets_apps.yaml` (para los otros), parte del TODO #3.

### Ejemplo — instrumentar Flask con prometheus_client

```python
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from flask import Flask, Response, request
import time

app = Flask(__name__)

REQUESTS = Counter(
    "http_requests_total", "Total HTTP requests",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds", "Latencia por endpoint",
    ["endpoint"],
)

@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

@app.before_request
def _start():
    request._t0 = time.time()

@app.after_request
def _track(resp):
    endpoint = request.endpoint or "unknown"
    REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
    LATENCY.labels(endpoint).observe(time.time() - request._t0)
    return resp
```

### Ejemplo — habilitar stub_status en nginx

En `/etc/nginx/sites-available/default`:

```nginx
location = /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
}
```

Y `nginx-prometheus-exporter` corriendo en :9113 apuntando a `http://127.0.0.1/nginx_status`.

---

## Logs (para Loki)

Los targets empujan sus logs a este Loki con `promtail`. La URL de push que deben usar es:

```
http://<monitoring_private_ip>:3100/loki/api/v1/push
```

`monitoring_private_ip` sale del output de Terraform de este repo.

### Snippet de `promtail-config.yaml` que deben pegar en cada target:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://<monitoring_private_ip>:3100/loki/api/v1/push

scrape_configs:
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: <hostname_target>
          __path__: /var/log/syslog

  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: journal
        host: <hostname_target>
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit

  # Para nginx:
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: <hostname_target>
          __path__: /var/log/nginx/*.log
```

El Security Group del nodo monitoring debe permitir inbound en `:3100/tcp` desde `var.targets_cidr` (TODO #9).

---

## Checklist del target

Antes de pretender que el monitoring los vea, cada target debe tener:

- [ ] `node_exporter` corriendo en `:9100` (vía systemd, idealmente)
- [ ] SG permite inbound `:9100` desde el CIDR del monitoring
- [ ] Si es una app: exporter o `/metrics` expuesto en puerto conocido
- [ ] `promtail` corriendo, empujando a `http://<monitoring_private_ip>:3100`
- [ ] IPs y puertos agregados a `targets_infra.yaml` y/o `targets_apps.yaml` en este repo

Si al hacer `curl http://<target_ip>:9100/metrics` desde el nodo monitoring responde con métricas de Prometheus, vas bien.
