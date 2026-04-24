output "monitoring_public_ip" {
  description = "IP pública de la instancia de monitoreo"
  value       = aws_instance.monitoreo.public_ip
}

output "monitoring_private_ip" {
  description = "IP privada de la instancia de monitoreo"
  value       = aws_instance.monitoreo.private_ip
}

output "monitoring_ssh_command" {
  description = "Comando SSH para conectarse al nodo de monitoreo"
  value       = "ssh -i ${local.ruta_llave_ssh} ${var.usuario_ssh}@${aws_instance.monitoreo.public_ip}"
}

output "frontend_target_ip" {
  description = "IP del frontend (obtenida del remote state del stack de apps)"
  value       = data.terraform_remote_state.apps.outputs.frontend_public_ip
}

output "backend_target_ip" {
  description = "IP privada del backend (obtenida del remote state del stack de apps)"
  value       = data.terraform_remote_state.apps.outputs.backend_private_ip
}
