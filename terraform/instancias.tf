# data "aws_ami": busca dinamicamente la AMI más reciente que cumpla los filtros.
# Usar "most_recent = true" con filtros precisos garantiza que siempre tomamos
# la última imagen parcheada de Ubuntu sin hardcodear el AMI ID (que varía por región).
#
# ¿Por qué Ubuntu 24.04 LTS?
# - LTS (Long Term Support): soporte de seguridad hasta 2029.
# - Noble Numbat: nombre en clave de la versión 24.04.
# - hvm-ssd-gp3: virtualización HVM (hardware-assisted), disco SSD tipo gp3 (más barato que gp2).
#
# Cuenta 099720109477: ID de AWS de Canonical (fabricante de Ubuntu).
# Siempre verificar este ID en https://ubuntu.com/server/docs/cloud-images/amazon-ec2
# para asegurarse de que la AMI es oficial y no maliciosa.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # Virtualización HVM (Hardware Virtual Machine): usa las extensiones de virtualización
  # del procesador (Intel VT-x / AMD-V). Es la opción moderna; la alternativa PV
  # (paravirtualization) está obsoleta en AWS.
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# La instancia EC2 que actúa como nodo central de observabilidad del taller.
# Ejecuta Prometheus, Grafana, Loki, Alertmanager y Promtail (todos instalados por Ansible).
resource "aws_instance" "monitoreo" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # La instancia va en la subnet pública para que los alumnos puedan acceder
  # a Grafana y Prometheus desde sus browsers (IP pública).
  # En producción el nodo de monitoreo iría en subnet privada con acceso via VPN o bastion.
  subnet_id                   = data.terraform_remote_state.apps.outputs.public_subnet_id
  associate_public_ip_address = true

  key_name = aws_key_pair.bootcamp.key_name

  # Lista de Security Groups aplicados a esta instancia.
  # Se combinan las reglas de todos: el resultado es la UNIÓN de todos los permisos.
  # - security_group_ids.publico: SG del stack de apps (acceso SSH, HTTP, HTTPS)
  # - security_group_ids.comun: SG compartido para comunicación intra-VPC
  # - taller_observabilidad_bootcamperu_prometheus: SG de este stack (Prometheus, Grafana, Loki, Alertmanager)
  vpc_security_group_ids = [
    data.terraform_remote_state.apps.outputs.security_group_ids.publico,
    data.terraform_remote_state.apps.outputs.security_group_ids.comun,
    aws_security_group.taller_observabilidad_bootcamperu_prometheus.id,
  ]

  # Script de inicialización ejecutado UNA SOLA VEZ al lanzar la instancia (cloud-init).
  # cloud-init es el mecanismo estándar en EC2 para bootstrapping. Se ejecuta como root
  # durante el primer arranque. Ver user_data/monitoring.sh para los detalles.
  user_data = file("${path.module}/user_data/monitoring.sh")

  tags = {
    Name = "Instancia Monitoreo"
  }
}
