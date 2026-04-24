# Preparación de los targets — Guía de instalación manual

Este repo monitorea el proyecto `webstack-bootcamp` (frontend nginx + backend Flask en AWS). Esta guía explica **paso a paso** cómo preparar ambas instancias para que Prometheus pueda scrapear sus métricas y Loki recibir sus logs.

> **Asumción**: el stack de apps ya está desplegado con `terraform apply` en `webstack-bootcamp/taller/terraform`. Si no, hacerlo primero.

---

## 0. Obtener IPs y acceso SSH

Desde el directorio del webstack:

```bash
cd /ruta/a/webstack-bootcamp/taller/terraform
terraform output
```

Anotá los valores:

```
frontend_public_ip = "3.x.x.x"       # IP pública del frontend (nginx)
backend_private_ip = "10.0.2.xx"      # IP privada del backend (Flask)
```

El **backend no tiene IP pública**. Solo es accesible vía el frontend como bastion.

### Comandos SSH

Terraform genera los comandos SSH exactos como outputs. La forma más simple es usarlos directamente:

```bash
# Frontend
terraform output -raw frontend_ssh_command | bash

# Backend — el output ya incluye el ProxyJump correcto
terraform output -raw backend_ssh_command | bash
```

Si preferís construir el comando manualmente, **es importante usar `-o ProxyCommand=` en lugar de `-o ProxyJump=`**. ProxyJump no siempre propaga la clave `-i` al host de salto dependiendo de la versión de OpenSSH y del estado del agente SSH; ProxyCommand con `-W` sí lo hace de forma explícita:

```bash
KEY="/ruta/a/webstack-bootcamp/taller/terraform/taller.pem"
FRONTEND_IP="<frontend_public_ip>"
BACKEND_IP="<backend_private_ip>"

# Frontend (acceso directo)
ssh -i "$KEY" ubuntu@"$FRONTEND_IP"

# Backend (ProxyCommand con clave explícita en ambos saltos)
ssh -i "$KEY" \
    -o ProxyCommand="ssh -W %h:%p -i '$KEY' ubuntu@$FRONTEND_IP" \
    ubuntu@"$BACKEND_IP"
```

> Si ya tenés la clave en el agente SSH (`ssh-add terraform/taller.pem`), podés usar el ProxyJump sin `-i`:
> `ssh -J ubuntu@<frontend_ip> ubuntu@<backend_ip>`

Para conexiones repetidas durante el taller, agregá esto a `~/.ssh/config` (reemplazá las IPs y la ruta real de la clave):

```
Host webstack-frontend
    HostName <frontend_public_ip>
    User ubuntu
    IdentityFile /ruta/absoluta/webstack-bootcamp/taller/terraform/taller.pem
    StrictHostKeyChecking no

Host webstack-backend
    HostName <backend_private_ip>
    User ubuntu
    IdentityFile /ruta/absoluta/webstack-bootcamp/taller/terraform/taller.pem
    ProxyCommand ssh -W %h:%p -i /ruta/absoluta/webstack-bootcamp/taller/terraform/taller.pem ubuntu@<frontend_public_ip>
    StrictHostKeyChecking no
```

Con esto: `ssh webstack-frontend` y `ssh webstack-backend`.

---

## 0.5 Requisitos de Security Groups

El webstack tiene tres Security Groups (`publico`, `privado`, `comun`). La siguiente tabla muestra qué puertos necesitamos para el monitoreo y cuáles ya están abiertos en el webstack base:

| Puerto | Componente | SG afectado | Estado por defecto | Acción necesaria |
|--------|-----------|-------------|-------------------|-----------------|
| :22 | SSH | `comun` | **Abierto** — `0.0.0.0/0` | Nada |
| :9100 | node_exporter | `comun` | **Abierto** — `monitoreo_cidr` (default `0.0.0.0/0`) | Nada |
| :5000 | Flask `/metrics` | `privado` | **Abierto** — solo desde SG `publico` | Nada¹ |
| :9113 | nginx-prometheus-exporter | `comun` | **CERRADO** | Abrir manualmente |

> ¹ El nodo de monitoreo tiene el SG `publico` del webstack asignado (ver `instancias.tf` del repo de observabilidad), por lo que puede alcanzar el backend en :5000 directamente.

### Abrir puerto :9113 manualmente

El puerto :9113 (nginx-prometheus-exporter) no existe en el webstack base y hay que agregarlo al SG `comun` antes de continuar con la sección 3.

**Opción A — AWS CLI** (recomendado, desde el directorio del webstack):

```bash
# Obtener el ID del SG comun
SG_COMUN=$(terraform output -json security_group_ids | python3 -c "import json,sys; print(json.load(sys.stdin)['comun'])")
printf "SG comun: %s\n" "$SG_COMUN"

# Agregar la regla
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_COMUN" \
  --protocol tcp \
  --port 9113 \
  --cidr 0.0.0.0/0

# Verificar
aws ec2 describe-security-groups --group-ids "$SG_COMUN" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`9113`]'
```

**Opción B — Consola AWS**:
1. EC2 → Security Groups → buscar el SG con nombre `taller_iac_bootcamperu_comun`
2. Pestaña "Inbound rules" → "Edit inbound rules"
3. Agregar regla: Type `Custom TCP`, Port `9113`, Source `0.0.0.0/0`
4. Guardar

---

## 1. Instalar node_exporter en el frontend

Conectate al frontend y ejecutá los siguientes comandos:

```bash
ssh -i terraform/taller.pem ubuntu@<frontend_public_ip>
```

```bash
# Variables
NODE_EXPORTER_VERSION="1.11.1"
ARCH="linux-amd64"
URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz"
CHECKSUM_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt"

# Descargar y verificar checksum
cd /tmp
wget -q "${URL}" -O node_exporter.tar.gz
wget -q "${CHECKSUM_URL}" -O sha256sums.txt
grep "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" sha256sums.txt | sha256sum --check

# Extraer e instalar
tar xzf node_exporter.tar.gz
sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" /usr/local/bin/
sudo chmod 755 /usr/local/bin/node_exporter

# Crear usuario de sistema
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter 2>/dev/null || true

# Crear unidad systemd
sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=":9100" \
  --collector.systemd \
  --collector.processes
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# Verificar
systemctl is-active node_exporter
curl -s http://localhost:9100/metrics | head -5
```

---

## 2. Instalar node_exporter en el backend

Conectate al backend usando ProxyCommand (ver sección 0 para el comando completo):

```bash
KEY="/ruta/a/webstack-bootcamp/taller/terraform/taller.pem"
ssh -i "$KEY" \
    -o ProxyCommand="ssh -W %h:%p -i '$KEY' ubuntu@<frontend_public_ip>" \
    ubuntu@<backend_private_ip>
```

Una vez conectado, ejecutá los mismos comandos que en la sección 1:

```bash
NODE_EXPORTER_VERSION="1.11.1"
ARCH="linux-amd64"
URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz"
CHECKSUM_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt"

cd /tmp
wget -q "${URL}" -O node_exporter.tar.gz
wget -q "${CHECKSUM_URL}" -O sha256sums.txt
grep "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" sha256sums.txt | sha256sum --check

tar xzf node_exporter.tar.gz
sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" /usr/local/bin/
sudo chmod 755 /usr/local/bin/node_exporter
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter 2>/dev/null || true

sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=":9100" \
  --collector.systemd \
  --collector.processes
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

systemctl is-active node_exporter
curl -s http://localhost:9100/metrics | head -5
```

---

## 3. Configurar nginx stub_status y nginx-prometheus-exporter en el frontend

El webstack instala nginx como reverse proxy pero **no expone métricas de Prometheus**. Para monitorearlo necesitamos dos pasos:

1. Habilitar `stub_status` en nginx (módulo estándar, ya incluido en el paquete `nginx`): expone contadores básicos de conexiones en una URL interna.
2. Instalar `nginx-prometheus-exporter`: un proceso externo que lee `stub_status` y lo convierte al formato Prometheus, escuchando en el **puerto :9113**.

> **Pre-requisito**: abrí el puerto :9113 en el SG `comun` del webstack antes de continuar (sección 0.5).

### 3.1 Habilitar stub_status en nginx

Conectado al **frontend**:

```bash
# Agregar bloque stub_status a la configuración de nginx
sudo tee /etc/nginx/sites-available/stub_status > /dev/null << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/stub_status /etc/nginx/sites-enabled/stub_status
sudo nginx -t && sudo systemctl reload nginx

# Verificar
curl -s http://127.0.0.1:8080/nginx_status
```

Deberías ver algo como:

```
Active connections: 1
server accepts handled requests
 5 5 12
Reading: 0 Writing: 1 Waiting: 0
```

### 3.2 Instalar nginx-prometheus-exporter

```bash
NGX_EXPORTER_VERSION="1.4.0"
URL="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGX_EXPORTER_VERSION}_linux_amd64.tar.gz"

cd /tmp
wget -q "${URL}" -O nginx-exporter.tar.gz
tar xzf nginx-exporter.tar.gz
sudo mv nginx-prometheus-exporter /usr/local/bin/
sudo chmod 755 /usr/local/bin/nginx-prometheus-exporter

sudo useradd --system --no-create-home --shell /usr/sbin/nologin nginx_exporter 2>/dev/null || true

sudo tee /etc/systemd/system/nginx-prometheus-exporter.service > /dev/null << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
After=network.target nginx.service

[Service]
Type=simple
User=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
  --nginx.scrape-uri=http://127.0.0.1:8080/nginx_status \
  --web.listen-address=:9113
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nginx-prometheus-exporter

# Verificar
curl -s http://localhost:9113/metrics | grep nginx_
```

> Verificá la última versión de nginx-prometheus-exporter en https://github.com/nginxinc/nginx-prometheus-exporter/releases

---

## 4. Instrumentar Flask con prometheus_client en el backend

La app Flask del webstack (`/opt/webstack-app/app.py`) actualmente **no expone métricas de Prometheus**. Para instrumentarla:

### 4.1 Instalar prometheus_client

Conectado al **backend**:

```bash
pip3 install prometheus_client
```

### 4.2 Agregar métricas a app.py

Editá `/opt/webstack-app/app.py` para agregar el endpoint `/metrics`:

```bash
sudo nano /opt/webstack-app/app.py
```

Agregá estas importaciones al inicio del archivo:

```python
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
```

Agregá las métricas después de `app = Flask(__name__)`:

```python
REQUESTS = Counter(
    "http_requests_total", "Total de peticiones HTTP",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds", "Latencia por endpoint",
    ["endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)

@app.before_request
def _iniciar_timer():
    from flask import request as req
    req._t0 = time.time()

@app.after_request
def _registrar_metrica(resp):
    from flask import request as req
    endpoint = req.endpoint or "desconocido"
    REQUESTS.labels(req.method, endpoint, resp.status_code).inc()
    LATENCY.labels(endpoint).observe(time.time() - getattr(req, "_t0", time.time()))
    return resp
```

Agregá el endpoint `/metrics` junto a los otros routes:

```python
@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}
```

Reiniciá el servicio:

```bash
sudo systemctl restart flask-app
sudo systemctl is-active flask-app

# Verificar endpoint de métricas
curl -s http://localhost:5000/metrics | head -10
```

---

## 5. Instalar Promtail en el frontend

Conectado al **frontend**:

```bash
PROMTAIL_VERSION="3.6.10"
URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"

cd /tmp
wget -q "${URL}" -O promtail.zip
unzip -q promtail.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod 755 /usr/local/bin/promtail

sudo useradd --system --no-create-home --shell /usr/sbin/nologin promtail 2>/dev/null || true
sudo usermod -aG systemd-journal promtail

sudo mkdir -p /etc/promtail /var/lib/promtail

# Reemplazá MONITORING_PRIVATE_IP con la IP privada del nodo de monitoreo
# (obtenida con: cd <repo-observabilidad>/terraform && terraform output monitoring_private_ip)
MONITORING_PRIVATE_IP="<PEGAR_IP_PRIVADA_DEL_NODO_MONITOREO>"
HOSTNAME=$(hostname)

sudo tee /etc/promtail/promtail-config.yaml > /dev/null << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${MONITORING_PRIVATE_IP}:3100/loki/api/v1/push
    batchwait: 1s
    batchsize: 1048576
    timeout: 10s

scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
        host: ${HOSTNAME}
        instancia: frontend
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
      - source_labels: ['__journal__hostname']
        target_label: hostname
      - source_labels: ['__journal__priority_keyword']
        target_label: level

  - job_name: nginx-access
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: ${HOSTNAME}
          instancia: frontend
          __path__: /var/log/nginx/access.log

  - job_name: nginx-error
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx-error
          host: ${HOSTNAME}
          instancia: frontend
          __path__: /var/log/nginx/error.log
EOF

sudo tee /etc/systemd/system/promtail.service > /dev/null << 'EOF'
[Unit]
Description=Promtail — Agente de envío de logs hacia Loki
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now promtail

# Verificar
systemctl is-active promtail
curl -s http://localhost:9080/ready
```

---

## 6. Instalar Promtail en el backend

Conectado al **backend** (vía ProxyJump):

```bash
PROMTAIL_VERSION="3.6.10"
URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"

cd /tmp
wget -q "${URL}" -O promtail.zip
unzip -q promtail.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod 755 /usr/local/bin/promtail

sudo useradd --system --no-create-home --shell /usr/sbin/nologin promtail 2>/dev/null || true
sudo usermod -aG systemd-journal promtail

sudo mkdir -p /etc/promtail /var/lib/promtail

MONITORING_PRIVATE_IP="<PEGAR_IP_PRIVADA_DEL_NODO_MONITOREO>"
HOSTNAME=$(hostname)

sudo tee /etc/promtail/promtail-config.yaml > /dev/null << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${MONITORING_PRIVATE_IP}:3100/loki/api/v1/push
    batchwait: 1s
    batchsize: 1048576
    timeout: 10s

scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
        host: ${HOSTNAME}
        instancia: backend
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
      - source_labels: ['__journal__hostname']
        target_label: hostname
      - source_labels: ['__journal__priority_keyword']
        target_label: level

  - job_name: flask-app
    static_configs:
      - targets: [localhost]
        labels:
          job: flask
          host: ${HOSTNAME}
          instancia: backend
          __path__: /var/log/syslog
    pipeline_stages:
      - match:
          selector: '{job="flask"}'
          stages:
            - regex:
                expression: '.*flask-app.*: (?P<message>.*)'
            - output:
                source: message
EOF

sudo tee /etc/systemd/system/promtail.service > /dev/null << 'EOF'
[Unit]
Description=Promtail — Agente de envío de logs hacia Loki
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now promtail

systemctl is-active promtail
curl -s http://localhost:9080/ready
```

---

## 7. Verificar desde el nodo de monitoreo

Obtenés la IP pública del nodo con:

```bash
cd <repo-observabilidad>/terraform && terraform output -raw monitoring_public_ip
```

### 7.1 Verificar alcance de los exporters

SSH al nodo de monitoreo y probá cada exporter:

```bash
ssh -i terraform/taller-observabilidad-bootcamperu.pem ubuntu@<monitoring_public_ip>
```

```bash
FRONTEND_IP="<frontend_public_ip>"
BACKEND_IP="<backend_private_ip>"

# node_exporter
curl -s "http://${FRONTEND_IP}:9100/metrics" | grep node_cpu | head -3
curl -s "http://${BACKEND_IP}:9100/metrics"  | grep node_cpu | head -3

# nginx exporter (solo frontend)
curl -s "http://${FRONTEND_IP}:9113/metrics" | grep nginx | head -3

# Flask metrics (solo backend)
curl -s "http://${BACKEND_IP}:5000/metrics" | head -5
```

Si alguno no responde, verificá el Security Group del target en AWS Console o con:

```bash
aws ec2 describe-security-groups --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName,Ingress:IpPermissions}'
```

### 7.2 Verificar targets en Prometheus

En el browser: `http://<monitoring_public_ip>:9090/targets`

Deberías ver todos los jobs con estado **UP**:
- `prometheus` — self-scrape
- `node-monitoring` — nodo de monitoreo
- `node-external` — frontend y backend
- `apps` — nginx exporter y Flask

### 7.3 Verificar logs en Loki/Grafana

En Grafana: `http://<monitoring_public_ip>:3000` → Explore → datasource **Loki**

Queries de prueba:

```logql
# Logs del frontend
{instancia="frontend"}

# Logs del backend
{instancia="backend"}

# Solo errores nginx
{job="nginx-error"}
```

---

## 8. Checklist final

Antes de iniciar la sesión del taller, verificá que cada target tenga:

- [ ] `node_exporter` activo en `:9100` — `systemctl is-active node_exporter`
- [ ] Prometheus puede alcanzar `:9100` desde el nodo de monitoreo
- [ ] (Frontend) `nginx-prometheus-exporter` activo en `:9113`
- [ ] (Frontend) `stub_status` habilitado en nginx en `127.0.0.1:8080/nginx_status`
- [ ] (Backend) Flask expone `/metrics` en `:5000`
- [ ] `promtail` activo en ambos hosts — `systemctl is-active promtail`
- [ ] Logs visibles en Grafana → Explore → Loki
- [ ] Todos los jobs en `http://<monitoring_ip>:9090/targets` en estado UP

Si `curl http://<target_ip>:9100/metrics` desde el nodo de monitoreo responde con métricas de Prometheus, el target está listo.
