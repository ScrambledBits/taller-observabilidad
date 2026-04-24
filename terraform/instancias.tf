# Busca la AMI más reciente de Ubuntu 24.04 LTS (Noble Numbat) publicada por Canonical.
# El ID de cuenta 099720109477 pertenece a Canonical (verificado en AWS Marketplace).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "monitoreo" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.apps.outputs.public_subnet_id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bootcamp.key_name
  vpc_security_group_ids = [
    data.terraform_remote_state.apps.outputs.security_group_ids.publico,
    data.terraform_remote_state.apps.outputs.security_group_ids.comun,
    aws_security_group.taller_observabilidad_bootcamperu_prometheus.id,
  ]

  # Script de inicialización ejecutado una sola vez al lanzar la instancia (cloud-init).
  user_data = file("${path.module}/user_data/monitoring.sh")

  tags = {
    Name = "Instancia Monitoreo"
  }
}
