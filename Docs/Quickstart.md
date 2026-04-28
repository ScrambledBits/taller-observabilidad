# Quickstart — Taller de Observabilidad

Guía paso a paso para los **alumnos**. Tiempo estimado en "happy path": ~20 min para tener el stack arriba (sin contar los ejercicios prácticos del live coding).

**Scope**: este repo solo despliega el nodo de monitoreo. Los targets (apps que vamos a monitorear) son externos y viven en el repo `webstack-bootcamp`. Ver `Docs/targets.md` para prepararlos.

---

## 0. Pre-requisitos

En tu laptop:

| Herramienta | Versión mínima | Verificación |
|-------------|----------------|--------------|
| terraform   | 1.6            | `terraform -v` |
| ansible     | 2.20           | `ansible --version` |
| aws cli     | 2.x            | `aws --version && aws sts get-caller-identity` |
| make        | cualquiera     | `make --version` |
| git         | cualquiera     | `git --version` |
| ssh         | OpenSSH        | `ssh -V` |

### Credenciales AWS

El instructor proporcionará `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` temporales, o una sesión SSO. Configúralas antes de continuar:

```bash
# Opción A — variables de entorno (válido solo en la terminal actual)
export AWS_ACCESS_KEY_ID="<clave>"
export AWS_SECRET_ACCESS_KEY="<secreto>"
export AWS_DEFAULT_REGION="us-east-1"

# Opción B — perfil AWS (persiste entre terminales)
aws configure --profile taller
export AWS_PROFILE=taller

# Verificar
aws sts get-caller-identity
```

---

## 1. Clonar el repo

```bash
git clone <URL-DEL-REPO> taller-observabilidad
cd taller-observabilidad
```

---

## 2. Provisionar el nodo de monitoreo con Terraform

```bash
cd terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

> **Dependencia previa**: el stack de apps (`webstack-bootcamp`) debe estar desplegado y su estado en S3 antes de ejecutar este `apply`. Terraform lee las IPs de los targets directamente desde ese remote state.

Al terminar verás las salidas:

```
monitoring_public_ip  = "54.x.x.x"
monitoring_private_ip = "10.0.1.xx"
frontend_target_ip    = "3.x.x.x"
backend_target_ip     = "10.0.2.xx"
```

El `apply` también genera `ansible/inventario_terraform.yaml` automáticamente y espera a que SSH esté disponible en el nodo de monitoreo.

---

## 3. Verificar conectividad y re-provisionar

El `terraform apply` del paso anterior ya ejecutó Ansible automáticamente al terminar. Si necesitas volver a aplicar cambios de Ansible (por ejemplo, después de modificar una configuración durante los ejercicios):

```bash
cd ..
make ping        # verifica que SSH sigue funcionando
make provision   # vuelve a ejecutar ansible-playbook — los roles son idempotentes
```

Para regenerar el inventario si la IP del nodo cambió (por ejemplo, tras un stop/start de la instancia):

```bash
make inventario
```

---

## 4. Verificar

```bash
make open
```

Abre en el browser:

- **Grafana**: `http://<monitoring_public_ip>:3000` — login `admin / bootcamp2026` (cambia la contraseña en producción)
- **Prometheus**: `http://<monitoring_public_ip>:9090/targets` — deberías ver:
  - `prometheus` UP (self-scrape)
  - `node-monitoring` UP (node_exporter del propio nodo)
  - `node-external` y `apps` aparecen con targets pero DOWN hasta que los targets tengan node_exporter instalado (ver `Docs/targets.md`)
- **Alertmanager**: `http://<monitoring_public_ip>:9093`

---

## 5. Live coding — ejercicios prácticos

Esta es la parte pedagógica del taller. Cada ejercicio introduce un concepto clave del stack. El instructor guiará cada bloque; el orden en la tabla es el pedagógico recomendado.

| # | Archivo | Concepto | Tiempo aprox. |
|---|---------|----------|--------------|
| 1 | `ansible/roles/node_exporter/tasks/main.yaml` | Checksum SHA256 + get_url + binario + systemd | 10 min |
| 2 | `ansible/roles/prometheus/templates/prometheus.yml.j2` | `scrape_configs` con `file_sd` para service discovery | 15 min |
| 3 | `ansible/roles/prometheus/templates/targets_infra.yaml.j2` y `targets_apps.yaml.j2` | IPs de targets inyectadas desde Terraform | 5 min |
| 4 | `ansible/roles/grafana/files/dashboards/overview.json` | Panel PromQL de uso de CPU | 10 min |
| 5 | `ansible/roles/loki/templates/loki-config.yaml.j2` | Almacenamiento filesystem + esquema v13 + retención | 10 min |
| 6 | `ansible/roles/promtail/templates/promtail-config.yaml.j2` | `positions` + `clients` + scrape de journal y syslog | 15 min |
| 7 | `ansible/roles/alertmanager/templates/alertmanager.yml.j2` | Route + receptor de notificaciones (webhook) | 10 min |
| 8 | `ansible/roles/prometheus/files/rules/alerts.yaml` | Regla HighCPU con `for` y `annotations` | 10 min |
| 9 | `terraform/seguridad.tf` | Reglas de ingreso en SG para puertos `:9093` y `:3100` | 5 min |
| 10 | `terraform/user_data/monitoring.sh` | Discusión: Docker vs binarios en bootstrap | — |

Tras cada ejercicio que modifique configuración del stack, vuelve a aplicar:

```bash
make provision
# o solo el rol afectado:
ansible-playbook -i ansible/inventario_terraform.yaml ansible/site.yaml --tags <rol>
```

Para los ejercicios #2 y #3, las IPs de los targets ya están inyectadas automáticamente desde el remote state de Terraform (se pueden ver con `terraform -chdir=terraform output`).

---

## 6. Generar carga desde los targets

Esto se hace **desde el nodo de monitoreo o desde tu laptop**. El instructor dará los comandos. Ejemplo con la IP del frontend del webstack:

```bash
FRONT=$(cd terraform && terraform output -raw frontend_target_ip)
while true; do
    curl -s "http://$FRONT/api/hello" > /dev/null
    curl -s "http://$FRONT/"          > /dev/null
    sleep 0.5
done
```

Las métricas deben aparecer en Grafana a los ~30 segundos (dos scrape intervals).

---

## 7. Al terminar

**IMPORTANTE** — destruye la infraestructura para no consumir créditos AWS:

```bash
make tf-destroy
```

---

## Troubleshooting rápido

Ver `Docs/troubleshooting.md` para el debugging completo.

| Síntoma | Pista |
|---------|-------|
| `terraform apply` falla con `UnauthorizedOperation` | `aws sts get-caller-identity` para verificar credenciales |
| `Error: Failed to load remote state` | El stack de apps no está desplegado o el bucket S3 no es accesible |
| Ansible `UNREACHABLE` al hacer `make ping` | Verifica `chmod 400 terraform/taller-observabilidad-bootcamperu.pem` |
| `Permission denied (publickey)` | Clave sin permisos correctos o usuario SSH incorrecto |
| Prometheus `node-external` / `apps` DOWN | node_exporter no instalado en los targets — sigue `Docs/targets.md` |
| Grafana "Datasource not found" | UIDs esperados: `prom-taller` y `loki-taller` — reinicia grafana-server |
| Loki no recibe logs desde targets | Promtail en los targets debe apuntar a `http://<monitoring_private_ip>:3100/loki/api/v1/push` |
| Alertas no llegan | Configura `alertmanager_webhook_url` en `ansible/group_vars/all.yaml` con un endpoint real |
