# Taller de Observabilidad — Bootcamperu

Repositorio del taller de 4 horas: **Prometheus 3.x + Grafana 13.x + Loki 3.x + Alertmanager + node_exporter + Promtail sobre AWS** con **Terraform + Ansible**.

**Scope**: este repo solo despliega el nodo de monitoreo. Las apps monitoreadas (backend Flask, frontend nginx) viven en el repo `webstack-bootcamp` y se asumen ya desplegadas. Ver `Docs/targets.md` para preparar los targets.

---

## Arquitectura

```
┌──────────────────────────────────────────────────────┐
│ VPC bootcamperu (10.0.0.0/16)                        │
│                                                       │
│  Subnet pública 10.0.1.0/24                          │
│  ┌─────────────────────────────────────────────────┐ │
│  │ monitoring EC2 (t3.small, Ubuntu 24.04)         │ │
│  │  ├─ Prometheus    :9090  ←── scrape ──────────┐ │ │
│  │  ├─ Grafana       :3000                       │ │ │
│  │  ├─ Loki          :3100  ←── logs push ────┐  │ │ │
│  │  ├─ Alertmanager  :9093                    │  │ │ │
│  │  ├─ node_exporter :9100 (self)             │  │ │ │
│  │  └─ promtail (self-journal)                │  │ │ │
│  └─────────────────────────────────────────────┘ │ │ │
│                                                   │ │ │
│  Subnet pública 10.0.1.0/24                       │ │ │
│  ┌───────────────────────────┐                    │ │ │
│  │ frontend EC2 (nginx :80)  │── :9100 :9113 ─────┘ │ │
│  │  └─ node_exporter :9100   │── logs ──────────────┘ │
│  │  └─ nginx-exporter :9113  │                        │
│  │  └─ promtail              │                        │
│  └───────────────────────────┘                        │
│                                                        │
│  Subnet privada 10.0.2.0/24                           │
│  ┌───────────────────────────┐                        │
│  │ backend EC2 (Flask :5000) │── :9100 :5000 ─────────┘
│  │  └─ node_exporter :9100   │── logs ──────────────────
│  │  └─ promtail              │
│  └───────────────────────────┘
└──────────────────────────────────────────────────────┘
```

---

## Requisitos

```bash
terraform -v      # >= 1.6
ansible --version # >= 2.20
aws --version     # credenciales válidas (SSO o access keys)
make --version    # cualquiera
```

---

## Quick start

```bash
# 1) Terraform — crea VPC, EC2, SGs, llave SSH, genera inventario Ansible
#    y provisiona automáticamente con Ansible al finalizar
cd terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan

# 2) Verificar conectividad (opcional — Terraform ya corrió Ansible)
cd ..
make ping

# 3) Reproducir cambios de Ansible sin recrear la infra
make provision

# 4) Abrir las interfaces en el browser
make open
# Grafana       :  http://<monitoring_ip>:3000   (admin / bootcamp2026)
# Prometheus    :  http://<monitoring_ip>:9090
# Alertmanager  :  http://<monitoring_ip>:9093

# 5) Destruir al terminar el taller (para no consumir créditos AWS)
make tf-destroy
```

> **Dependencia previa**: el stack de apps (`webstack-bootcamp`) debe estar desplegado y su estado en S3 (`bootcamperu-tf-state/bootcamperu.tfstate`) antes de ejecutar `terraform apply`.

---

## Estructura

```
taller-observabilidad/
├── terraform/
│   ├── aprovisionamiento.tf   # genera inventario Ansible + espera SSH + corre Ansible
│   ├── instancias.tf          # EC2 monitoring (Ubuntu 24.04 Noble)
│   ├── proveedores.tf         # AWS provider + backend S3
│   ├── salidas.tf             # outputs (IPs, SSH command)
│   ├── seguridad.tf           # SG con puertos :9090 :3000 :9093 :3100
│   ├── ssh.tf                 # RSA-4096 key pair
│   ├── state.tf               # remote state del stack de apps
│   ├── variables.tf           # parámetros configurables
│   └── user_data/
│       └── monitoring.sh      # bootstrap cloud-init (TODO #10 — discusión)
├── ansible/
│   ├── site.yaml              # playbook principal (7 roles)
│   ├── group_vars/
│   │   └── all.yaml           # versiones, puertos, contraseña Grafana, webhook
│   ├── inventario_terraform.yaml  # generado por Terraform — no editar
│   └── roles/
│       ├── common/            # apt upgrade, usuario observability, grupo systemd-journal
│       ├── node_exporter/     # v1.11.1 — TODO #1
│       ├── prometheus/        # v3.11.0 — TODOs #2 #3 #8
│       ├── loki/              # v3.6.10 — TODO #5
│       ├── grafana/           # v13.0.1 — TODO #4
│       ├── alertmanager/      # v0.32.0 — TODO #7
│       └── promtail/          # v3.6.10 — TODO #6
├── Docs/
│   ├── Quickstart.md          # guía paso a paso para alumnos
│   ├── targets.md             # instalación manual de exporters en el webstack
│   └── troubleshooting.md     # debugging por componente
├── Makefile                   # targets: inventario, ping, provision, open, tf-destroy
└── .gitignore                 # excluye .pem, inventario generado, .claude/
```

---

## Los 7 roles de Ansible

| Rol             | Puerto | Versión  | Concepto del TODO         |
|-----------------|--------|----------|---------------------------|
| `common`        | —      | —        | Sistema base y usuario     |
| `node_exporter` | 9100   | 1.11.1   | TODO #1: checksum + systemd |
| `prometheus`    | 9090   | 3.11.0   | TODOs #2 #3 #8: file_sd + targets + alertas |
| `loki`          | 3100   | 3.6.10   | TODO #5: storage + retención |
| `grafana`       | 3000   | 13.0.1   | TODO #4: panel PromQL CPU  |
| `alertmanager`  | 9093   | 0.32.0   | TODO #7: route + receptor  |
| `promtail`      | —      | 3.6.10   | TODO #6: journal + syslog  |

---

## Los 10 TODO pedagógicos

| #  | Archivo                                                        | Concepto                              |
|----|----------------------------------------------------------------|---------------------------------------|
| 1  | `ansible/roles/node_exporter/tasks/main.yaml`                  | Checksum SHA256 + get_url + systemd   |
| 2  | `ansible/roles/prometheus/templates/prometheus.yml.j2`         | `scrape_configs` con `file_sd`        |
| 3  | `ansible/roles/prometheus/templates/targets_*.yaml.j2`         | IPs de targets inyectadas desde Terraform |
| 4  | `ansible/roles/grafana/files/dashboards/overview.json`         | Panel PromQL de uso de CPU            |
| 5  | `ansible/roles/loki/templates/loki-config.yaml.j2`             | Storage filesystem + retención 7 días |
| 6  | `ansible/roles/promtail/templates/promtail-config.yaml.j2`     | positions + clients + scrape journal  |
| 7  | `ansible/roles/alertmanager/templates/alertmanager.yml.j2`     | Route + receptor webhook              |
| 8  | `ansible/roles/prometheus/files/rules/alerts.yaml`             | Regla `HighCPU` con `for` y `annotations` |
| 9  | `terraform/seguridad.tf`                                       | Ingress SG para `:9093` y `:3100`     |
| 10 | `terraform/user_data/monitoring.sh`                            | Discusión: Docker vs binarios         |

---

## Variables principales (`ansible/group_vars/all.yaml`)

| Variable                   | Valor por defecto          | Descripción |
|----------------------------|----------------------------|-------------|
| `grafana_admin_password`   | `bootcamp2026`             | Contraseña del admin de Grafana |
| `alertmanager_webhook_url` | `http://localhost:5001/alertas` | Endpoint de notificaciones |
| `loki_retention_period`    | `168h`                     | Retención de logs (7 días) |

---

## Licencia

MIT — material pedagógico. Sin garantías. No usar en producción sin hardening adicional (TLS, autenticación, backups, restricción de IPs en SGs).
