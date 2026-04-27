# Variables de configuración del stack de observabilidad.
#
# ORDEN DE PRIORIDAD (de menor a mayor):
#   1. El valor "default" definido aquí en el código
#   2. Archivo terraform.tfvars (o *.auto.tfvars) — para valores locales, no commitear
#   3. Variables de entorno con prefijo TF_VAR_: export TF_VAR_region="us-west-2"
#   4. Línea de comandos: terraform apply -var="region=us-west-2"
#
# Para el taller, los defaults son suficientes. Solo cambiarías las variables si
# quisieras desplegar en otra región o usar otro tipo de instancia.

variable "region" {
  type        = string
  description = "Región de AWS donde se desplegarán los recursos"
  default     = "us-east-1"
}

# Estas variables de red están definidas por consistencia con el stack de apps,
# pero este stack no crea VPC propia: usa la VPC del stack de apps via remote state.
# Se mantienen como referencia documental del rango de IPs del entorno.
variable "vpc_cidr" {
  type        = string
  description = "Bloque CIDR de la VPC (referencia — la VPC la gestiona el stack de apps)"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Bloque CIDR de la subnet pública (referencia — la subnet la gestiona el stack de apps)"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Bloque CIDR de la subnet privada (referencia — la subnet la gestiona el stack de apps)"
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

# locals: valores calculados internamente a partir de variables u otras expresiones.
# Diferencias clave vs variable {}:
#   - No son parametrizables desde fuera (no se pueden sobreescribir con -var o tfvars)
#   - Son ideales para transformaciones, concatenaciones y rutas derivadas
#   - Se acceden como local.<nombre> (sin "s" al final)
locals {
  # replace(): función built-in de Terraform. Convierte guiones en guiones bajos
  # porque algunos recursos de AWS (como los nombres de Security Groups) no aceptan
  # guiones en ciertos contextos.
  # Ejemplo: "taller-observabilidad-bootcamperu" → "taller_observabilidad_bootcamperu"
  prefijo_proyecto = replace(var.nombre_proyecto, "-", "_")

  # path.module: variable especial de Terraform que resuelve a la ruta ABSOLUTA del
  # directorio que contiene los archivos .tf que se están ejecutando.
  # Usar path.module en lugar de rutas hardcodeadas hace el código portable:
  # funciona sin importar desde qué directorio ejecutes `terraform apply`.
  ruta_llave_ssh  = "${path.module}/${var.nombre_llave_ssh}"
  ansible_dir     = "${path.module}/../ansible"
  ruta_inventario = "${path.module}/../ansible/inventario_terraform.yaml"
}
