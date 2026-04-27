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
#
# PREREQUISITO: El stack de apps debe estar aplicado y su estado en S3 antes de
# ejecutar `terraform plan` aquí. Si el estado no existe, el plan fallará.
data "terraform_remote_state" "apps" {
  backend = "s3"

  config = {
    bucket = "bootcamperu-tf-state"
    key    = "bootcamperu.tfstate"
    region = "us-east-1"
  }
}
