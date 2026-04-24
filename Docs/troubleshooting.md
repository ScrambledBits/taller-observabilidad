# Troubleshooting — Taller de Observabilidad

Recordá que este repo solo despliega el **nodo monitoring**. Todo lo que veas sobre "targets" se refiere a hosts externos que viven fuera de este repo (ver `docs/TARGETS.md`).

---

## Terraform

### `Error: AuthFailure` / `UnauthorizedOperation`
- `aws sts get-caller-identity` debe devolver tu ARN.
- Si usás SSO: `aws sso login --profile <perfil>` y exportá `AWS_PROFILE=<perfil>`.

### `Error: InvalidKeyPair.Duplicate`
- El key pair quedó de una corrida anterior. Borralo:
  ```bash
  aws ec2 delete-key-pair --key-name tallerobs-key
  ```

### `Error: VcpuLimitExceeded`
- Tu cuenta AWS no tiene cuota para `t3.small`. Bajá a `t3.micro` en `variables.tf` (Prometheus + Grafana + Loki corren apretados pero arrancan).

### `terraform destroy` se cuelga
- No tenemos NAT gateway en este stack (solo una subred pública), así que no debería pasar. Si igual se cuelga, revisá si dejaste algún ENI colgado por fuera del state.

---

## Ansible

### `UNREACHABLE` al correr `make ping`
- El nodo monitoring está en subred pública con IP elástica efímera. Verificá:
  - `terraform output monitoring_public_ip` devuelve algo.
  - Tu IP pública está dentro de `allowed_ingress_cidr` (`curl -s https://checkip.amazonaws.com`).
  - `chmod 400 terraform/tallerobs-key.pem`.

### `Permission denied (publickey)`
- `chmod 400 terraform/tallerobs-key.pem`
- Y volvé a correr: `ansible -i ansible/inventory.ini all -m ping`

### `promtool check config` falla al provisionar
- La `validate:` de la task de Prometheus corrió promtool con el YAML rendereado. Abrí el archivo:
  ```bash
  ssh -i terraform/tallerobs-key.pem ubuntu@<monitoring_ip> \
      "sudo cat /etc/prometheus/prometheus.yml"
  ```
  y validá sintaxis YAML — indentación con espacios, no tabs. Típico error: el TODO #2 con bloques `scrape_configs` mal indentados.

---

## Prometheus

### Target externo aparece DOWN en `/targets`
1. Desde el nodo monitoring:
   ```bash
   curl -sS http://<target_ip>:9100/metrics | head
   ```
   Si no responde → el problema es del target, no del monitoring.
2. Security Group del **target** permite `:9100` desde el CIDR del monitoring (ver `docs/TARGETS.md`).
3. En el target: `systemctl status node_exporter` y `journalctl -u node_exporter -n 50`.

### `targets_infra.yaml` / `targets_apps.yaml` vacíos
- Es esperable hasta que completes el TODO #3 pegando las IP:puerto reales. Mientras tanto los jobs `node-external` y `apps` aparecen en Prometheus sin targets.

### `prometheus.yml` no se recarga tras editar el template
- Ansible dispara un `reload` via systemd; si no tomó el cambio:
  ```bash
  curl -X POST http://localhost:9090/-/reload
  ```
  (Requiere el flag `--web.enable-lifecycle`, que ya viene en el unit file.)

---

## Grafana

### "Datasource not found"
- Verificá `/etc/grafana/provisioning/datasources/datasources.yaml`. Los UID esperados son `prom-taller` y `loki-taller`.
- Reiniciá: `sudo systemctl restart grafana-server`.

### "No data" en panel de CPU
- Es el TODO #4. La query inicial del dashboard es `up`, y el panel espera un % de CPU. Reemplazá por:
  ```
  (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
  ```

### Dashboards no aparecen
- `ls /var/lib/grafana/dashboards/` dentro del nodo debería listar los `.json` provisionados.
- Revisá `journalctl -u grafana-server -n 100` buscando líneas con `level=error`.

---

## Loki / Promtail

### Promtail local (del nodo monitoring) no empuja
- `journalctl -u promtail -n 100` en el nodo.
- Verificá que el usuario `observability` está en el grupo `systemd-journal` (si no, no lee journald).
- En este repo, el promtail local apunta a `http://127.0.0.1:3100/loki/api/v1/push` (es self-shipping del monitoring, NO cross-host).

### Promtail de un target externo no empuja
- Esa config vive fuera de este repo. Checklist en el target:
  - `url: http://<monitoring_private_ip>:3100/loki/api/v1/push` en `clients` (NO `public_ip`, tiene que ser la IP privada).
  - SG del monitoring permite inbound `:3100/tcp` desde `var.targets_cidr` (TODO #9).
  - `curl -v http://<monitoring_private_ip>:3100/ready` desde el target responde `ready`.

### Loki devuelve 429
- Volumen alto para los defaults. Subí `limits_config.ingestion_rate_mb` en el template de Loki (TODO #5 toca retention, podés tocar esto de paso).

---

## Alertmanager

### Alertas no llegan a Slack
- Probá el webhook desde tu laptop primero, fuera del stack:
  ```bash
  curl -X POST -H 'Content-type: application/json' \
       --data '{"text":"hola taller"}' $SLACK_WEBHOOK_URL
  ```
- Si el webhook responde `ok`, el problema es el config. En el nodo:
  - `amtool check-config /etc/alertmanager/alertmanager.yml`
  - Que el route no tenga un `receiver: null` genérico que se traga todo.
  - `curl http://localhost:9093/api/v2/status` muestra el config cargado.

### La alerta `HighCPU` nunca dispara
- Verificá la regla en `http://<monitoring_ip>:9090/rules` — debería estar `active` o `pending`.
- El `for:` de la regla (p. ej. `2m`) obliga a que el CPU esté alto sostenido ese tiempo antes de disparar. Para probar: `stress-ng --cpu 1 --timeout 180s` en el nodo.

---

## Limpieza

Siempre al final del taller:

```bash
make tf-destroy
```

Si algún recurso quedó huérfano (pasa si matás Terraform a mitad de apply): revisá la consola AWS → EC2 y VPC y borrá manualmente. Con un solo nodo y sin NAT, la limpieza es barata.
