#!/usr/bin/env bash
# TODO(taller): #10 — Script de bootstrap: discusión Docker vs binarios.
#
# Este script se ejecuta UNA SOLA VEZ al lanzar la instancia EC2 (cloud-init).
# En un despliegue real se elegiría UNA de las dos estrategias:
#
# ESTRATEGIA A — Binarios (opción por defecto en el taller, implementada por los roles Ansible):
#   Ventajas: sin overhead de runtime de contenedores, nativo en systemd, depuración directa
#   Desventajas: gestión manual de versiones, dependencias del SO
#
# ESTRATEGIA B — Docker Compose (alternativa):
#   Ventajas: aislamiento, rollback sencillo, versiones fijas en compose file
#   Desventajas: requiere Docker daemon, gestión de volúmenes, complejidad de red
#
# Este script solo prepara la línea de base del SO. La instalación real de cada
# componente la hacen los roles Ansible.
set -o errexit -o nounset -o pipefail

hostnamectl set-hostname monitoreo-bootcamperu

apt-get update -qq
apt-get install -y --no-install-recommends \
  curl \
  wget \
  unzip \
  python3 \
  apt-transport-https \
  ca-certificates \
  gnupg \
  software-properties-common

# Crear usuario de sistema para ejecutar los servicios de observabilidad.
# Sin directorio home ni shell interactivo por seguridad.
useradd --system --no-create-home --shell /usr/sbin/nologin observability 2>/dev/null || true
