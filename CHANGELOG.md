# Changelog

Historial de cambios del Taller de Observabilidad (Bootcamperu).
Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).

---

## [1.2.0] — 2026-04-26

### Changed
- `Docs/targets.md`: eliminado voseo residual (Anotá→Anota, preferís→prefieres, Conectate→Conéctate, Verificá→Verifica, Editá→Edita, Agregá→Agrega, Reemplazá→Reemplaza); corregido "Asumción" por "Asunción"
- `Docs/troubleshooting.md`: agregada sección "Diagnóstico rápido" al inicio con secuencia de verificación de cuatro pasos
- `Docs/Quickstart.md`: agregada subsección "Credenciales AWS" con opciones A/B (variables de entorno y perfil nombrado); tabla de TODOs con columna "Tiempo aprox." más descriptiva; tono unificado
- `README.md`: agregada sección "Credenciales AWS" con instrucciones de configuración antes de la sección de licencia

---

## [1.1.0] — 2026-04-24

### Changed
- Comentarios pedagógicos completos en todos los archivos del proyecto
- Reemplazo de voseo argentino por español neutro en toda la documentación
- Variables cross-rol centralizadas en `group_vars/all.yaml`
- `daemon_reload` duplicado eliminado en rol `node_exporter`
- Corrección de typo en configuración del backend S3
- Grupo `observability` creado explícitamente en rol `common`
- SSH al backend via `ProxyCommand` explícito en `Docs/targets.md`
- Sección de SGs y contextualización del puerto 9113 en `Docs/targets.md`

---

## [1.0.0] — 2026-04-23

### Added
- Implementación de referencia completa con los 10 TODOs pedagógicos resueltos
- Rol `node_exporter` v1.11.1: descarga con `get_url`, verificación de checksum, servicio systemd
- Rol `prometheus` v3.11.0: `scrape_configs` con `file_sd`, reglas de alerta (HighCPU, InstanciaInaccesible, AltaMemoria), targets dinámicos vía Jinja2
- Rol `loki` v3.6.10: almacenamiento filesystem, esquema v13, retención 7 días
- Rol `grafana` v13.0.1: datasources Prometheus+Loki, dashboard con 5 paneles (CPU, RAM, Disco, Targets, Logs)
- Rol `alertmanager` v0.32.0: route con agrupación por severidad, receptor webhook, inhibit rules
- Rol `promtail` v3.6.10: scraping de journal systemd y `/var/log/syslog` hacia Loki
- Auto-provisioning de Ansible desde `terraform apply` (via `null_resource`)
- `.gitignore` con exclusiones para `.pem`, inventario generado y `.claude/`
- `Docs/`: Quickstart.md, targets.md, troubleshooting.md

### Fixed
- Condicional `when` incompatible con ansible-core 2.19+
- AMI Ubuntu 24.04 (Noble) corregida en `instancias.tf`

---

## [0.1.0] — 2026-04-23

### Added
- Scaffold inicial: estructura terraform + ansible + Docs
- Terraform: VPC, EC2 t3.small, SGs para :9090 :3000 :9093 :3100, key pair RSA-4096, remote state
- `Makefile` con targets: `inventario`, `ping`, `provision`, `open`, `tf-destroy`, `ayuda`
- `README.md` con arquitectura, quick start y tabla de TODOs pedagógicos
