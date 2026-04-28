# Outputs de Terraform: valores expuestos al final de `terraform apply`.
#
# TRES USOS PRINCIPALES:
#   1. Mostrar información útil al operador al terminar el apply (IPs, comandos listos).
#   2. Ser consumidos por otro stack via `terraform_remote_state` (como hacemos nosotros
#      con el stack de apps en state.tf).
#   3. Ser parseados por scripts externos o el Makefile para automatización.
#      Ejemplo en el Makefile: $(shell terraform output -raw monitoring_public_ip)
#
# COMANDOS ÚTILES:
#   terraform output                          → todos los outputs en formato legible
#   terraform output -raw monitoring_public_ip → solo el valor (sin comillas, útil en scripts)
#   terraform output -json                    → todos en JSON (útil para jq)

output "monitoring_public_ip" {
  description = "IP pública de la instancia de monitoreo — úsala para acceder a Grafana (:3000), Prometheus (:9090) y Alertmanager (:9093) desde el browser"
  value       = aws_instance.monitoreo.public_ip
}

output "monitoring_private_ip" {
  description = "IP privada de la instancia de monitoreo — los targets externos la usan para enviar logs a Loki (:3100) dentro de la VPC"
  value       = aws_instance.monitoreo.private_ip
}

# Construye el comando SSH completo como output para que el alumno pueda copiarlo
# directamente sin tener que recordar la ruta del PEM ni el usuario.
output "monitoring_ssh_command" {
  description = "Comando SSH listo para copiar y ejecutar. Conecta directamente al nodo de monitoreo."
  value       = "ssh -i ${local.ruta_llave_ssh} ${var.usuario_ssh}@${aws_instance.monitoreo.public_ip}"
}

# Los siguientes outputs RE-EXPORTAN valores del stack de apps.
# Aunque los tenemos disponibles via data.terraform_remote_state.apps.outputs.*,
# exponerlos como outputs de este stack los hace accesibles con `terraform output`
# sin necesidad de saber que vienen de otro stack. Útil en el Makefile y para depuración.

output "frontend_target_ip" {
  description = "IP pública del frontend (nginx/node_exporter en :9100, nginx exporter en :9113) — leída del remote state del stack de apps"
  value       = data.terraform_remote_state.apps.outputs.frontend_public_ip
}

output "backend_target_ip" {
  description = "IP privada del backend (Flask en :5000) — leída del remote state del stack de apps. Sin IP pública por estar en subnet privada; Prometheus la alcanza dentro de la VPC."
  value       = data.terraform_remote_state.apps.outputs.backend_private_ip
}
