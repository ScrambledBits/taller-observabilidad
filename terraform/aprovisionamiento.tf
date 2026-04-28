# local_file: genera el inventario de Ansible con las IPs reales una vez que
# Terraform conoce las direcciones IP de las instancias.
#
# ¿Por qué genera Terraform el inventario?
# Porque las IPs son dinámicas — AWS las asigna en el momento de crear la instancia.
# Al generar el inventario como output de Terraform nos aseguramos de tener siempre
# las IPs correctas sin copiarlas manualmente.
#
# NOTA: Este archivo se sobreescribe en cada `terraform apply`. No editar manualmente.
# El Makefile tiene un target `make inventory` que genera este archivo también.
resource "local_file" "ansible_inventory" {
  filename        = local.ruta_inventario
  file_permission = "0644"

  # Heredoc con interpolación de Terraform: las expresiones ${ } se evalúan en tiempo
  # de `terraform apply` y se sustituyen por los valores reales.
  content = <<-YAML
    # Archivo generado automáticamente por Terraform al ejecutar `terraform apply`.
    # NO editar manualmente — los cambios se sobreescribirán en el próximo apply.
    all:
      vars:
        ansible_user: ${var.usuario_ssh}
        ansible_ssh_private_key_file: ${local.ruta_llave_ssh}
        # StrictHostKeyChecking=no: desactiva la verificación del fingerprint del host.
        # Necesario porque la IP puede cambiar entre sesiones y el taller no gestiona
        # known_hosts. En producción se mantiene la verificación de host.
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
        # IPs de los targets externos, leídas del remote state del stack de apps.
        # Prometheus las usa para scrapear métricas; Promtail para enviar logs.
        frontend_target_ip: "${data.terraform_remote_state.apps.outputs.frontend_public_ip}"
        backend_target_ip: "${data.terraform_remote_state.apps.outputs.backend_private_ip}"
      hosts:
        monitoring:
          ansible_host: ${aws_instance.monitoreo.public_ip}
    YAML

  depends_on = [aws_instance.monitoreo]
}

# terraform_data con provisioner "remote-exec": ejecuta un comando REMOTO en la instancia
# vía SSH para verificar que el servicio SSH está operativo y aceptando conexiones.
#
# ¿Por qué es necesario este paso?
# EC2 reporta la instancia como "running" antes de que cloud-init termine y sshd esté listo.
# Sin este paso, el provisioner de Ansible puede intentar conectar demasiado pronto y fallar.
# Este recurso actúa como "barrera de sincronización": Terraform espera aquí hasta
# que SSH responde antes de continuar con el aprovisionamiento.
#
# triggers_replace: si la IP pública cambia (por ejemplo, tras un `terraform taint` o
# recreación de la instancia), este recurso se vuelve a ejecutar automáticamente.
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

# terraform_data con provisioner "local-exec": ejecuta un comando LOCAL (en la máquina
# que corre Terraform, no en la instancia remota).
#
# En este caso lanza el playbook de Ansible contra el nodo de monitoreo ya creado.
# Esto integra Terraform + Ansible en un único flujo: `terraform apply` provee la
# infraestructura Y configura el software en un solo comando.
#
# ALTERNATIVA: Separar los dos pasos y usar `make provision` manualmente después.
# La integración automática es conveniente para el taller; en producción suele
# preferirse la separación para tener más control sobre cuándo se ejecuta Ansible.
resource "terraform_data" "ansible_provisioning" {
  # Re-ejecutar el aprovisionamiento si cambia la IP pública del nodo de monitoreo.
  triggers_replace = [
    aws_instance.monitoreo.public_ip
  ]

  provisioner "local-exec" {
    command = <<-CMD
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        --inventory ${local.ruta_inventario} \
        --private-key ${local.ruta_llave_ssh} \
        ${local.ansible_dir}/site.yaml
    CMD
  }

  depends_on = [local_file.ansible_inventory, local_sensitive_file.private_key, terraform_data.esperar_ssh_monitoreo]
}
