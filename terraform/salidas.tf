# Outputs de Terraform: valores que se muestran al final de `terraform apply`
# y que están disponibles para consultar con `terraform output`.
#
# USOS DE LOS OUTPUTS:
#   1. Mostrar información útil al operador (IPs, comandos SSH)
#   2. Ser consumidos por otro módulo/stack de Terraform via remote state
#   3. Ser parseados por scripts o el Makefile para automatización
#
# Para ver todos los outputs: `terraform output`
# Para un valor específico: `terraform output -raw monitoring_public_ip`
# Para formato JSON (útil en scripts): `terraform output -json`

output "monitoring_public_ip" {
  description = "IP pública de la instancia de monitoreo — úsala para acceder a Grafana, Prometheus y Alertmanager desde el browser"
  value       = aws_instance.monitoreo.public_ip
}

output "monitoring_private_ip" {
  description = "IP privada de la instancia de monitoreo — dentro de la VPC, los otros servicios la usan para comunicarse"
  value       = aws_instance.monitoreo.private_ip
}

output "monitoring_ssh_command" {
  description = "Comando SSH listo para copiar y ejecutar. Conecta directamente al nodo de monitoreo."
  value       = "ssh -i ${local.ruta_llave_ssh} ${var.usuario_ssh}@${aws_instance.monitoreo.public_ip}"
}

# Estas IPs se leen del remote state del stack de apps (webstack-bootcamp).
# Se inyectan en el inventario de Ansible para que Prometheus pueda scrapear los targets.
output "frontend_target_ip" {
  description = "IP pública del frontend (nginx) — leída del remote state del stack de apps"
  value       = data.terraform_remote_state.apps.outputs.frontend_public_ip
}

output "backend_target_ip" {
  description = "IP privada del backend (Flask) — leída del remote state del stack de apps. Sin IP pública por estar en subnet privada."
  value       = data.terraform_remote_state.apps.outputs.backend_private_ip
}
