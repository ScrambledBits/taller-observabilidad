resource "aws_security_group" "taller_observabilidad_bootcamperu_prometheus" {
  name        = "${local.prefijo_proyecto}_publico"
  description = "SG del proyecto ${var.nombre_proyecto}"
  vpc_id      = data.terraform_remote_state.apps.outputs.vpc_id
  tags = {
    Name = "taller_observabilidad_bootcamperu_prometheus"
  }
}

resource "aws_vpc_security_group_ingress_rule" "permitir_http_prometheus" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 9090
  ip_protocol       = "tcp"
  to_port           = 9090
}

resource "aws_vpc_security_group_ingress_rule" "permitir_http_grafana" {
  security_group_id = aws_security_group.taller_observabilidad_bootcamperu_prometheus.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3000
  ip_protocol       = "tcp"
  to_port           = 3000
}
