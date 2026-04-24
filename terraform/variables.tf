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
  description = "Tipo de instancia EC2 para todas las instancias"
  default     = "t3.small"
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "El tipo de instancia debe ser t3.micro, t3.small o t3.medium."
  }
}

variable "nombre_proyecto" {
  type        = string
  description = "Nombre del proyecto para identificar recursos en AWS"
  default     = "taller-observabilidad-bootcamperu"
}

variable "nombre_llave_ssh" {
  type        = string
  description = "Nombre del archivo de la llave SSH generada"
  default     = "taller-observabilidad-bootcamperu.pem"
}

variable "usuario_ssh" {
  type        = string
  description = "Usuario del sistema operativo para conexiones SSH"
  default     = "ubuntu"
}

locals {
  prefijo_proyecto = replace(var.nombre_proyecto, "-", "_")
  ruta_llave_ssh   = "${path.module}/${var.nombre_llave_ssh}"
  ansible_dir      = "${path.module}/../ansible"
  ruta_inventario  = "${path.module}/../ansible/inventario_terraform.yaml"
}
