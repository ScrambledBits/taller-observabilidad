# Variables de configuración del stack de observabilidad.
# Para cambiar un valor, puedes:
#   1. Modificar el "default" aquí directamente
#   2. Crear un archivo terraform.tfvars con: nombre_variable = "valor"
#   3. Pasar el valor en la línea de comandos: terraform apply -var="region=us-west-2"
# Las opciones 2 y 3 tienen mayor prioridad que el default del código.

variable "region" {
  type        = string
  description = "Región de AWS donde se desplegarán los recursos"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "Bloque CIDR de la VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Bloque CIDR de la subnet pública"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Bloque CIDR de la subnet privada"
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  type        = string
  description = "Tipo de instancia EC2 para el nodo de monitoreo. t3.small tiene 2 vCPU y 2GB RAM, suficiente para el taller."
  default     = "t3.small"
  # validation: Terraform verifica esta condición antes de crear recursos.
  # Si el valor no cumple la condición, el plan falla con el error_message.
  # Evita que alguien use un tipo de instancia no soportado por accidente.
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "El tipo de instancia debe ser t3.micro, t3.small o t3.medium."
  }
}

variable "nombre_proyecto" {
  type        = string
  description = "Nombre del proyecto para identificar recursos en AWS. Se usa como prefijo en los nombres de los recursos."
  default     = "taller-observabilidad-bootcamperu"
}

variable "nombre_llave_ssh" {
  type        = string
  description = "Nombre del archivo PEM de la llave SSH generada. Se escribe en terraform/<nombre>."
  default     = "taller-observabilidad-bootcamperu.pem"
}

variable "usuario_ssh" {
  type        = string
  description = "Usuario del sistema operativo para conexiones SSH. En Ubuntu siempre es 'ubuntu'."
  default     = "ubuntu"
}

# locals: valores derivados que se calculan a partir de variables u otras expresiones.
# A diferencia de variable {}, los locals NO son parametrizables desde fuera.
# Son como constantes calculadas internamente.
locals {
  # replace: convierte guiones en guiones bajos para nombres de recursos de AWS
  # que no aceptan guiones (como algunos nombres de Security Groups).
  # Ejemplo: "taller-observabilidad-bootcamperu" → "taller_observabilidad_bootcamperu"
  prefijo_proyecto = replace(var.nombre_proyecto, "-", "_")

  # path.module: ruta absoluta al directorio donde está este archivo .tf.
  # Permite construir rutas relativas al proyecto sin hardcodear paths absolutos.
  # En este caso apunta al directorio terraform/ del proyecto.
  ruta_llave_ssh  = "${path.module}/${var.nombre_llave_ssh}"
  ansible_dir     = "${path.module}/../ansible"
  ruta_inventario = "${path.module}/../ansible/inventario_terraform.yaml"
}
