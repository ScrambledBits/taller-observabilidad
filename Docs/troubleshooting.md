# Troubleshooting — Taller de Observabilidad

Recuerda que este repo solo despliega el **nodo de monitoreo**. Todo lo referente a "targets" corresponde a hosts externos del proyecto `webstack-bootcamp` (ver `Docs/targets.md`).

---

## Terraform

### `Error: AuthFailure` / `UnauthorizedOperation`
- `aws sts get-caller-identity` debe devolver tu ARN.
- Si usas SSO: `aws sso login --profile <perfil>` y exporta `AWS_PROFILE=<perfil>`.

### `Error: Failed to load remote state`
- El stack de apps (`webstack-bootcamp`) no está desplegado, o el bucket S3 `bootcamperu-tf-state` no es accesible con tus credenciales.
- Verifica que el estado del webstack existe:
  ```bash
  aws s3 ls s3://bootcamperu-tf-state/bootcamperu.tfstate
  ```

### `Error: InvalidKeyPair.Duplicate`
- El key pair quedó de una corrida anterior. Elimínalo en AWS:
  ```bash
  aws ec2 delete-key-pair --key-name taller-observabilidad-bootcamperu
  ```

### `Error: VcpuLimitExceeded`
- Tu cuenta AWS no tiene cuota para `t3.small`. Baja a `t3.micro` en `variables.tf` (el stack arranca ajustado pero funciona).

### `terraform destroy` se cuelga
- Este stack no tiene NAT gateway, así que rara vez sucede. Si igual se cuelga, revisa si quedó algún ENI colgado fuera del state en la consola AWS → EC2 → Network Interfaces.

---

## Ansible

### `UNREACHABLE` al correr `make ping`

El nodo de monitoreo tiene IP pública efímera. Verifica:

```bash
# Confirmar que el output de Terraform tiene una IP
cd terraform && terraform output monitoring_public_ip

# Verificar que la clave tiene los permisos correctos
chmod 400 terraform/taller-observabilidad-bootcamperu.pem

# Probar SSH manualmente
ssh -i terraform/taller-observabilidad-bootcamperu.pem ubuntu@<monitoring_public_ip> echo OK
```

### `Permission denied (publickey)`

```bash
chmod 400 terraform/taller-observabilidad-bootcamperu.pem
make ping
```

### El inventario tiene una IP vieja

Si destruiste y volviste a crear la infraestructura, regenera el inventario:

```bash
make inventario
```

### `promtool check config` falla al provisionar

El rol de Prometheus valida la config generada. Para ver qué se renderizó:

```bash
ssh -i terraform/taller-observabilidad-bootcamperu.pem ubuntu@<monitoring_ip> \
    "sudo cat /etc/prometheus/prometheus.yml"
```

Errores típicos: indentación con tabs en vez de espacios, variables Jinja2 sin definir.

### Ansible falla en el condicional de reinicio del kernel

Si ves el error `Conditional result was derived from value of type 'str'`, es un cambio de comportamiento de ansible-core 2.19+. El `when` del task de reinicio debe ser una expresión Jinja2 nativa sin comillas externas:

```yaml
# Incorrecto (string literal en ansible-core 2.19+):
when: resultado_upgrade.changed and "'linux-image' in resultado_upgrade.stdout"

# Correcto:
when: resultado_upgrade.changed and 'linux-image' in (resultado_upgrade.stdout | default(''))
```

---

## Prometheus

### Target externo aparece DOWN en `/targets`

1. Desde el nodo de monitoreo:
   ```bash
   curl -sS http://<target_ip>:9100/metrics | head
   ```
   Si no responde → el problema está en el target, no en el nodo de monitoreo.
2. Verifica que node_exporter está instalado y activo en el target (ver `Docs/targets.md`).
3. El Security Group del target debe permitir `:9100` desde el CIDR del nodo de monitoreo.

### `targets_infra.yaml` / `targets_apps.yaml` sin IPs esperadas

Las IPs se inyectan desde el remote state de Terraform. Verifica que los outputs del webstack son accesibles:

```bash
cd terraform && terraform output frontend_target_ip backend_target_ip
```

Si están vacíos o son incorrectos, el remote state del webstack puede estar desactualizado.

### `prometheus.yml` no se recarga tras editar un template

Ansible dispara un `reload` vía HTTP. Si no tomó el cambio, hazlo manualmente:

```bash
ssh -i terraform/taller-observabilidad-bootcamperu.pem ubuntu@<monitoring_ip> \
    "curl -X POST http://localhost:9090/-/reload"
```

Requiere el flag `--web.enable-lifecycle` en el unit file, que ya viene incluido.

---

## Grafana

### "Datasource not found"

- Los UIDs esperados son `prom-taller` (Prometheus) y `loki-taller` (Loki).
- Verifica el archivo de provisioning:
  ```bash
  sudo cat /etc/grafana/provisioning/datasources/datasources.yaml
  ```
- Reinicia: `sudo systemctl restart grafana-server`.

### Dashboards no aparecen

```bash
# Ver logs de Grafana
journalctl -u grafana-server -n 100 | grep -i error

# Ver dashboards provisionados
ls /var/lib/grafana/dashboards/
```

### Grafana no arranca

```bash
# Ver estado y logs
systemctl status grafana-server
journalctl -u grafana-server -n 50
```

Causa común: el archivo `grafana.ini` tiene una directiva mal formateada. Revisa los cambios recientes.

---

## Loki / Promtail

### Promtail del nodo de monitoreo no empuja

```bash
# Ver logs del servicio
journalctl -u promtail -n 100

# Verificar que el usuario observability está en el grupo systemd-journal
id observability

# Probar conectividad con Loki
curl -s http://localhost:3100/ready
```

### Promtail de un target externo no empuja

Verifica desde el target:

```bash
# La URL de push debe usar la IP PRIVADA del nodo de monitoreo (mismo VPC)
curl -v http://<monitoring_PRIVATE_ip>:3100/ready

# Si no responde, verificar SG del nodo de monitoreo: debe permitir :3100 inbound
# (ya incluido en terraform/seguridad.tf como `permitir_loki`)
```

También verifica que el servicio promtail esté activo:

```bash
systemctl is-active promtail
journalctl -u promtail -n 50
```

### Loki devuelve `429 Too Many Requests`

Volumen alto para los defaults. Aumenta los límites en `ansible/roles/loki/templates/loki-config.yaml.j2`:

```yaml
limits_config:
  ingestion_rate_mb: 8       # era 4
  ingestion_burst_size_mb: 12  # era 6
```

Luego re-provisiona con `make provision`.

---

## Alertmanager

### Alertas no llegan a ningún receptor

1. Verifica que la configuración es válida:
   ```bash
   amtool check-config /etc/alertmanager/alertmanager.yml
   ```
2. Verifica el config cargado en el proceso:
   ```bash
   curl -s http://localhost:9093/api/v2/status | python3 -m json.tool | head -30
   ```
3. El `alertmanager_webhook_url` en `ansible/group_vars/all.yaml` debe apuntar a un endpoint HTTP real que acepte POST con payload JSON.

### La alerta `HighCPU` nunca dispara

- Verifica que la regla está cargada: `http://<monitoring_ip>:9090/rules`
- El `for: 2m` requiere CPU sostenido > 80% por al menos 2 minutos.
- Para forzar la condición durante pruebas:
  ```bash
  # En el nodo de monitoreo
  sudo apt install -y stress-ng
  stress-ng --cpu 1 --timeout 180s &
  ```

### Alertmanager no recarga tras editar el template

```bash
curl -X POST http://localhost:9093/-/reload
```

---

## Limpieza

Siempre al final del taller:

```bash
make tf-destroy
```

Si algún recurso quedó huérfano (pasa si interrumpes Terraform a mitad de un apply), revisa manualmente:
- EC2 → Instances
- VPC → Security Groups
- EC2 → Key Pairs (nombre: `taller-observabilidad-bootcamperu`)

Con un solo nodo y sin NAT gateway, la limpieza es directa.
