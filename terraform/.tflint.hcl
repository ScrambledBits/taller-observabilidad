# TFLint: linter estático para Terraform. Detecta errores que 'terraform validate' no encuentra:
# tipos de instancia inválidos, regiones inexistentes, parámetros obsoletos, y malas prácticas
# específicas de cada proveedor. Funciona leyendo el código HCL sin conectarse a AWS.
#
# Ejecutar localmente:
#   tflint --config=.tflint.hcl --init   # descarga los plugins (solo la primera vez)
#   tflint --config=.tflint.hcl          # analiza todos los archivos .tf del directorio
#
# NOTA: cuando se invoca con --chdir=terraform (desde la raíz del proyecto),
# el --config se resuelve relativo a terraform/. Usar --config=.tflint.hcl.

# Plugin AWS: añade reglas específicas de AWS al análisis.
# Sin este plugin, TFLint solo verifica sintaxis HCL genérica.
# version = "0.40.0": versión fijada para garantizar resultados reproducibles.
# Compatible con TFLint 0.61.x. (0.41.x requiere TFLint 0.62+.)
plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  # call_module_type = "none": no analiza módulos externos referenciados con source = "...".
  # Sin esta opción, TFLint intentaría descargar módulos de internet, lo que fallaría
  # en CI/CD sin acceso a red o con módulos privados.
  call_module_type = "none"
}

# terraform_unused_declarations: deshabilitado porque este proyecto tiene tres variables
# CIDR (vpc_cidr, public_subnet_cidr, private_subnet_cidr) que son intencionalmente
# no usadas — sirven como referencia documental del rango de IPs del entorno.
# La VPC real proviene del remote state de taller-iac, no de estas variables.
rule "terraform_unused_declarations" {
  enabled = false
}
