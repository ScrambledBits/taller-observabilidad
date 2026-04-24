# AMI (Amazon Machine Image): imagen base de Ubuntu 22.04 LTS publicada
# por Canonical (ID de cuenta: 099720109477). Se selecciona la más reciente.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "monitoreo" {
  ami                         = "ami-0ec10929233384c7f"
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.apps.outputs.public_subnet_id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bootcamp.key_name
  vpc_security_group_ids      = [data.terraform_remote_state.apps.outputs.security_group_ids.publico, data.terraform_remote_state.apps.outputs.security_group_ids.comun, aws_security_group.taller_observabilidad_bootcamperu_prometheus.id]

  tags = {
    Name = "Instancia Monitoreo"
  }
}
