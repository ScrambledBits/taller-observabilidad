#!/usr/bin/env bash
# Punto de discusión pedagógica: estrategia de despliegue — Docker vs binarios nativos.
#
# CONTEXTO: Este script se ejecuta UNA SOLA VEZ al lanzar la instancia EC2.
# Es el mecanismo "user_data" de cloud-init: AWS lo inyecta como metadato de la
# instancia y el agente cloud-init lo ejecuta como root durante el primer arranque,
# ANTES de que Ansible pueda conectarse.
#
# PROPÓSITO de este script: preparar el mínimo indispensable del SO para que
# Ansible pueda correr. La instalación real de cada componente de observabilidad
# la realizan los roles Ansible (más mantenibles, idempotentes, testeables).
#
# PUNTO DE DISCUSIÓN EN EL TALLER — dos estrategias válidas:
#
# ESTRATEGIA A — Binarios nativos (implementada en este taller):
#   Cada componente (Prometheus, Grafana, Loki, etc.) se instala como binario
#   del sistema operativo, gestionado directamente por systemd.
#   Ventajas:
#     - Sin overhead de runtime de contenedores
#     - Integración nativa con systemd (journald, restart policies, etc.)
#     - Depuración directa: los logs van a journald, los procesos son visibles en ps
#     - Menos dependencias en la máquina (no necesita Docker)
#   Desventajas:
#     - Actualizar versiones requiere descargar y reemplazar binarios manualmente
#     - Dependencias del sistema operativo pueden interferir entre componentes
#
# ESTRATEGIA B — Docker Compose:
#   Cada componente corre en un contenedor; docker-compose.yml define el stack completo.
#   Ventajas:
#     - Aislamiento: cada componente tiene sus propias dependencias
#     - Rollback sencillo: cambiar la versión en el compose y hacer `docker compose up`
#     - Versiones fijas y reproducibles en el compose file
#     - Portabilidad: el mismo compose funciona en dev y producción
#   Desventajas:
#     - Requiere instalar y gestionar el Docker daemon
#     - Volúmenes y redes de Docker añaden complejidad al debugging
#     - Mayor consumo de memoria por el overhead de los contenedores
#
# En proyectos reales ambas son válidas. La elección depende del equipo y la plataforma.

# set -o errexit: el script aborta si cualquier comando retorna código != 0
# set -o nounset: el script aborta si se usa una variable no definida (previene errores silenciosos)
# set -o pipefail: el script aborta si falla cualquier comando en un pipe (sin esto, solo falla el último)
set -o errexit -o nounset -o pipefail

# Establece el hostname del servidor. Aparecerá en el prompt SSH y en los logs del sistema.
# También es el nombre que Prometheus usará como etiqueta `instance` en algunas métricas.
hostnamectl set-hostname monitoreo-bootcamperu

# -qq: modo silencioso (quiet quiet) — suprime output no esencial de apt
apt-get update -qq

# --no-install-recommends: instala solo las dependencias directas, no las "recomendadas".
# Reduce el tamaño de la imagen y el tiempo de instalación en entornos de servidor.
apt-get install -y --no-install-recommends \
  curl \
  wget \
  unzip \
  python3 \
  apt-transport-https \
  ca-certificates \
  gnupg \
  software-properties-common

# Crear un usuario de sistema dedicado para ejecutar los procesos de observabilidad.
# Principio de mínimo privilegio: cada servicio corre con el usuario `observability`,
# no como root. Si un servicio es comprometido, el atacante solo tiene acceso limitado.
#
# --system: UID < 1000, sin directorio home por defecto, marcado como usuario de sistema
# --no-create-home: no crea /home/observability (innecesario para un servicio)
# --shell /usr/sbin/nologin: previene login interactivo con este usuario
# 2>/dev/null || true: ignora el error si el usuario ya existe (idempotencia)
useradd --system --no-create-home --shell /usr/sbin/nologin observability 2>/dev/null || true
