# Quickstart — Taller de Observabilidad

Guía paso-a-paso para los **15 alumnos**. Tiempo estimado en "happy path": ~20 min para tener el stack arriba (sin contar los TODO).

**Recordatorio de scope**: este repo solo despliega el nodo de monitoring. Los targets (apps que vamos a monitorear) son externos y se asumen provistos por el instructor o por el repo de apps. Ver `docs/TARGETS.md`.

---

## 0. Pre-requisitos

En tu laptop:

| Herramienta | Versión mínima | Check |
|-------------|---------------|-------|
| terraform   | 1.6           | `terraform -v` |
| ansible     | 2.15          | `ansible --version` |
| aws cli     | 2.x           | `aws --version && aws sts get-caller-identity` |
| git         | cualquiera    | `git --version` |
| ssh         | OpenSSH       | `ssh -V` |

Credenciales AWS: el instructor te dará `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` temporales, o una sesión SSO.

---

## 1. Clonar el repo

```bash
git clone <URL-DEL-REPO> taller-observabilidad
cd taller-observabilidad
```

---

## 2. Provisionar el nodo de monitoring con Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# EDITA terraform.tfvars:
#   allowed_ingress_cidr = "<TU IP>/32"     (saca la tuya con: curl -s https://checkip.amazonaws.com)
#   targets_cidr         = <CIDR de los targets externos>

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Esto crea VPC + 1 EC2 (monitoring). Al terminar verás:

```
monitoring_public_ip  = "54.x.x.x"
monitoring_private_ip = "10.0.1.xx"
```

Guardá ambas: la pública es para tu browser; la privada es para que los targets externos empujen logs a Loki.

---

## 3. Generar inventory y provisionar

```bash
cd ..
make inventory   # lee outputs de Terraform y genera ansible/inventory.ini
make ping        # debe devolver pong
make provision   # corre ansible-playbook site.yaml (5-8 min primera vez)
```

Si algo falla, re-ejecutalo — los roles son idempotentes.

---

## 4. Verificar

```bash
make open
```

Abrí en el browser:

- **Grafana**: `http://<monitoring_ip>:3000` — login `admin / admin`, cambiá password.
- **Prometheus**: `http://<monitoring_ip>:9090/targets` — deberías ver:
  - `prometheus` UP (self-scrape)
  - `node-monitoring` UP (node_exporter del propio nodo)
  - `node-external` y `apps` aparecen vacíos hasta que completes TODO #2 y #3
- **Alertmanager**: `http://<monitoring_ip>:9093`

---

## 5. Live coding — completá los 10 TODO

| # | Archivo | Qué | ⏱ aprox |
|---|---------|------|---------|
| 1 | `ansible/roles/node_exporter/tasks/main.yaml` | Rellenar checksum + get_url + copy + systemd | 10' |
| 2 | `ansible/roles/prometheus/templates/prometheus.yml.j2` | scrape_configs con file_sd | 15' |
| 3 | `ansible/roles/prometheus/files/targets_*.yaml` | Pegar IPs de targets externos | 5' |
| 4 | `ansible/roles/grafana/files/dashboards/overview.json` | PromQL panel CPU | 10' |
| 5 | `ansible/roles/loki/templates/loki-config.yaml.j2` | retention + compactor | 10' |
| 6 | `ansible/roles/promtail/templates/promtail-config.yaml.j2` | clients + scrape (journal + syslog del monitoring) | 15' |
| 7 | `ansible/roles/alertmanager/templates/alertmanager.yml.j2` | Receiver Slack | 10' |
| 8 | `ansible/roles/prometheus/files/rules/alerts.yaml` | Regla HighCPU | 10' |
| 9 | `terraform/main.tf` | SG ingress 3000 / 9090 / 9093 / 3100 | 5' |
| 10 | `terraform/user_data/monitoring.sh` | (ya está; lectura + discusión Docker vs binarios) | - |

Tras cada TODO que cambie config del stack: `make provision` o `ansible-playbook -i ansible/inventory.ini ansible/site.yaml --tags <rol>`.

Para los TODO #2 y #3 necesitás las IPs de los targets externos. Tu instructor las comparte (ver sección "Targets del taller" en los materiales, o `docs/TARGETS.md`).

---

## 6. Generar carga (desde los targets externos)

Esto se hace **desde los targets**, no desde este repo. Tu instructor te dará los comandos de `curl` para bombardear las apps que querés monitorear.

Ejemplo típico (asumiendo que los targets exponen un endpoint HTTP):

```bash
FRONT=<IP_DEL_TARGET_FRONTEND>
while true; do
    curl -s "http://$FRONT/api/hello" > /dev/null
    curl -s "http://$FRONT/api/slow"  > /dev/null
    sleep 0.5
done
```

Las métricas deberían aparecer en Grafana a los ~30s (dos scrape intervals).

---

## 7. Al terminar

**IMPORTANTE** — no dejes el nodo corriendo, se te va a acabar el crédito AWS:

```bash
make tf-destroy
```

---

## Troubleshooting rápido

Ver `docs/TROUBLESHOOTING.md` para el debugging completo. Pistas clave:

| Síntoma | Pista |
|---------|-------|
| `terraform apply` falla con `UnauthorizedOperation` | tus credenciales AWS están mal — `aws sts get-caller-identity` |
| Ansible no conecta | chequeá permisos del key (`chmod 400 terraform/tallerobs-key.pem`) y que tu IP esté en `allowed_ingress_cidr` |
| Prometheus `node-external` / `apps` DOWN | TODO #2/#3 incompletos, o Security Group del target no permite al monitoring alcanzar :9100 |
| Grafana "No data" en panel CPU | es TODO #4 — reemplazar `up` por la expresión de CPU real |
| Loki no recibe logs desde targets | targets deben tener promtail configurado apuntando a `http://<monitoring_private_ip>:3100/loki/api/v1/push` — ver `docs/TARGETS.md` |
| Alertmanager silent | `amtool check-config` y que el webhook Slack sea real |

Si te atorás, levantá la mano — el instructor o los compañeros ayudan.
