# Genera el inventario de Ansible con la IP del nodo de monitoreo e IPs de los targets
# obtenidas desde el remote state del stack de apps.
# NOTA: Este archivo se sobreescribe en cada `terraform apply`. No editar manualmente.
resource "local_file" "ansible_inventory" {
  filename        = local.ruta_inventario
  file_permission = "0644"
  content         = <<-YAML
    # Archivo generado automáticamente por Terraform al ejecutar `terraform apply`.
    # NO editar manualmente — los cambios se sobreescribirán en el próximo apply.
    all:
      vars:
        ansible_user: ${var.usuario_ssh}
        ansible_ssh_private_key_file: ${local.ruta_llave_ssh}
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
        frontend_target_ip: "${data.terraform_remote_state.apps.outputs.frontend_public_ip}"
        backend_target_ip: "${data.terraform_remote_state.apps.outputs.backend_private_ip}"
      hosts:
        monitoring:
          ansible_host: ${aws_instance.monitoreo.public_ip}
    YAML

  depends_on = [aws_instance.monitoreo]
}

# Espera a que SSH esté disponible en el nodo de monitoreo antes de continuar.
# Esto permite que `make ping` y `make provision` funcionen inmediatamente después
# de un `terraform apply`.
resource "terraform_data" "esperar_ssh_monitoreo" {
  triggers_replace = [aws_instance.monitoreo.public_ip]

  provisioner "remote-exec" {
    inline = ["echo 'SSH listo: nodo de monitoreo'"]
    connection {
      type        = "ssh"
      user        = var.usuario_ssh
      private_key = tls_private_key.bootcamp.private_key_pem
      host        = aws_instance.monitoreo.public_ip
    }
  }

  depends_on = [aws_instance.monitoreo, local_sensitive_file.private_key]
}
