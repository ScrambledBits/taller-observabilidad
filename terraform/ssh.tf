# tls_private_key: genera un par de claves RSA usando el provider TLS de Terraform.
#
# IMPORTANTE: La generación ocurre en tu máquina local y la clave privada
# se almacena en el estado de Terraform (.tfstate). Si el estado está en S3
# con cifrado habilitado (como en este taller), el riesgo es aceptable.
# En producción con estados compartidos o en CI/CD, genera las claves FUERA
# de Terraform y pasa solo la clave pública.
#
# RSA 4096 bits: tamaño de clave que ofrece seguridad robusta. 2048 bits es
# el mínimo recomendado; 4096 es la opción más segura (a costo de operaciones
# SSH ligeramente más lentas, imperceptible en la práctica).
resource "tls_private_key" "bootcamp" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# local_sensitive_file vs local_file:
# `local_sensitive_file` marca el contenido como sensible, lo que significa que
# Terraform NO lo muestra en los logs del plan/apply ni en el output de consola.
# Usa esto siempre para claves privadas, tokens, contraseñas.
#
# file_permission = "0600": permisos de Unix "solo el propietario puede leer y escribir".
# SSH rechaza conectarse si la clave privada tiene permisos más abiertos (ej: 0644),
# mostrando el error: "WARNING: UNPROTECTED PRIVATE KEY FILE!"
#
# El archivo se escribe en el directorio terraform/ del proyecto.
# Asegúrate de que está en .gitignore para no commitear la clave privada por accidente.
resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/${var.nombre_llave_ssh}"
  content         = tls_private_key.bootcamp.private_key_pem
  file_permission = "0600"
}

# aws_key_pair: registra la clave PÚBLICA en AWS (nunca la privada sale de tu máquina).
# AWS inyecta esta clave pública en el archivo ~/.ssh/authorized_keys del usuario ubuntu
# durante el primer arranque de la instancia EC2, habilitando la autenticación SSH.
#
# Flujo de autenticación SSH:
# 1. Tu máquina intenta conectar con la clave privada (.pem)
# 2. AWS/el servidor EC2 tiene la clave pública (registrada aquí)
# 3. Si la privada y la pública coinciden, la conexión se acepta sin contraseña
resource "aws_key_pair" "bootcamp" {
  key_name   = "${local.prefijo_proyecto}_${var.nombre_llave_ssh}"
  public_key = tls_private_key.bootcamp.public_key_openssh
}
