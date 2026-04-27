# Responsabilidad: declara los providers de Terraform y el backend de estado remoto.
#
# ¿Por qué existe como archivo separado?
# Centralizar los providers en un único archivo facilita actualizar versiones y
# cambiar el backend sin tocar los archivos de recursos. Es una convención ampliamente
# adoptada en la comunidad Terraform (equivalente a un "manifest" de dependencias).
#
# Restricciones operativas:
#   - Los bloques `backend {}` se evalúan ANTES de que Terraform cargue variables,
#     por lo que NO pueden usar var.*, local.* ni data.*. Si necesitas parametrizar
#     el backend, usa: terraform init -backend-config="bucket=mi-bucket"
#   - Cambiar el backend después de un apply ya existente requiere `terraform init -migrate-state`
#     para copiar el estado al nuevo destino antes de poder usar el nuevo backend.
#
# Comandos relevantes:
#   terraform init             → descarga los providers y conecta con el backend S3
#   terraform init -upgrade    → actualiza los providers a la última versión permitida
#   terraform providers        → lista los providers y sus versiones efectivas

# El bloque `terraform {}` declara los providers necesarios y el backend de estado.
# Fijar versiones exactas (o rangos estrechos) es una práctica recomendada:
# evita que una actualización automática del provider rompa el código sin aviso.
#
# Convención de versionado:
#   version = "6.37.0"  → versión exacta (más predecible, recomendado en equipos)
#   version = "~> 2.0"  → cualquier 2.x pero no 3.x (permite patches automáticos)
#   version = ">= 4.0"  → cualquier versión 4 o superior (menos restrictivo)
terraform {
  required_version = ">= 1.6"

  required_providers {
    # Provider oficial de AWS — gestiona todos los recursos de AWS (EC2, S3, SGs, etc.)
    aws = {
      source  = "hashicorp/aws"
      version = "6.37.0"
    }
    # Provider local — escribe archivos en disco (inventario Ansible, clave SSH privada)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    # Provider TLS — genera claves criptográficas (par RSA para SSH)
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend S3: el archivo .tfstate vive en S3 en lugar de en disco local.
  #
  # ¿Por qué backend remoto?
  # - Colaboración: todo el equipo comparte el mismo estado sin enviarse archivos.
  # - Seguridad: el estado contiene valores sensibles (IPs, claves); S3 + cifrado
  #   lo protege mejor que un archivo local commiteado por error.
  # - CI/CD: los pipelines pueden leer y escribir el estado sin acceso al repo.
  #
  # use_lockfile = true: crea un archivo .lock en S3 durante el apply para evitar
  #   que dos personas ejecuten `terraform apply` al mismo tiempo (condición de carrera).
  #   Antes se usaba DynamoDB para el lock; use_lockfile es la opción moderna (>= 1.10).
  #
  # encrypt = true: cifra el .tfstate en S3 con la clave del bucket (SSE-S3 o SSE-KMS).
  #
  # LIMITACION IMPORTANTE: Los bloques `backend {}` se evalúan ANTES de que Terraform
  # cargue las variables, por lo que NO pueden usar var.*, local.* ni data.*.
  # Para parametrizar el backend usa: terraform init -backend-config="bucket=mi-bucket"
  backend "s3" {
    bucket       = "bootcamperu-tf-state"
    key          = "taller-observabilidad.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # default_tags: aplica estas etiquetas a TODOS los recursos gestionados por este provider
  # de forma automática, sin necesidad de repetirlas en cada bloque `tags = {}`.
  #
  # ¿Para qué sirven las etiquetas en AWS?
  # - Filtrar recursos en la consola ("mostrar todos los recursos del taller")
  # - Control de costos: AWS Cost Explorer puede agrupar gastos por etiqueta Project
  # - Automatización: scripts que actúan sobre recursos con etiqueta Environment=dev
  # - Seguridad: políticas IAM que permiten acceso solo a recursos con etiqueta Team=DevOps
  #
  # En producción Environment se cambiaría a "staging" o "production" según el entorno.
  # Separar entornos por etiqueta (en lugar de por cuenta AWS) es aceptable para talleres;
  # en producción se prefieren cuentas AWS separadas por entorno (AWS Organizations).
  default_tags {
    tags = {
      Environment = "dev"
      Owner       = "Emilio Castro"
      Project     = "taller-observabilidad-bootcamperu"
      ManagedBy   = "terraform"
      Team        = "DevOps"
    }
  }
}
