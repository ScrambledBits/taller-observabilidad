# Responsabilidad: lee los outputs del stack de aplicaciones (taller-iac) via remote state.
#
# ¿Por qué existe como archivo separado?
# Este archivo encapsula toda la dependencia cross-stack en un único lugar.
# Si en algún momento la fuente de los datos cambia (por ejemplo, se migra de remote state
# a variables de entrada), el cambio queda contenido aquí sin tocar los archivos de recursos.
#
# PRERREQUISITO CRÍTICO: El stack de apps (bootcamperu.tfstate) DEBE estar desplegado
# y su estado disponible en S3 antes de ejecutar `terraform plan` o `terraform apply`
# en este directorio. Si el estado no existe, el plan fallará con un error de acceso S3.
#
# Excepción segura: `terraform validate -backend=false` no accede al backend ni al remote
# state, por lo que funciona sin este prerrequisito. Útil para validar la sintaxis HCL
# en CI/CD antes de tener las credenciales o el estado disponibles.
#
# Comandos relevantes:
#   terraform validate -backend=false  → valida sintaxis HCL sin acceder al backend (seguro)
#   terraform plan                     → requiere que el stack de apps esté desplegado
#   terraform apply                    → requiere que el stack de apps esté desplegado

# terraform_remote_state: lee los outputs de OTRO stack de Terraform almacenado en S3.
#
# ¿Por qué dos stacks separados?
# El "stack de apps" (webstack-bootcamp) gestiona la VPC, subnets y los servidores de la
# aplicación. Este stack de observabilidad es un servicio transversal que necesita
# conocer esa infraestructura pero NO debe poder modificarla.
# La separación de stacks es una práctica de seguridad: cada equipo tiene permisos
# solo sobre su propio estado.
#
# ¿Cómo funciona?
# 1. El stack de apps exporta valores con bloques `output {}` en su código.
# 2. Terraform los escribe en su archivo de estado (bootcamperu.tfstate) en S3.
# 3. Este bloque `data` lee ese estado y expone esos valores bajo:
#    data.terraform_remote_state.apps.outputs.<nombre_output>
#
# Ejemplos de uso en este stack:
#   data.terraform_remote_state.apps.outputs.vpc_id
#   data.terraform_remote_state.apps.outputs.public_subnet_id
#   data.terraform_remote_state.apps.outputs.frontend_public_ip
#   data.terraform_remote_state.apps.outputs.backend_private_ip
data "terraform_remote_state" "apps" {
  backend = "s3"

  config = {
    bucket = "bootcamperu-tf-state"
    key    = "bootcamperu.tfstate"
    region = "us-east-1"
  }
}
