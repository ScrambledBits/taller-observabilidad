# Genera un par de llaves RSA de 4096 bits localmente (el proceso ocurre en tu máquina,
# no en AWS). Terraform almacena la clave privada en el estado — no uses este enfoque
# en producción con estado compartido. En entornos reales se generan las llaves fuera de
# Terraform y se referencia solo la clave pública.
resource "tls_private_key" "bootcamp" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Escribe la clave privada en disco con permisos 0600 (solo el propietario puede leerla).
# `local_sensitive_file` marca el contenido como sensible: Terraform no lo muestra en logs
# ni en el output del plan. El archivo queda en terraform/ — incluirlo en .gitignore.
resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/${var.nombre_llave_ssh}"
  content         = tls_private_key.bootcamp.private_key_pem
  file_permission = "0600"
}

# Sube la clave pública a AWS como un Key Pair. AWS la instala automáticamente en
# ~/.ssh/authorized_keys de cada instancia EC2 que lo referencie, habilitando
# la autenticación SSH con la clave privada guardada localmente.
resource "aws_key_pair" "bootcamp" {
  key_name   = "${local.prefijo_proyecto}_${var.nombre_llave_ssh}"
  public_key = tls_private_key.bootcamp.public_key_openssh
}
