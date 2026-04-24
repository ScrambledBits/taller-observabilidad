# Taller de Observabilidad — Bootcamperu

Repositorio pre-cocinado para el taller de 4 horas: **Prometheus 3.x + Grafana 13.x + Loki 3.x + Alertmanager + YACE sobre AWS** con **Terraform + Ansible**.

**Scope del repo**: SOLO el stack de observabilidad. Las apps que queremos monitorear (backend Flask, frontend nginx, etc.) NO viven aquí — se asumen externas y ya corriendo en algún host accesible desde el nodo de monitoring. Ver `docs/TARGETS.md` para qué deben exponer.

Este repo NO está completo a propósito. Contiene el andamiaje, las decisiones de arquitectura y los puntos de extensión. Lo que falta se rellena durante el taller, guiado por la *Guía del Instructor*.

---

## Arquitectura

```
┌──────────────────────────────────────┐       ┌──────────────────────┐
│ VPC tallerobs  (10.0.0.0/16)         │       │ Targets externos     │
│ ┌──────────────────────────────────┐ │       │ (otra VPC / misma /  │
│ │ Subnet pública  10.0.1.0/24      │ │       │  Internet)           │
│ │                                  │ │       │                      │
│ │   monitoring  (EC2 t3.small)     │◀┼──────▶│  frontend :9100 :9113│
│ │   ├─ Prometheus     :9090        │ │ scrape│  backend  :9100 :5000│
│ │   ├─ Grafana        :3000        │ │       │  + promtail push     │
│ │   ├─ Loki           :3100  ◀─────┼─┼───────┤        ↑             │
│ │   ├─ Alertmanager   :9093        │ │ logs  │        │             │
│ │   ├─ node_exporter  :9100        │ │       └────────┼─────────────┘
│ │   └─ promtail (self-journal)     │ │                │
│ └──────────────────────────────────┘ │                │
└──────────────────────────────────────┘                │
          ▲ Grafana / Prometheus UI                     │
          └──── tu laptop ─────────────────────────────┘
```

Este repo crea SOLO el nodo `monitoring`. Los targets externos son responsabilidad de otro repo (o del instructor).

---

## Requisitos locales

```bash
terraform -v      # >= 1.6
ansible --version # >= 2.15
aws --version     # credenciales válidas (SSO o access keys)
```

---

## Quick start (happy path)

```bash
# 1) Terraform — VPC + 1 EC2 + SG + key pair
cd terraform
cp terraform.tfvars.example terraform.tfvars   # editar con tu info
terraform init
terraform plan -out tfplan
terraform apply tfplan

# 2) Ansible — copia inventory generado por Terraform outputs
cd ..
make inventory
make ping

# 3) Provisionar el stack
make provision

# 4) Abrir Grafana
make open
# Grafana       :  http://<monitoring_ip>:3000   (admin / admin)
# Prometheus    :  http://<monitoring_ip>:9090
# Alertmanager  :  http://<monitoring_ip>:9093
```

---

## Estructura

```
taller-observabilidad/
├── terraform/          # VPC, subnet pública, SG, 1 EC2 (monitoring), key pair
├── ansible/            # inventory, site.yaml, 7 roles (solo del stack O11y)
├── docs/
│   ├── QUICKSTART.md       # paso a paso para alumnos
│   ├── TARGETS.md          # qué deben exponer los targets externos
│   └── TROUBLESHOOTING.md  # debugging rápido
├── Makefile
└── README.md
```

### Los 7 roles de Ansible (todos corren en el nodo monitoring)

| Rol              | Qué hace                                                 |
|------------------|----------------------------------------------------------|
| `common`         | apt update, paquetes base, usuario `observability`       |
| `node_exporter`  | Self-monitoring del nodo monitoring (puerto 9100)        |
| `prometheus`     | Prometheus 3.x + file_sd + rules + alertmanager target   |
| `loki`           | Loki 3.x con storage filesystem + schema v13             |
| `grafana`        | Grafana OSS 13.x con provisioning de datasources + dashboards |
| `alertmanager`   | Alertmanager 0.28 con route + receivers                  |
| `promtail`       | Promtail del propio nodo (journal + syslog)              |

---

## Puntos de extensión (TODO durante el taller)

Los archivos con `# TODO(taller):` marcan dónde los alumnos deben completar código. Hay exactamente **10 TODO** distribuidos en orden pedagógico:

| #  | Archivo                                              | Concepto                           |
|----|------------------------------------------------------|------------------------------------|
| 1  | `ansible/roles/node_exporter/tasks/main.yaml`        | Descarga + checksum + systemd      |
| 2  | `ansible/roles/prometheus/templates/prometheus.yml.j2` | `scrape_configs` con file_sd     |
| 3  | `ansible/roles/prometheus/files/targets_*.yaml`      | Service discovery de targets externos |
| 4  | `ansible/roles/grafana/files/dashboards/overview.json` | PromQL en panel de CPU           |
| 5  | `ansible/roles/loki/templates/loki-config.yaml.j2`   | Storage local + retention         |
| 6  | `ansible/roles/promtail/templates/promtail-config.yaml.j2` | Positions + clients + scrape |
| 7  | `ansible/roles/alertmanager/templates/alertmanager.yml.j2` | Route + receiver Slack       |
| 8  | `ansible/roles/prometheus/files/rules/alerts.yaml`   | Regla `HighCPU`                    |
| 9  | `terraform/main.tf`                                  | Security Group para :3000 :9090 :9093 :3100 |
| 10 | `terraform/user_data/monitoring.sh`                  | Docker compose bootstrap (opcional, lectura y discusión) |

**Lo que NO está en este repo** (pero los alumnos van a necesitar en sus targets): instalar `node_exporter` en el target externo, instrumentar Flask con `prometheus_client`, habilitar `stub_status` en nginx, instalar `promtail` como shipper hacia este Loki. Todo eso está en `docs/TARGETS.md`.

---

## Licencia

MIT — material pedagógico. Sin garantías. No usar en producción sin hardening adicional (TLS, auth, backups, network policies, etc.).
