# SECURITY GROUP del nodo de monitoreo.
#
# ¿Qué es un Security Group en AWS?
# Es un firewall virtual con estado (stateful) que controla el tráfico de red
# hacia y desde una instancia EC2. Características:
#   - Stateful: si permites el tráfico entrante, la respuesta sale automáticamente.
#   - Solo permite (no deniega): todo lo que no está explícitamente permitido se deniega.
#   - Se aplica a nivel de interfaz de red de la instancia.
#
# Diferencia con NACLs (Network Access Control Lists):
#   - Los NACLs son stateless y aplican a nivel de subnet.
#   - Los Security Groups son stateful y aplican a nivel de instancia.
#   - Usamos Security Groups para este taller por simplicidad.
#
# ADVERTENCIA SOBRE cidr_ipv4 = "0.0.0.0/0":
# Todas las reglas de ingreso usan 0.0.0.0/0 (acceso desde cualquier IP de internet).
# Esto es intencional para el taller (los alumnos se conectan desde IPs diversas),
# pero en producción deberías restringirlo a las IPs de tu organización o usar VPN.
# Los servicios expuestos no tienen autenticación fuerte: alguien con la IP pública
# podría acceder a Prometheus y hacer reload de la config, o leer logs de Loki.

resource "aws_security_group" "taller_observabilidad_bootcamperu_prometheus" {
  name        = "${local.prefijo_proyecto}_publico"
  description = "SG del proyecto ${var.nombre_proyecto}"
  # La VPC donde vive este security group. Viene del remote state del stack de apps
  # porque el nodo de monitoreo se despliega en la misma VPC que las aplicaciones.
  vpc_id = data.terraform_remote_state.apps.outputs.vpc_id
  tags = {
    Name = "taller_observabilidad_bootcamperu_prometheus"
  }
}

# Regla de ingreso para Prometheus (puerto 9090)
# Prometheus expone su UI y API en este puerto.
# Los alumnos acceden desde el browser para ver targets, métricas, y alertas activas.
resource "aws_vpc_security_group_ingress_rule" "permitir_http_prometheus" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0" # Taller: abierto. Producción: restringir a IPs conocidas.
  from_port         = 9090
  ip_protocol       = "tcp"
  to_port           = 9090
}

# Regla de ingreso para Grafana (puerto 3000)
# Grafana es la interfaz principal que usarán los alumnos durante el taller.
resource "aws_vpc_security_group_ingress_rule" "permitir_http_grafana" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3000
  ip_protocol       = "tcp"
  to_port           = 3000
}

# Nota pedagógica: en una versión anterior del taller, los alumnos agregaban estas reglas
# como ejercicio. El ejercicio enseñaba la diferencia entre declarar la infraestructura
# (Terraform) y configurar el software (Ansible): ambos pasos son necesarios para que
# el servicio sea accesible desde el exterior.

# Regla de ingreso para Alertmanager (puerto 9093)
# Alertmanager recibe alertas de Prometheus y las envía a los receptores configurados.
# Los alumnos pueden ver las alertas activas y crear silences desde la UI.
resource "aws_vpc_security_group_ingress_rule" "permitir_alertmanager" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 9093
  ip_protocol       = "tcp"
  to_port           = 9093
  tags = {
    Name = "alertmanager-ingress"
  }
}

# Regla de ingreso para Loki (puerto 3100)
# Loki recibe logs enviados por Promtail (de este nodo y de los targets externos).
# Los targets del webstack necesitan alcanzar este puerto para enviar sus logs.
# También permite consultar logs directamente via API de Loki.
resource "aws_vpc_security_group_ingress_rule" "permitir_loki" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3100
  ip_protocol       = "tcp"
  to_port           = 3100
  tags = {
    Name = "loki-ingress"
  }
}

# Regla de egreso (salida): permite TODO el tráfico saliente.
# ip_protocol = "-1" significa "todos los protocolos" (TCP, UDP, ICMP, etc.)
# Necesario para que el servidor pueda:
#   - Descargar binarios de GitHub
#   - Hacer apt update/upgrade
#   - Llamar a la API de AWS
#   - Enviar notificaciones al webhook de Alertmanager
resource "aws_vpc_security_group_egress_rule" "permitir_todo_egress" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
